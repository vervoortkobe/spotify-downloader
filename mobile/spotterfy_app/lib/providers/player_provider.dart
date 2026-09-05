import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/services/audio_handler.dart';

class PlayerProvider extends ChangeNotifier {
  AudioPlayer? _fallbackPlayer;
  AudioPlayer get _player {
    final h = audioHandler;
    if (h != null) return h.player;
    _fallbackPlayer ??= AudioPlayer();
    return _fallbackPlayer!;
  }

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
    _player.positionStream.listen((pos) {
      _position = pos;
      notifyListeners();
    });
    _player.durationStream.listen((dur) {
      if (dur != null) {
        _duration = dur;
        notifyListeners();
      }
    });
    _player.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      notifyListeners();
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      final h = audioHandler;
      if (h != null) {
        h.playbackState.listen((state) {
          _isPlaying = state.playing;
          notifyListeners();
        });
      }
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
    try {
      await ensureAudioHandler();
      final h = audioHandler;
      if (h != null) {
        await h.playTrack(track, queue: _queue);
      } else {
        final url = track.sourceUrl.isNotEmpty ? track.sourceUrl : 'ytsearch1:${track.title} ${track.artists} audio';
        final streamUrl = url.startsWith('http') ? url : 'https://spotdl.vervoortkobe.be.eu.org/api/stream?source_url=${Uri.encodeComponent(url)}';
        await _player.setAudioSource(AudioSource.uri(Uri.parse(streamUrl)));
        await _player.play();
      }
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[Player] play failed: $e');
    }
    _savePlayerState();
  }

  Future<void> togglePlayPause() async {
    final h = audioHandler;
    if (_isPlaying) {
      if (h != null) {
        await h.pause();
      } else {
        await _player.pause();
      }
    } else {
      if (h != null) {
        await h.play();
      } else {
        await _player.play();
      }
    }
  }

  Future<void> pause() async {
    final h = audioHandler;
    if (h != null) {
      await h.pause();
    } else {
      await _player.pause();
    }
  }

  Future<void> resume() async {
    final h = audioHandler;
    if (h != null) {
      await h.play();
    } else {
      await _player.play();
    }
  }

  Future<void> seekTo(Duration position) async {
    final h = audioHandler;
    if (h != null) {
      await h.seek(position);
    } else {
      await _player.seek(position);
    }
  }

  Future<void> next() async {
    if (_queue.isEmpty || _currentIndex >= _queue.length - 1) return;
    _currentIndex++;
    await play(_queue[_currentIndex], queue: _queue);
  }

  Future<void> previous() async {
    if (_queue.isEmpty || _currentIndex <= 0) return;
    if (_position.inSeconds > 3) {
      final h = audioHandler;
      if (h != null) {
        await h.seek(Duration.zero);
      } else {
        await _player.seek(Duration.zero);
      }
      return;
    }
    _currentIndex--;
    await play(_queue[_currentIndex], queue: _queue);
  }

  Future<void> stop() async {
    final h = audioHandler;
    if (h != null) {
      await h.stop();
    } else {
      await _player.stop();
    }
    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
  }

  void setQueue(List<TrackModel> tracks, {int startIndex = 0}) {
    _queue = List.from(tracks);
    _currentIndex = startIndex.clamp(0, tracks.isEmpty ? 0 : tracks.length - 1);
    final h = audioHandler;
    if (h != null) {
      h.setQueue(tracks, startIndex: startIndex);
    }
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
    final h = audioHandler;
    if (h != null) {
      h.setQueue(_queue, startIndex: _currentIndex.clamp(0, _queue.length - 1));
    }
    notifyListeners();
  }

  void addToQueueNext(TrackModel track) {
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      _queue.insert(_currentIndex + 1, track);
    } else {
      _queue.add(track);
    }
    final h = audioHandler;
    if (h != null) {
      h.setQueue(_queue, startIndex: _currentIndex.clamp(0, _queue.length - 1));
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _savePlayerState();
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
