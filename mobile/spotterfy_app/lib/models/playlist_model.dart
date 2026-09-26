import 'track_model.dart';

class PlaylistModel {
  final String id;
  String name;
  final String owner;
  String coverUrl;
  List<TrackModel> tracks;
  final String source;
  final String spotifyUrl;
  String creatorUid;
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

  /// Firestore docs are read with a defensive cast on every field: a single
  /// hand-edited / legacy document with an unexpected type must not throw and
  /// wipe out an entire community listing.
  factory PlaylistModel.fromJson(Map<String, dynamic> json, String docId) {
    String str(String key) {
      final v = json[key];
      if (v is String) return v;
      if (v == null) return '';
      return v.toString();
    }

    bool flag(String key) {
      final v = json[key];
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) return v == 'true' || v == '1';
      return false;
    }

    DateTime? date(String key) {
      final v = json[key];
      if (v is DateTime) return v;
      try {
        if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      } catch (_) {}
      try {
        if (v != null && v.toString().isNotEmpty) return v.toDate();
      } catch (_) {}
      return null;
    }

    List<TrackModel> parseTracks() {
      final raw = json['tracks'];
      if (raw is! List) return const [];
      final out = <TrackModel>[];
      for (final t in raw) {
        if (t is Map) {
          try {
            out.add(TrackModel.fromJson(Map<String, dynamic>.from(t)));
          } catch (_) {
            // Skip only the malformed track, keep the rest of the playlist.
          }
        }
      }
      return out;
    }

    final rawShared = json['sharedWith'];

    return PlaylistModel(
      id: docId,
      name: str('name'),
      owner: str('owner'),
      coverUrl: str('coverUrl'),
      tracks: parseTracks(),
      source: str('source').isEmpty ? 'spotify' : str('source'),
      spotifyUrl: str('spotifyUrl'),
      creatorUid: str('creatorUid'),
      sharedWith: rawShared is List
          ? rawShared.where((e) => e != null).map((e) => e.toString()).toList()
          : const <String>[],
      isCustom: flag('isCustom'),
      isUsersOwn: flag('isUsersOwn'),
      // Fall back to the epoch rather than DateTime.now(): a missing date must
      // not make an undated doc sort to the top of a "newest first" list.
      createdAt: date('createdAt') ?? DateTime.fromMillisecondsSinceEpoch(0),
      lastTrackSync: date('lastTrackSync'),
    );
  }

  /// Name as persisted in Firebase: raw display title minus a trailing
  /// " - Owner" / " by Owner" suffix so imports are saved clean.
  String get storageName {
    var n = name.trim();
    if (owner.isNotEmpty) {
      final dash = ' - $owner';
      if (n.endsWith(dash)) return n.substring(0, n.length - dash.length).trim();
      final by = ' by $owner';
      if (n.toLowerCase().endsWith(by.toLowerCase())) {
        return n.substring(0, n.length - by.length).trim();
      }
    }
    return n;
  }

  Map<String, dynamic> toFirestore() => {
    'name': storageName,
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

  Map<String, dynamic> toCache() => {
    'id': id,
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
    'createdAt': createdAt.toIso8601String(),
    'lastTrackSync': lastTrackSync?.toIso8601String(),
  };

  factory PlaylistModel.fromCache(Map<String, dynamic> json) => PlaylistModel(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    owner: json['owner'] as String? ?? '',
    coverUrl: json['coverUrl'] as String? ?? '',
    tracks: (json['tracks'] as List<dynamic>?)
            ?.map((t) => TrackModel.fromJson(t as Map<String, dynamic>))
            .toList() ??
        [],
    source: json['source'] as String? ?? 'spotify',
    spotifyUrl: json['spotifyUrl'] as String? ?? '',
    creatorUid: json['creatorUid'] as String? ?? '',
    sharedWith: (json['sharedWith'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [],
    isCustom: json['isCustom'] as bool? ?? false,
    isUsersOwn: json['isUsersOwn'] as bool? ?? false,
    createdAt: json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : null,
    lastTrackSync: json['lastTrackSync'] != null
        ? DateTime.parse(json['lastTrackSync'] as String)
        : null,
  );
}
