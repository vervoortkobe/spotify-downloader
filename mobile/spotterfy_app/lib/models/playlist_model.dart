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

  /// Copy with the *creator account* removed, keeping the displayed author.
  ///
  /// For the curated Discover shelves (Top Genres / Top Artists). The backend
  /// publishes those under a `system_discover` uid, which is not a real user, so
  /// the detail screen would offer a profile button that resolves to nobody.
  /// Clearing [creatorUid] is what hides that button - the screen renders it
  /// purely on "does this playlist have an owner uid".
  ///
  /// [owner] is deliberately **kept**: it is the display name, not the account,
  /// so these keep reading "By Spotify". Only the profile affordance goes away.
  /// [id], [tracks] and [spotifyUrl] are preserved, so the playlist still opens,
  /// scrapes and plays exactly as before.
  PlaylistModel withoutCreator() => PlaylistModel(
    id: id,
    name: name,
    owner: owner,
    coverUrl: coverUrl,
    tracks: tracks,
    source: source,
    spotifyUrl: spotifyUrl,
    creatorUid: '',
    sharedWith: sharedWith,
    isCustom: isCustom,
    isUsersOwn: isUsersOwn,
    createdAt: createdAt,
    lastTrackSync: lastTrackSync,
  );

  /// Human-readable name for [source].
  ///
  /// Sources are stored as bare lowercase slugs (`spotify`, `youtube`,
  /// `soundcloud`) because the backend uses them as identifiers, so they must be
  /// formatted for display rather than shown raw.
  String get sourceLabel {
    switch (source.trim().toLowerCase()) {
      case '':
      case 'spotify':
      case 'auto':
        return 'Spotify';
      case 'youtube':
      case 'yt':
      case 'ytsearch':
        return 'YouTube';
      case 'soundcloud':
      case 'sound_cloud':
        return 'SoundCloud';
      case 'local':
      case 'storage':
        return 'On device';
      default:
        // Unknown slug: title-case it rather than leaking the raw identifier.
        final s = source.trim();
        if (s.isEmpty) return 'Spotify';
        return s[0].toUpperCase() + s.substring(1);
    }
  }

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
    final parsedTracks = parseTracks();

    // Playlists imported from a URL never get their own artwork (the scrape
    // endpoint returns no cover), so `coverUrl` is empty for most of them.
    // Fall back to the first track that has art so playlists always show a
    // cover instead of a generic music-note placeholder.
    var cover = str('coverUrl');
    if (cover.isEmpty) {
      for (final t in parsedTracks) {
        if (t.cover.isNotEmpty) {
          cover = t.cover;
          break;
        }
      }
    }

    return PlaylistModel(
      id: docId,
      name: str('name'),
      owner: str('owner'),
      coverUrl: cover,
      tracks: parsedTracks,
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
  String get storageName => displayName;

  /// Title to show in the UI, without the scraper's author suffix.
  ///
  /// YouTube and Spotify both return "Song - Artist" / "Playlist - Owner" as the
  /// playlist *name*, so an import ends up storing the author twice: once in the
  /// title and once in [owner]. Stripping it here keeps the name readable and
  /// leaves [owner] as the single source for the byline.
  ///
  /// Only strips a trailing suffix that actually matches [owner] (or, failing
  /// that, a trailing " - Something"). A title that merely happens to contain a
  /// dash mid-string is left alone.
  String get displayName {
    var n = name.trim();
    if (n.isEmpty) return n;

    // Exact match against the known owner, in either separator style.
    if (owner.isNotEmpty) {
      for (final sep in [' - ', ' by ']) {
        final suffix = '$sep$owner';
        if (n.toLowerCase().endsWith(suffix.toLowerCase())) {
          final stripped = n.substring(0, n.length - suffix.length).trim();
          // Don't leave an empty title if the whole name *was* the suffix.
          if (stripped.isNotEmpty) return stripped;
        }
      }
    }

    // Owner unknown (community playlist imported before ownership was
    // recorded): drop a trailing " - Whatever" as the author hint.
    //
    // Only when the owner really is unknown. If we know who the owner is and the
    // suffix doesn't match them, then that trailing segment is far more likely
    // to be part of the title - "Jay-Z - The Blueprint" and "Nils Frahm - All
    // Melody" are real playlists, and this used to truncate both to "Jay-Z".
    if (owner.trim().isNotEmpty) return n;
    final generic = RegExp(r'\s+[-–—]\s+[^-+–—]+$');
    final m = generic.firstMatch(n);
    if (m != null) {
      final stripped = n.substring(0, m.start).trim();
      // A title that is only a dash fragment is not a real title.
      if (stripped.length >= 2) return stripped;
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

  factory PlaylistModel.fromCache(Map<String, dynamic> json) {
    final tracks =
        (json['tracks'] as List<dynamic>?)
            ?.map((t) => TrackModel.fromJson(t as Map<String, dynamic>))
            .toList() ??
        <TrackModel>[];
    var cover = json['coverUrl'] as String? ?? '';
    // Same first-track fallback as fromJson (see there for why).
    if (cover.isEmpty) {
      for (final t in tracks) {
        if (t.cover.isNotEmpty) {
          cover = t.cover;
          break;
        }
      }
    }
    return PlaylistModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      owner: json['owner'] as String? ?? '',
      coverUrl: cover,
      tracks: tracks,
      source: json['source'] as String? ?? 'spotify',
      spotifyUrl: json['spotifyUrl'] as String? ?? '',
      creatorUid: json['creatorUid'] as String? ?? '',
      sharedWith:
          (json['sharedWith'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          <String>[],
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
}
