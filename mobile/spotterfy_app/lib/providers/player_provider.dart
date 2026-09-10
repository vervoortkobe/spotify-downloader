import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/services/audio_handler.dart';

class PlayerProvider extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  TrackModel? _currentTrack;
  List<TrackModel> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  TrackModel? get currentTrack => _currentTrack;
  List<TrackModel> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  AudioPlayer get player => _player;
  bool get hasQueue => _queue.isNotEmpty;
  bool get hasNext => _queue.isNotEmpty && _currentIndex < _queue.length - 1;
  bool get hasPrevious => _queue.isNotEmpty && _currentIndex > 0;

  PlayerProvider() {
    _loadPlayerState();
    _player.setAudioContext(AudioContext(
      android: AudioContextAndroid(
        isSpeakerphoneOn: false,
        stayAwake: true,
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.gain,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: {AVAudioSessionOptions.mixWithOthers},
      ),
    ));
    _player.setReleaseMode(ReleaseMode.stop);
    _player.onPositionChanged.listen((pos) {
      _position = pos;
      audioHandler?.updatePosition(pos, _duration, _isPlaying);
      notifyListeners();
    });
    _player.onDurationChanged.listen((dur) {
      _duration = dur;
      if (_currentTrack != null) audioHandler?.updateTrack(_currentTrack!, queue: _queue, position: _position, duration: _duration, isPlaying: _isPlaying);
      notifyListeners();
    });
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      audioHandler?.updatePosition(_position, _duration, _isPlaying);
      notifyListeners();
    });
    _player.onPlayerComplete.listen((_) {
      if (_queue.isNotEmpty && _currentIndex < _queue.length - 1) {
        next();
      } else {
        _isPlaying = false;
        audioHandler?.updatePosition(_position, _duration, false);
        notifyListeners();
      }
    });
    // hook MediaSession seek (drag in Now Bar) -> seek audioplayers
    Future.delayed(const Duration(milliseconds: 500), () {
      final h = audioHandler;
      if (h != null) {
        h.onSeekRequested = (pos) async => await seekTo(pos);
      }
    });
    // poll for handler late init
    Timer.periodic(const Duration(seconds: 1), (t) {
      final h = audioHandler;
      if (h != null && h.onSeekRequested == null) {
        h.onSeekRequested = (pos) async => await seekTo(pos);
        t.cancel();
      }
      if (h != null) t.cancel();
    });
  }

  Future<void> play(TrackModel track, {List<TrackModel>? queue}) async {
    if (queue != null) {
      _queue = queue;
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
    notifyListeners();
    await ensureAudioHandler();
    final h = audioHandler;
    if (h != null) {
      await h.updateTrack(track, queue: _queue, position: Duration.zero, duration: Duration.zero, isPlaying: true);
      h.onSeekRequested = (pos) async => await seekTo(pos);
    }
    final primary = track.sourceUrl.isNotEmpty ? ApiService.streamTrackUrl(track.sourceUrl) : null;
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
      await _player.play(UrlSource(url)).timeout(const Duration(seconds: 30));
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[Player] primary failed: $e');
      try {
        await _player.stop();
        await warm(fallback);
        await _player.play(UrlSource(fallback)).timeout(const Duration(seconds: 35));
        _isPlaying = true;
        notifyListeners();
      } catch (e2) {
        debugPrint('[Player] fallback failed: $e2');
      }
    }
    _savePlayerState();
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
      audioHandler?.updatePosition(_position, _duration, false);
    } else {
      await _player.resume();
      audioHandler?.updatePosition(_position, _duration, true);
    }
  }

  Future<void> pause() async {
    await _player.pause();
    audioHandler?.updatePosition(_position, _duration, false);
  }

  Future<void> resume() async {
    await _player.resume();
    audioHandler?.updatePosition(_position, _duration, true);
  }

  Future<void> seekTo(Duration position) async {
    await _player.seek(position);
    audioHandler?.updatePosition(position, _duration, _isPlaying);
  }

  Future<void> next() async {
    if (_queue.isEmpty || _currentIndex >= _queue.length - 1) return;
    _currentIndex++;
    await play(_queue[_currentIndex], queue: _queue);
  }

  Future<void> previous() async {
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
