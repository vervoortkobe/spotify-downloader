class JamSessionModel {
  final String id;
  final String name;
  final String createdBy;
  final List<String> tracks; // track ids
  final String? currentTrackId;
  final int currentPositionMs;
  final bool isPlaying;
  final List<String> participants;
  final DateTime createdAt;

  JamSessionModel({
    required this.id,
    required this.name,
    required this.createdBy,
    this.tracks = const [],
    this.currentTrackId,
    this.currentPositionMs = 0,
    this.isPlaying = false,
    this.participants = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}
