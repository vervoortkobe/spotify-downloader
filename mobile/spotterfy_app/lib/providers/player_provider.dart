import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/services/audio_handler.dart';
import 'package:spotterfy_app/services/auto_media_library.dart';
import 'package:spotterfy_app/services/download_service.dart';
import 'package:spotterfy_app/providers/equalizer_provider.dart';

class PlayerProvider extends ChangeNotifier {
  // just_audio player with the shared EQ pipeline (equalizer + loudness).
  // Audio focus/session config lives in SpotterfyAudioHandler._initSession.
  late final AudioPlayer _player;
  TrackModel? _currentTrack;
  List<TrackModel> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  bool _completed = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;

  TrackModel? get currentTrack => _currentTrack;
  List<TrackModel> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  Duration get buffered => _buffered;
  bool get hasQueue => _queue.isNotEmpty;
  bool get hasNext => _queue.isNotEmpty && _currentIndex < _queue.length - 1;
  bool get hasPrevious => _queue.isNotEmpty && _currentIndex > 0;

  bool _isRadioUrl(String url) {
    final u = url.toLowerCase();
    return u.contains('icecast.vrtcdn.be') ||
        u.contains('qmusic.be') ||
        u.contains('joe.be') ||
        u.contains('streamtheworld.com');
  }

  bool get isRadio =>
      _currentTrack != null &&
      (_currentTrack!.id.startsWith('radio_') ||
          _isRadioUrl(_currentTrack!.sourceUrl));
  Duration _radioMaxListened = Duration.zero;
  Timer? _radioDriftTimer;

  Duration get radioMaxListened => _radioMaxListened;

  // Single unified queue: library, radio and on-device storage tracks share one queue,
  // so storage songs can be queued/mixed with anything else.
  bool _isLocalPath(String p) => p.startsWith('/') || p.startsWith('file://');

  PlayerProvider() {
    _player = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: [androidEqualizer, androidLoudnessEnhancer],
      ),
    );
    _loadPlayerState();
    _requestNotificationPermission();
    // Let Android Auto start playback from rows it browses.
    AutoLibraryBridge.instance.bindPlayback((tracks, index) async {
      setQueue(tracks, startIndex: index);
      await play(tracks[index], queue: tracks);
    });
    // NOTE: do NOT init AudioService here. The constructor runs before
    // MainActivity is attached, which burns our single AudioService.init()
    // attempt (it can only be called once per process). Init lazily on
    // first play() instead, when the Activity is guaranteed ready.
    _player.positionStream.listen((pos) {
      _position = pos;
      if (isRadio && _isPlaying) {
        if (pos > _radioMaxListened) _radioMaxListened = pos;
      }
      audioHandler?.updatePosition(pos, _duration, _isPlaying);
      notifyListeners();
    });
    _player.durationStream.listen((dur) {
      // Live radio has no duration (null) - keep the previous value.
      if (dur == null) return;
      _duration = dur;
      // The real length is often the only place we ever learn it (scrapes and
      // local files can carry no duration), so write it back onto the track.
      // Everything downstream - mini player, queue rows, playlist lists - reads
      // `durationMs`, so this is what makes their lengths correct.
      final ms = dur.inMilliseconds;
      if (ms > 0) _applyDurationToTrack(ms);
      if (_currentTrack != null) {
        audioHandler?.updateTrack(
          _currentTrack!,
          queue: _queue,
          position: _position,
          duration: _duration,
          isPlaying: _isPlaying,
        );
      }
      notifyListeners();
    });
    _player.bufferedPositionStream.listen((buf) {
      _buffered = buf;
      audioHandler?.updateBuffered(buf);
      notifyListeners();
    });
    _player.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      _completed = state.processingState == ProcessingState.completed;
      if (_completed) {
        if (_queue.isNotEmpty && _currentIndex < _queue.length - 1) {
          next();
          return;
        } else {
          _isPlaying = false;
          audioHandler?.updatePosition(_position, _duration, false);
        }
      }
      _handleRadioDrift();
      audioHandler?.updatePosition(_position, _duration, _isPlaying);
      notifyListeners();
    });
  }

  /// Writes a learned track length back onto the current track and its queue
  /// entry, so every view that renders `durationMs` shows the real value
  /// instead of 0:00 / a blank.
  void _applyDurationToTrack(int ms) {
    final current = _currentTrack;
    if (current == null) return;
    if (current.durationMs == ms) return;
    final updated = current.copyWith(durationMs: ms);
    _currentTrack = updated;
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      final queued = _queue[_currentIndex];
      if (queued.durationMs != ms) {
        _queue[_currentIndex] = updated;
      }
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      // POST_NOTIFICATIONS is Android 13+ (33) only - on 11/12 it's auto-granted
      // permission_handler returns granted on <33, so gate to avoid prompt spam on 11
      if (await perm.Permission.notification.status.isGranted) return;
      // Only request on 33+ where runtime prompt exists; on 11/12 the channel still shows without prompt
      final s = await perm.Permission.notification.status;
      if (s.isDenied || s.isPermanentlyDenied) {
        await perm.Permission.notification.request();
      }
    } catch (_) {}
  }

  void _bindHandler() {
    bindAudioHandlerCallbacks(
      onPlay: () async => await resume(),
      onPause: () async => await pause(),
      onSkipNext: () async => await next(),
      onSkipPrev: () async => await previous(),
      onSeek: (pos) async => await seekTo(pos),
    );
    final h = audioHandler;
    if (h != null) h.onSeekRequested = (pos) async => await seekTo(pos);
  }

  void _handleRadioDrift() {
    _radioDriftTimer?.cancel();
    _radioDriftTimer = null;
    if (!isRadio) return;
    if (!_isPlaying) {
      // When radio paused, progress drifts left (fall behind live) at 1x speed
      _radioDriftTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_position.inMilliseconds > 0) {
          _position = Duration(milliseconds: _position.inMilliseconds - 1000);
          if (_position.isNegative) _position = Duration.zero;
          audioHandler?.updatePosition(_position, _duration, false);
          notifyListeners();
        } else {
          _radioDriftTimer?.cancel();
        }
      });
    }
  }

  Future<void> play(TrackModel track, {List<TrackModel>? queue}) async {
    if (queue != null) {
      _queue = List.from(queue);
      _currentIndex = queue.indexWhere((e) => e.id == track.id);
      if (_currentIndex == -1) _currentIndex = 0;
    } else if (_queue.isEmpty) {
      _queue = [track];
      _currentIndex = 0;
    } else {
      final idx = _queue.indexWhere((e) => e.id == track.id);
      if (idx >= 0) {
        _currentIndex = idx;
      } else {
        _queue.add(track);
        _currentIndex = _queue.length - 1;
      }
    }
    _currentTrack = track;
    _position = Duration.zero;
    _duration = Duration.zero;
    _buffered = Duration.zero;
    if (isRadio) _radioMaxListened = Duration.zero;
    // A track is loading from here until playback actually begins. During this
    // window both `_isPlaying` and `_player.playing` are false, so a pause tap
    // used to be read as "not playing", turned into a play command, and then
    // silently overwritten when the load finished - which is why pressing pause
    // during a slow load appeared to do nothing.
    _starting = true;
    _pauseRequested = false;
    _handleRadioDrift();
    notifyListeners();
    await ensureAudioHandler();
    _bindHandler();
    final h = audioHandler;
    if (h != null) {
      await h.updateTrack(
        track,
        queue: _queue,
        position: Duration.zero,
        duration: Duration.zero,
        isPlaying: true,
      );
      h.onSeekRequested = (pos) async => await seekTo(pos);
    } else {
      debugPrint('[Player] audioHandler is null — notification will not show');
    }
    // Local storage files: play directly from device, no backend
    if (_isLocalPath(track.sourceUrl)) {
      final path = track.sourceUrl.replaceFirst('file://', '');
      try {
        await _player.setFilePath(path).timeout(const Duration(seconds: 30));
        await _player.play().timeout(const Duration(seconds: 30));
        await _onTrackStarted();
      } catch (e) {
        debugPrint('[Player] local file failed: $e');
      }
      _starting = false;
      _savePlayerState();
      return;
    }

    // A track downloaded from inside the app is played from disk, so it starts
    // instantly and costs no bandwidth. Falls through to streaming when the
    // file is absent or unreadable.
    final downloaded = await _downloadedPathFor(track);
    if (downloaded != null) {
      try {
        await _player
            .setFilePath(downloaded)
            .timeout(const Duration(seconds: 30));
        await _player.play().timeout(const Duration(seconds: 30));
        await _onTrackStarted();
        _starting = false;
        _savePlayerState();
        return;
      } catch (e) {
        debugPrint('[Player] downloaded file failed, streaming instead: $e');
      }
    }
    // Radio live streams (icecast etc) play directly, not via backend proxy
    final primary = track.sourceUrl.isNotEmpty
        ? (isDirectRadioUrl(track.sourceUrl) || track.id.startsWith('radio_')
              ? track.sourceUrl
              : ApiService.streamTrackUrl(track.sourceUrl))
        : null;
    final fallback = ApiService.streamTrackUrl(
      'ytsearch1:${track.title} ${track.artists} audio',
    );

    // No pre-flight HEAD request here on purpose. `setAudioSource` performs the
    // real request anyway, and doing a throwaway HEAD first just added a full
    // extra round-trip *in front of* it on every single track. The next track is
    // primed in the background instead (see [_prefetchNextSource]), so by the
    // time it is needed the server-side extraction is already cached.
    try {
      final url = primary ?? fallback;
      // No explicit `stop()`: `setAudioSource` stops the current source itself,
      // so calling it first was a wasted platform round-trip per track.
      await _player
          .setAudioSource(AudioSource.uri(Uri.parse(url)))
          .timeout(const Duration(seconds: 30));
      await _player.play().timeout(const Duration(seconds: 30));
      await _onTrackStarted();
    } catch (e) {
      debugPrint('[Player] primary failed: $e');
      try {
        await _player
            .setAudioSource(AudioSource.uri(Uri.parse(fallback)))
            .timeout(const Duration(seconds: 35));
        await _player.play().timeout(const Duration(seconds: 35));
        await _onTrackStarted();
      } catch (e2) {
        debugPrint('[Player] fallback failed: $e2');
      }
    }
    _starting = false;
    _savePlayerState();
  }

  /// Warms the server-side extraction for the *next* queue track.
  ///
  /// The backend caches the resolved audio URL, so touching it a couple of
  /// seconds early means the next track skips the slow yt-dlp resolution and
  /// starts almost immediately. Fire-and-forget: a failure here is harmless
  /// because the real load still falls back normally.
  void _prefetchNextSource() {
    if (!isRadio) return;
    final next = _currentIndex + 1;
    if (next < 0 || next >= _queue.length) return;
    final upcoming = _queue[next];
    // Local files and direct radio streams need no resolution.
    if (_isLocalPath(upcoming.sourceUrl)) return;
    if (isDirectRadioUrl(upcoming.sourceUrl)) return;
    final url = ApiService.streamTrackUrl(upcoming.sourceUrl);
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(const Duration(seconds: 2), () {
      try {
        http
            .head(Uri.parse(url))
            .timeout(const Duration(seconds: 8))
            .then((_) {}, onError: (_) {});
      } catch (_) {}
    });
  }

  /// Absolute path of the app-downloaded file for [track], if one exists.
  ///
  /// Looks the track up by id **and** by source URL: tracks can be re-imported
  /// or matched across playlists with different ids, and the download index is
  /// keyed on whichever id was used when it was saved.
  Future<String?> _downloadedPathFor(TrackModel track) async {
    try {
      await DownloadService.instance.ensureLoaded();
      final svc = DownloadService.instance;
      final candidates = <String>[track.id, track.sourceUrl];
      // Also try the id without a `yt_`-style prefix, and the URL without query.
      for (final c in candidates) {
        final p = svc.localPathFor(c);
        if (p != null && await File(p).exists()) return p;
      }
      for (final e in svc.entries.values) {
        if (track.sourceUrl.isNotEmpty && e.title == track.title) {
          final p = svc.localPathFor(e.trackId);
          if (p != null && await File(p).exists()) return p;
        }
      }
      return null;
    } catch (e) {
      debugPrint('[Player] download lookup failed: $e');
      return null;
    }
  }

  /// Marks a track as genuinely started.
  ///
  /// Honours a pause that was pressed while the track was still loading, so the
  /// page never starts playing something the user already cancelled.
  Future<void> _onTrackStarted() async {
    _completed = false;
    if (_pauseRequested) {
      _pauseRequested = false;
      _isPlaying = false;
      notifyListeners();
      await _player.pause();
      return;
    }
    _isPlaying = true;
    notifyListeners();
    // Get the following track resolving on the server while this one plays.
    _prefetchNextSource();
  }

  Future<void> _startPlayback() async {
    // just_audio resumes from the completed state otherwise - restart instead.
    if (_completed) {
      await _player.seek(Duration.zero);
      _completed = false;
    }
    await _player.play();
  }

  /// Guards against overlapping play/pause requests: `_startPlayback()` can
  /// await network work for seconds, and without a guard two taps would
  /// interleave.
  /// A track is loading (source resolution / buffering). During this window the
  /// player reports `playing == false`, so this flag is what lets a pause tap be
  /// understood as "stop the thing that is about to start".
  bool _starting = false;

  /// The user pressed pause before the track finished loading.
  bool _pauseRequested = false;

  Timer? _prefetchTimer;

  /// Live radio streams are played directly rather than through the backend
  /// proxy. Shared by [play] and [_prefetchNextSource] so both agree on what
  /// needs resolving.
  static bool isDirectRadioUrl(String url) {
    final u = url.toLowerCase();
    return u.contains('icecast.vrtcdn.be') ||
        u.contains('qmusic.be') ||
        u.contains('joe.be') ||
        u.contains('streamtheworld.com') ||
        (u.contains('.mp3') && u.contains('dist='));
  }

  /// Guards against overlapping play/pause requests: `_startPlayback()` can
  /// await network work for seconds.
  bool _toggling = false;

  /// Taps that arrived while a toggle was in flight. These used to be discarded
  /// outright, which is the other half of "pause sometimes does nothing".
  int _pendingToggles = 0;

  Future<void> togglePlayPause() {
    _pendingToggles++;
    if (_toggling) return Future<void>.value();
    return _drainToggles();
  }

  /// Applies queued toggles one at a time.
  ///
  /// Each toggle flips the state, so a burst of taps only needs applying by
  /// parity - replaying every tap in order would just re-run a slow start
  /// several times for exactly the same end result.
  Future<void> _drainToggles() async {
    _toggling = true;
    try {
      while (_pendingToggles > 0) {
        var queued = 0;
        while (_pendingToggles > 0) {
          _pendingToggles--;
          queued++;
        }
        if (queued.isOdd) await _applyToggle();
      }
    } finally {
      _toggling = false;
    }
  }

  Future<void> _applyToggle() async {
    // Decide from BOTH sources *plus* "a track is loading". Treating it as
    // playing when any of them says so is what makes pause reliable: using only
    // `_isPlaying` (the mirror) missed a pause whenever the mirror lagged, and
    // using only `_player.playing` missed one while the source was loading.
    final actuallyPlaying = _player.playing || _isPlaying || _starting;
    final willPlay = !actuallyPlaying;
    // Optimistic so the button reacts on the first frame, and deliberately not
    // re-read from the player afterwards - that discarded the flip before the
    // audio pipeline reported back and left the glyph stuck.
    _isPlaying = willPlay;
    notifyListeners();
    try {
      if (willPlay) {
        await _startPlayback();
        // `_startPlayback` swallows its own errors and silently falls back to a
        // second URL, so a source that never started leaves the optimistic value
        // lying. `idle` is the only state that proves nothing loaded.
        if (!_player.playing &&
            _player.processingState == ProcessingState.idle) {
          _isPlaying = false;
        }
      } else if (_starting) {
        // Nothing is audible yet, so don't pause an unloaded player - just make
        // sure the track doesn't start under the user's finger.
        _pauseRequested = true;
        _isPlaying = false;
      } else {
        await _player.pause();
        // A completed pause always settles on false, whatever `playing` happens
        // to report at this instant.
        _isPlaying = false;
      }
      audioHandler?.updatePosition(_position, _duration, _isPlaying);
    } catch (e) {
      debugPrint('[Player] toggle failed: $e');
      _isPlaying = _player.playing;
    } finally {
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _player.pause();
    audioHandler?.updatePosition(_position, _duration, false);
  }

  Future<void> resume() async {
    await _startPlayback();
    audioHandler?.updatePosition(_position, _duration, true);
  }

  Future<void> seekTo(Duration position) async {
    if (isRadio) {
      // Radio: only back within listened window, never forward beyond live edge
      final clamped = Duration(
        milliseconds: position.inMilliseconds.clamp(
          0,
          _radioMaxListened.inMilliseconds,
        ),
      );
      await _player.seek(clamped);
      _position = clamped;
      audioHandler?.updatePosition(clamped, _duration, _isPlaying);
      notifyListeners();
      return;
    }
    await _player.seek(position);
    audioHandler?.updatePosition(position, _duration, _isPlaying);
  }

  Future<void> next() async {
    if (isRadio) return;
    if (_queue.isEmpty || _currentIndex >= _queue.length - 1) return;
    _currentIndex++;
    await play(_queue[_currentIndex], queue: _queue);
  }

  Future<void> previous() async {
    if (isRadio) {
      // Radio: only seek back within listened window, no track switch
      await seekTo(Duration.zero);
      return;
    }
    if (_queue.isEmpty || _currentIndex <= 0) return;
    if (_position.inSeconds > 3) {
      await seekTo(Duration.zero);
      return;
    }
    _currentIndex--;
    await play(_queue[_currentIndex], queue: _queue);
  }

  Future<void> stop() async {
    await _player.stop();
    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    audioHandler?.updatePosition(_position, _duration, false);
    notifyListeners();
  }

  void setQueue(List<TrackModel> tracks, {int startIndex = 0}) {
    _queue = List.from(tracks);
    _currentIndex = startIndex.clamp(0, tracks.isEmpty ? 0 : tracks.length - 1);
    audioHandler?.setQueue(tracks, startIndex: startIndex);
    notifyListeners();
  }

  Future<void> playFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    await play(_queue[index], queue: _queue);
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    if (_currentIndex >= index) {
      _currentIndex = (_currentIndex - 1).clamp(-1, _queue.length - 1);
    }
    if (_currentIndex < 0 && _queue.isNotEmpty) {
      _currentIndex = 0;
    } else if (_queue.isEmpty) {
      _currentTrack = null;
      _currentIndex = -1;
      _isPlaying = false;
    }
    notifyListeners();
  }

  void clearQueue() {
    _queue.clear();
    _currentIndex = -1;
    _currentTrack = null;
    _isPlaying = false;
    notifyListeners();
  }

  /// Moves the queue entry at [from] to [to], keeping [_currentIndex] pointing
  /// at the *same track*.
  ///
  /// The index has to follow the track rather than the slot: moving the playing
  /// track one place up would otherwise leave playback pointing at whatever
  /// slid into the old position.
  void moveQueueItem(int from, int to) {
    if (from < 0 || from >= _queue.length) return;
    if (to < 0 || to >= _queue.length) return;
    if (from == to) return;
    final movingIsCurrent = from == _currentIndex;
    final item = _queue.removeAt(from);
    _queue.insert(to, item);
    if (movingIsCurrent) {
      _currentIndex = to;
    } else if (_currentIndex > from && _currentIndex <= to) {
      // The playing track shifted one place earlier.
      _currentIndex -= 1;
    } else if (_currentIndex < from && _currentIndex >= to) {
      // The playing track shifted one place later.
      _currentIndex += 1;
    }
    audioHandler?.setQueue(_queue, startIndex: _currentIndex);
    notifyListeners();
  }

  /// Moves [from] up one place, if it can.
  void moveQueueUp(int from) => moveQueueItem(from, from - 1);

  /// Moves [from] down one place, if it can.
  void moveQueueDown(int from) => moveQueueItem(from, from + 1);

  /// Removes several queue entries at once.
  ///
  /// Indices are resolved against the *original* queue and removed highest
  /// first, so the caller can pass a UI selection straight through without
  /// re-computing indices as the list shifts underneath.
  void removeFromQueueMany(Iterable<int> indices) {
    final targets = indices.toSet().where((i) => i >= 0 && i < _queue.length);
    if (targets.isEmpty) return;
    final removedCurrent = targets.contains(_currentIndex);
    final ordered = targets.toList()..sort((a, b) => b.compareTo(a));
    for (final i in ordered) {
      _queue.removeAt(i);
    }
    if (_queue.isEmpty) {
      _currentTrack = null;
      _currentIndex = -1;
      _isPlaying = false;
    } else if (removedCurrent) {
      // Playback continues from whatever now sits at the old slot, clamped.
      _currentIndex = _currentIndex.clamp(0, _queue.length - 1);
    } else if (_currentIndex > ordered.last) {
      _currentIndex -= ordered.length;
    }
    audioHandler?.setQueue(_queue, startIndex: _currentIndex);
    notifyListeners();
  }

  /// Moves every selected entry up one place, keeping their relative order.
  ///
  /// Moving a multi-row selection one item at a time would shuffle it instead
  /// of shifting the block, so only the lowest selected index actually moves.
  void moveQueueBlockUp(List<int> indices) {
    final sel = indices.where((i) => i >= 0 && i < _queue.length).toSet();
    if (sel.isEmpty) return;
    final block = sel.toList()..sort();
    final lowest = block.first;
    if (lowest == 0) return;
    final wasCurrent = lowest == _currentIndex;
    final item = _queue.removeAt(lowest);
    _queue.insert(lowest - 1, item);
    if (wasCurrent) {
      _currentIndex = lowest - 1;
    } else if (_currentIndex >= lowest) {
      // Everything from `lowest` onwards shifted up a slot.
      _currentIndex += 1;
    }
    audioHandler?.setQueue(_queue, startIndex: _currentIndex);
    notifyListeners();
  }

  /// Moves every selected entry down one place, keeping their relative order.
  void moveQueueBlockDown(List<int> indices) {
    final sel = indices.where((i) => i >= 0 && i < _queue.length).toSet();
    if (sel.isEmpty) return;
    final block = sel.toList()..sort();
    final highest = block.last;
    if (highest >= _queue.length - 1) return;
    final wasCurrent = highest == _currentIndex;
    final item = _queue.removeAt(highest);
    _queue.insert(highest + 1, item);
    if (wasCurrent) {
      _currentIndex = highest + 1;
    } else if (_currentIndex <= highest) {
      // Everything up to `highest` shifted down a slot.
      _currentIndex -= 1;
    }
    audioHandler?.setQueue(_queue, startIndex: _currentIndex);
    notifyListeners();
  }

  void addToQueue(TrackModel track) {
    _queue.add(track);
    audioHandler?.setQueue(
      _queue,
      startIndex: _currentIndex.clamp(0, _queue.length - 1),
    );
    notifyListeners();
  }

  void addToQueueNext(TrackModel track) {
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      _queue.insert(_currentIndex + 1, track);
    } else {
      _queue.add(track);
    }
    audioHandler?.setQueue(
      _queue,
      startIndex: _currentIndex.clamp(0, _queue.length - 1),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _radioDriftTimer?.cancel();
    _prefetchTimer?.cancel();
    _savePlayerState();
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadPlayerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getString('player_queue');
      final currentIndex = prefs.getInt('player_current_index') ?? -1;
      final positionMs = prefs.getInt('player_position_ms') ?? 0;
      if (queueJson != null) {
        final List<dynamic> queueData = jsonDecode(queueJson);
        _queue = queueData.map((data) => TrackModel.fromJson(data)).toList();
        if (currentIndex >= 0 && currentIndex < _queue.length) {
          _currentIndex = currentIndex;
          _currentTrack = _queue[_currentIndex];
          _position = Duration(milliseconds: positionMs);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[Player] Failed to load state: $e');
    }
  }

  Future<void> _savePlayerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_queue.isNotEmpty) {
        final queueJson = jsonEncode(_queue.map((t) => t.toJson()).toList());
        await prefs.setString('player_queue', queueJson);
        await prefs.setInt('player_current_index', _currentIndex);
        await prefs.setBool('player_was_playing', _isPlaying);
        await prefs.setInt('player_position_ms', _position.inMilliseconds);
      } else {
        await prefs.remove('player_queue');
        await prefs.remove('player_current_index');
        await prefs.remove('player_was_playing');
        await prefs.remove('player_position_ms');
      }
    } catch (e) {
      debugPrint('[Player] Failed to save state: $e');
    }
  }
}
