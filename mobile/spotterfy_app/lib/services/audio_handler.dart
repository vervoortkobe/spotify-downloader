import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
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
  final AudioPlayer _player = AudioPlayer();
  List<TrackModel> _tracks = [];
  int _index = -1;

  SpotterfyAudioHandler() {
    _init();
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _player.playbackEventStream.map(_toPlaybackState).pipe(playbackState);
    _player.durationStream.listen((dur) {
      if (dur != null) {
        final item = mediaItem.value;
        if (item != null && item.duration != dur) {
          mediaItem.add(item.copyWith(duration: dur));
        }
      }
    });

    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_index + 1 < _tracks.length) {
          skipToNext();
        }
      }
    });
  }

  PlaybackState _toPlaybackState(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _index >= 0 ? _index : null,
    );
  }

  MediaItem _toMediaItem(TrackModel t) => MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artists,
        album: t.album,
        artUri: t.cover.isNotEmpty ? Uri.tryParse(t.cover) : null,
        duration: t.durationMs > 0 ? Duration(milliseconds: t.durationMs) : null,
      );

  Future<void> playTrack(TrackModel track, {List<TrackModel>? queue}) async {
    if (queue != null) {
      _tracks = List.from(queue);
      _index = _tracks.indexWhere((e) => e.id == track.id);
      if (_index == -1) _index = 0;
      this.queue.add(_tracks.map(_toMediaItem).toList());
    } else if (_tracks.isEmpty) {
      _tracks = [track];
      _index = 0;
      this.queue.add([_toMediaItem(track)]);
    } else {
      final idx = _tracks.indexWhere((e) => e.id == track.id);
      if (idx >= 0) {
        _index = idx;
      } else {
        _tracks.add(track);
        _index = _tracks.length - 1;
        this.queue.add(_tracks.map(_toMediaItem).toList());
      }
    }
    final mediaItem = _toMediaItem(track);
    this.mediaItem.add(mediaItem);
    final url = track.sourceUrl.isNotEmpty ? ApiService.streamTrackUrl(track.sourceUrl) : ApiService.streamTrackUrl('ytsearch1:${track.title} ${track.artists} audio');
    try {
      await _player.setAudioSource(AudioSource.uri(Uri.parse(url)), preload: true);
      await _player.play();
    } catch (e) {
      // fallback to ytsearch if sourceUrl failed
      if (track.sourceUrl.isNotEmpty) {
        final fb = ApiService.streamTrackUrl('ytsearch1:${track.title} ${track.artists} audio');
        await _player.setAudioSource(AudioSource.uri(Uri.parse(fb)));
        await _player.play();
      } else {
        rethrow;
      }
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_index + 1 < _tracks.length) {
      _index++;
      await playTrack(_tracks[_index], queue: _tracks);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if ((_player.position.inSeconds) > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    if (_index > 0) {
      _index--;
      await playTrack(_tracks[_index], queue: _tracks);
    }
  }

  void setQueue(List<TrackModel> tracks, {int startIndex = 0}) {
    _tracks = List.from(tracks);
    _index = startIndex.clamp(0, _tracks.length - 1);
    queue.add(_tracks.map(_toMediaItem).toList());
    if (_tracks.isNotEmpty) mediaItem.add(_toMediaItem(_tracks[_index]));
  }

  AudioPlayer get player => _player;
  List<TrackModel> get tracks => _tracks;
  int get index => _index;
}
