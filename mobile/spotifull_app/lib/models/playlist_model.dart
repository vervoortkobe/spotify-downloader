import 'track_model.dart';

class PlaylistModel {
  final String id;
  final String name;
  final String owner;
  final String coverUrl;
  List<TrackModel> tracks;
  final String source;
  final String spotifyUrl;
  final String creatorUid;
  final List<String> sharedWith;
  final bool isCustom;
  final bool isUsersOwn;
  final DateTime createdAt;
  DateTime? lastTrackSync;

  PlaylistModel({
    required this.id,
    required this.name,
    this.owner = '',
    this.coverUrl = '',
    this.tracks = const [],
    this.source = 'spotify',
    this.spotifyUrl = '',
    required this.creatorUid,
    this.sharedWith = const [],
    this.isCustom = false,
    this.isUsersOwn = false,
    DateTime? createdAt,
    this.lastTrackSync,
  }) : createdAt = createdAt ?? DateTime.now();

  factory PlaylistModel.fromJson(Map<String, dynamic> json, String docId) => PlaylistModel(
    id: docId,
    name: json['name'] as String? ?? '',
    owner: json['owner'] as String? ?? '',
    coverUrl: json['coverUrl'] as String? ?? '',
    tracks: (json['tracks'] as List<dynamic>?)
        ?.map((t) => TrackModel.fromJson(t as Map<String, dynamic>))
        .toList() ?? [],
    source: json['source'] as String? ?? 'spotify',
    spotifyUrl: json['spotifyUrl'] as String? ?? '',
    creatorUid: json['creatorUid'] as String? ?? '',
    sharedWith: (json['sharedWith'] as List<dynamic>?)
        ?.map((e) => e as String).toList() ?? [],
    isCustom: json['isCustom'] as bool? ?? false,
    isUsersOwn: json['isUsersOwn'] as bool? ?? false,
    createdAt: (json['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
    lastTrackSync: (json['lastTrackSync'] as dynamic)?.toDate(),
  );

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'owner': owner,
    'coverUrl': coverUrl,
    'tracks': tracks.map((t) => t.toJson()).toList(),
    'source': source,
    'spotifyUrl': spotifyUrl,
    'creatorUid': creatorUid,
    'sharedWith': sharedWith,
    'isCustom': isCustom,
    'isUsersOwn': isUsersOwn,
    'createdAt': createdAt,
    'lastTrackSync': lastTrackSync,
  };
}
