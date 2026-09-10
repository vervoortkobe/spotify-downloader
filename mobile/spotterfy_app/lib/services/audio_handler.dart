import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import '../models/track_model.dart';
import 'api_service.dart';

SpotterfyAudioHandler? audioHandler;

Future<void> ensureAudioHandler() async {
  if (audioHandler != null) return;
  try {
    audioHandler = await AudioService.init(
      builder: () => SpotterfyAudioHandler(),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.scooby.spotterfy.channel.audio',
        androidNotificationChannelName: 'Music playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidShowNotificationBadge: false,
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    );
  } catch (e) {
    debugPrint('[AudioService] init failed: $e');
  }
}

class SpotterfyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  List<TrackModel> _tracks = [];
  int _index = -1;
  Future<void> Function(Duration)? onSeekRequested;

  SpotterfyAudioHandler() {
    _initSession();
  }

  Future<void> _initSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}
  }

  MediaItem _toMediaItem(TrackModel t) => MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artists,
        album: t.album,
        artUri: t.cover.isNotEmpty ? Uri.tryParse(t.cover) : null,
        duration: t.durationMs > 0 ? Duration(milliseconds: t.durationMs) : null,
      );

  void setQueue(List<TrackModel> tracks, {int startIndex = 0}) {
    _tracks = List.from(tracks);
    _index = startIndex.clamp(0, _tracks.length - 1);
    queue.add(_tracks.map(_toMediaItem).toList());
    if (_tracks.isNotEmpty) mediaItem.add(_toMediaItem(_tracks[_index]));
    _updatePlaybackState(isPlaying: playbackState.valueOrNull?.playing ?? false, position: Duration.zero);
  }

  Future<void> updateTrack(TrackModel track, {List<TrackModel>? queue, required Duration position, Duration? duration, required bool isPlaying}) async {
    if (queue != null) {
      _tracks = List.from(queue);
      _index = _tracks.indexWhere((e) => e.id == track.id);
      if (_index == -1) _index = 0;
      this.queue.add(_tracks.map(_toMediaItem).toList());
    }
    final item = _toMediaItem(track);
    mediaItem.add(item.copyWith(duration: duration));
    _updatePlaybackState(isPlaying: isPlaying, position: position);
  }

  void _updatePlaybackState({required bool isPlaying, required Duration position, Duration buffered = Duration.zero, double speed = 1.0}) {
    final dur = mediaItem.value?.duration;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: isPlaying,
      updatePosition: position,
      bufferedPosition: buffered,
      speed: speed,
      queueIndex: _index >= 0 ? _index : null,
    ));
  }

  void updatePosition(Duration pos, Duration dur, bool isPlaying) {
    final item = mediaItem.value;
    if (item != null && dur != Duration.zero) {
      mediaItem.add(item.copyWith(duration: dur));
    }
    _updatePlaybackState(isPlaying: isPlaying, position: pos);
  }

  @override
  Future<void> seek(Duration position) async {
    if (onSeekRequested != null) {
      await onSeekRequested!(position);
    }
    _updatePlaybackState(isPlaying: playbackState.valueOrNull?.playing ?? false, position: position);
  }

  @override
  Future<void> play() async {
    _updatePlaybackState(isPlaying: true, position: playbackState.valueOrNull?.updatePosition ?? Duration.zero);
  }

  @override
  Future<void> pause() async {
    _updatePlaybackState(isPlaying: false, position: playbackState.valueOrNull?.updatePosition ?? Duration.zero);
  }

  @override
  Future<void> stop() async {
    _updatePlaybackState(isPlaying: false, position: Duration.zero);
  }

  @override
  Future<void> skipToNext() async {
    if (_index + 1 < _tracks.length) {
      _index++;
      mediaItem.add(_toMediaItem(_tracks[_index]));
      _updatePlaybackState(isPlaying: true, position: Duration.zero);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_index > 0) {
      _index--;
      mediaItem.add(_toMediaItem(_tracks[_index]));
      _updatePlaybackState(isPlaying: true, position: Duration.zero);
    }
  }
}
