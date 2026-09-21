import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/services/audio_handler.dart';
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
    return u.contains('icecast.vrtcdn.be') || u.contains('qmusic.be') || u.contains('joe.be') || u.contains('streamtheworld.com');
  }

  bool get isRadio => _currentTrack != null && (_currentTrack!.id.startsWith('radio_') || _isRadioUrl(_currentTrack!.sourceUrl));
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
      if (_currentTrack != null) audioHandler?.updateTrack(_currentTrack!, queue: _queue, position: _position, duration: _duration, isPlaying: _isPlaying);
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
    _handleRadioDrift();
    notifyListeners();
    await ensureAudioHandler();
    _bindHandler();
    final h = audioHandler;
    if (h != null) {
      await h.updateTrack(track, queue: _queue, position: Duration.zero, duration: Duration.zero, isPlaying: true);
      h.onSeekRequested = (pos) async => await seekTo(pos);
    } else {
      debugPrint('[Player] audioHandler is null — notification will not show');
    }
    // Local storage files: play directly from device, no backend
    if (_isLocalPath(track.sourceUrl)) {
      final path = track.sourceUrl.replaceFirst('file://', '');
      try {
        await _player.stop();
        await _player.setFilePath(path).timeout(const Duration(seconds: 30));
        await _player.play().timeout(const Duration(seconds: 30));
        _completed = false;
        _isPlaying = true;
        notifyListeners();
      } catch (e) {
        debugPrint('[Player] local file failed: $e');
      }
      _savePlayerState();
      return;
    }
    // Radio live streams (icecast etc) play directly, not via backend proxy
    bool isDirectRadio(String url) {
      final u = url.toLowerCase();
      return u.contains('icecast.vrtcdn.be') || u.contains('qmusic.be') || u.contains('joe.be') || u.contains('streamtheworld.com') || u.contains('.mp3') && u.contains('dist=') || track.id.startsWith('radio_');
    }

    final primary = track.sourceUrl.isNotEmpty
        ? (isDirectRadio(track.sourceUrl) ? track.sourceUrl : ApiService.streamTrackUrl(track.sourceUrl))
        : null;
    final fallback = ApiService.streamTrackUrl('ytsearch1:${track.title} ${track.artists} audio');
    Future<void> warm(String url) async {
      try {
        await http.head(Uri.parse(url)).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    try {
      await _player.stop();
      final url = primary ?? fallback;
      await warm(url);
      await _player.setAudioSource(AudioSource.uri(Uri.parse(url))).timeout(const Duration(seconds: 30));
      await _player.play().timeout(const Duration(seconds: 30));
      _completed = false;
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[Player] primary failed: $e');
      try {
        await _player.stop();
        await warm(fallback);
        await _player.setAudioSource(AudioSource.uri(Uri.parse(fallback))).timeout(const Duration(seconds: 35));
        await _player.play().timeout(const Duration(seconds: 35));
        _completed = false;
        _isPlaying = true;
        notifyListeners();
      } catch (e2) {
        debugPrint('[Player] fallback failed: $e2');
      }
    }
    _savePlayerState();
  }

  Future<void> _startPlayback() async {
    // just_audio resumes from the completed state otherwise - restart instead.
    if (_completed) {
      await _player.seek(Duration.zero);
      _completed = false;
    }
    await _player.play();
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
      audioHandler?.updatePosition(_position, _duration, false);
    } else {
      await _startPlayback();
      audioHandler?.updatePosition(_position, _duration, true);
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
        milliseconds: position.inMilliseconds.clamp(0, _radioMaxListened.inMilliseconds),
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

  void addToQueue(TrackModel track) {
    _queue.add(track);
    audioHandler?.setQueue(_queue, startIndex: _currentIndex.clamp(0, _queue.length - 1));
    notifyListeners();
  }

  void addToQueueNext(TrackModel track) {
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      _queue.insert(_currentIndex + 1, track);
    } else {
      _queue.add(track);
    }
    audioHandler?.setQueue(_queue, startIndex: _currentIndex.clamp(0, _queue.length - 1));
    notifyListeners();
  }

  @override
  void dispose() {
    _radioDriftTimer?.cancel();
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
