import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/services/notification_service.dart';

class PlayerProvider extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  TrackModel? _currentTrack;
  List<TrackModel> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _notifTimer;
  
  // Prefetching for faster playback
  final Map<String, String> _prefetchedUrls = {};
  bool _isPrefetching = false;

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
    final notif = NotificationService();
    notif.onPlayPause = togglePlayPause;
    notif.onNext = next;
    notif.onPrevious = previous;
    notif.onClose = () async {
      await stop();
      notif.cancelPlaybackNotification();
    };
    _player.onPositionChanged.listen((pos) {
      _position = pos;
      notifyListeners();
    });
    _player.onDurationChanged.listen((dur) {
      _duration = dur;
      notifyListeners();
    });
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      notifyListeners();
      _scheduleNotifUpdates();
    });
    _player.onPlayerComplete.listen((_) {
      if (_queue.isNotEmpty && _currentIndex < _queue.length - 1) next();
    });
    
    // Prefetch next tracks for faster playback
    _prefetchNextTracks();
  }

  Future<void> _prefetchNextTracks() async {
    if (_isPrefetching || _queue.isEmpty) return;
    _isPrefetching = true;
    
    try {
      // Prefetch next 3 tracks concurrently for faster loading
      final prefetchIndices = List.generate(3, (i) => _currentIndex + 1 + i)
        .where((index) => index >= 0 && index < _queue.length)
        .take(3);
      
      await Future.wait(prefetchIndices.map((index) async {
        final track = _queue[index];
        if (!_prefetchedUrls.containsKey(track.id)) {
          final url = track.sourceUrl.isNotEmpty 
            ? ApiService.streamTrackUrl(track.sourceUrl) 
            : ApiService.streamTrackUrl('ytsearch1:${track.title} ${track.artists} audio');
          _prefetchedUrls[track.id] = url;
          // Warm up the URL
          try {
            await http.head(Uri.parse(url)).timeout(const Duration(seconds: 3));
          } catch (_) {}
        }
      }));
    } finally {
      _isPrefetching = false;
    }
  }

  void _scheduleNotifUpdates() {
    _notifTimer?.cancel();
    if (!_isPlaying || _currentTrack == null) return;
    _notifTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateNotification();
    });
  }

  void _updateNotification() {
    if (_currentTrack == null) return;
    NotificationService().showPlaybackNotification(
      track: _currentTrack!,
      isPlaying: _isPlaying,
      position: _position,
      duration: _duration,
    );
  }

  Future<void> play(TrackModel track, {List<TrackModel>? queue}) async {
    if (queue != null) {
      _queue = queue;
      _currentIndex = queue.indexOf(track);
      if (_currentIndex == -1) _currentIndex = 0;
    } else if (_queue.isEmpty) {
      _queue = [track];
      _currentIndex = 0;
    }
    _currentTrack = track;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
    _updateNotification();
    
    // Use prefetched URL if available for faster loading
    final primary = track.sourceUrl.isNotEmpty ? ApiService.streamTrackUrl(track.sourceUrl) : null;
    final fallback = ApiService.streamTrackUrl('ytsearch1:${track.title} ${track.artists} audio');
    final prefetchedUrl = _prefetchedUrls[track.id];
    final url = prefetchedUrl ?? primary ?? fallback;
    
    debugPrint('[Player] play ${track.title} url=$url prefetched=${prefetchedUrl != null}');
    
    Future<void> warm(String url) async {
      try {
        await http.head(Uri.parse(url)).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    
    try {
      await _player.stop();
      if (prefetchedUrl != null) {
        // Use prefetched URL - faster loading
        await _player.play(UrlSource(url)).timeout(const Duration(seconds: 25));
      } else {
        // Warm up and play
        await warm(url);
        await _player.play(UrlSource(url)).timeout(const Duration(seconds: 30));
      }
      
      // Prefetch next tracks in background
      _prefetchNextTracks();
      
    } catch (e) {
      debugPrint('[Player] stream failed: $e, trying fallback');
      try {
        await _player.stop();
        await warm(fallback);
        await _player.play(UrlSource(fallback)).timeout(const Duration(seconds: 35));
        // Prefetch next tracks
        _prefetchNextTracks();
      } catch (e2) {
        debugPrint('[Player] fallback stream also failed: $e2');
      }
    }
    _savePlayerState();
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await resume();
    }
    _updateNotification();
  }
  
  Future<void> pause() async {
    await _player.pause();
  }
  
  Future<void> resume() async {
    await _player.resume();
  }

  Future<void> seekTo(Duration position) async {
    await _player.seek(position);
  }

  Future<void> next() async {
    if (_queue.isEmpty || _currentIndex >= _queue.length - 1) return;
    _currentIndex++;
    await play(_queue[_currentIndex], queue: _queue);
  }

  Future<void> previous() async {
    if (_queue.isEmpty || _currentIndex <= 0) return;
    if (_position.inSeconds > 3) {
      await _player.seek(Duration.zero);
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
    notifyListeners();
    NotificationService().cancelPlaybackNotification();
  }

  void setQueue(List<TrackModel> tracks, {int startIndex = 0}) {
    _queue = tracks;
    _currentIndex = startIndex.clamp(0, tracks.isEmpty ? 0 : tracks.length - 1);
    notifyListeners();
    _prefetchNextTracks();
  }
  
  Future<void> playFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    await play(_queue[index], queue: _queue);
  }
  
  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    
    // Adjust current index if needed
    if (_currentIndex >= index) {
      _currentIndex = (_currentIndex - 1).clamp(-1, _queue.length - 1);
    }
    
    // If we removed the current track, stop playback
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
    _prefetchedUrls.clear();
    notifyListeners();
  }
  
  void addToQueue(TrackModel track) {
    _queue.add(track);
    notifyListeners();
    _prefetchNextTracks();
  }
  
  void addToQueueNext(TrackModel track) {
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      _queue.insert(_currentIndex + 1, track);
    } else {
      _queue.add(track);
    }
    notifyListeners();
    _prefetchNextTracks();
  }

  @override
  void dispose() {
    _notifTimer?.cancel();
    _savePlayerState();
    NotificationService().cancelPlaybackNotification();
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadPlayerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getString('player_queue');
      final currentIndex = prefs.getInt('player_current_index') ?? -1;
      final wasPlaying = prefs.getBool('player_was_playing') ?? false;
      final positionMs = prefs.getInt('player_position_ms') ?? 0;
      
      if (queueJson != null) {
        final List<dynamic> queueData = jsonDecode(queueJson);
        _queue = queueData.map((data) => TrackModel.fromJson(data)).toList();
        if (currentIndex >= 0 && currentIndex < _queue.length) {
          _currentIndex = currentIndex;
          _currentTrack = _queue[_currentIndex];
          _position = Duration(milliseconds: positionMs);
          _isPlaying = wasPlaying;
          
          // Restore player position if we have a track
          if (_currentTrack != null) {
            try {
              await _player.setSource(UrlSource(
                _currentTrack!.sourceUrl.isNotEmpty
                  ? ApiService.streamTrackUrl(_currentTrack!.sourceUrl)
                  : ApiService.streamTrackUrl('ytsearch1:${_currentTrack!.title} ${_currentTrack!.artists} audio')
              ));
              await _player.seek(_position);
              if (wasPlaying) {
                await _player.resume();
              }
            } catch (e) {
              debugPrint('[Player] Failed to restore state: $e');
            }
          }
          
          _updateNotification();
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
