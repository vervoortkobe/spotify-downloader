import 'package:spotterfy_app/models/track_model.dart';

class JamSessionModel {
  final String id;
  final String name;
  final String createdBy;

  /// The shared queue. Full tracks, not ids, so the queue can be played without
  /// a second fetch.
  final List<TrackModel> tracks;
  final int currentTrackIndex;
  final int currentPositionMs;
  final bool isPlaying;
  final List<String> participants;
  final DateTime createdAt;

  JamSessionModel({
    required this.id,
    required this.name,
    required this.createdBy,
    this.tracks = const [],
    this.currentTrackIndex = 0,
    this.currentPositionMs = 0,
    this.isPlaying = false,
    this.participants = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// The track the session is currently on, or null for an empty queue.
  TrackModel? get currentTrack {
    if (tracks.isEmpty) return null;
    final i = currentTrackIndex.clamp(0, tracks.length - 1);
    return tracks[i];
  }
}
