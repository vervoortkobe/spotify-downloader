import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
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

  TrackModel? get currentTrack => _currentTrack;
  List<TrackModel> get queue => _queue;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  AudioPlayer get player => _player;

  PlayerProvider() {
    final notif = NotificationService();
    notif.onPlayPause = togglePlayPause;
    notif.onNext = next;
    notif.onPrevious = previous;

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
    } else {
      _currentTrack = track;
      _currentIndex = 0;
    }
    _currentTrack = track;
    notifyListeners();

    final source = track.sourceUrl.isNotEmpty
        ? ApiService.streamTrackUrl(track.sourceUrl)
        : null;
    if (source != null) {
      await _player.play(UrlSource(source));
    }
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.resume();
    }
    _updateNotification();
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

  void setQueue(List<TrackModel> tracks, {int startIndex = 0}) {
    _queue = tracks;
    _currentIndex = startIndex;
    notifyListeners();
  }

  @override
  void dispose() {
    _notifTimer?.cancel();
    NotificationService().cancelPlaybackNotification();
    _player.dispose();
    super.dispose();
  }
}
