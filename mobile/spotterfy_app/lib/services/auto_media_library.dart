import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/services/device_library.dart';
import 'package:spotterfy_app/services/firebase_service.dart';
import 'package:spotterfy_app/widgets/storage_cover.dart';

/// The playlist sources exposed to the Android Auto browse tree.
class AutoLibrarySnapshot {
  /// Playlists owned by the signed-in user.
  final List<PlaylistModel> own;

  /// Playlists other users shared directly with the signed-in user
  /// (Firestore `sharedWith` contains them).
  final List<PlaylistModel> shared;

  /// Public playlists from other users (the community catalogue).
  final List<PlaylistModel> community;

  /// Folders of music already on the device, from the Library > Storage tab.
  final List<PlaylistModel> device;

  const AutoLibrarySnapshot({
    this.own = const [],
    this.shared = const [],
    this.community = const [],
    this.device = const [],
  });

  bool get isEmpty =>
      own.isEmpty && shared.isEmpty && community.isEmpty && device.isEmpty;

  /// Every playlist in the tree, used to resolve a tapped media id.
  List<PlaylistModel> get all => [...own, ...shared, ...community, ...device];
}

/// Supplies the user's library to the Android Auto browse tree and starts
/// playback for rows picked there.
///
/// The audio handler has no access to the provider layer, so the provider that
/// owns the data registers itself here ([bindLibrary]) and the handler
/// delegates all browsing to this bridge.
class AutoLibraryBridge {
  AutoLibraryBridge._();
  static final AutoLibraryBridge instance = AutoLibraryBridge._();

  Future<AutoLibrarySnapshot> Function()? _libraryLoader;
  Future<void> Function(List<TrackModel> tracks, int index)? _playTracks;

  /// [PlaylistProvider] registers the library source here.
  void bindLibrary(Future<AutoLibrarySnapshot> Function() loader) =>
      _libraryLoader = loader;

  /// [PlayerProvider] registers playback here.
  void bindPlayback(
    Future<void> Function(List<TrackModel> tracks, int index) play,
  ) => _playTracks = play;

  // --- Media IDs used by the browse tree ---------------------------------

  /// `audio_service` 0.18.x routes browsing through `getChildren` and reports
  /// the root as `AudioService.browsableRootId` ('root').
  static const String rootId = 'root';
  static const String queueId = 'queue';
  static const String playlistPrefix = 'playlist:';
  static const String categoryPrefix = 'category:';

  /// Devices are grouped by folder, matching the Library > Storage tab.
  static const String deviceCategoryPrefix = 'device:';

  /// Live queue/current track, pushed in by the handler so the "Up Next" browse
  /// node works even for tracks that are not in any saved playlist.
  List<TrackModel> _queueSnapshot = const [];
  TrackModel? _current;

  void updatePlaybackState(List<TrackModel> queue, TrackModel? current) {
    _queueSnapshot = List.of(queue);
    _current = current;
  }

  Future<AutoLibrarySnapshot> _library() async {
    try {
      // The loader reaches Firestore, which is not ready yet when Android Auto
      // wakes the app before the splash has booted. Joining the splash's
      // initialisation here means the car waits for Firebase rather than
      // failing the browse tree.
      await FirebaseService.initialize();
      final base = await _libraryLoader?.call() ?? const AutoLibrarySnapshot();
      // Device folders come from disk rather than Firestore, so they are
      // resolved here. They stay useful when signed out, which is exactly the
      // state Android Auto can wake the app into.
      if (base.device.isNotEmpty) return base;
      final device = await DeviceLibrary.load();
      if (device.isEmpty) return base;
      final out = AutoLibrarySnapshot(
        own: base.own,
        shared: base.shared,
        community: base.community,
        device: device,
      );
      // A cold Android Auto start can hit this before any screen has read the
      // library, so this is the first time the device folders are known to the
      // car. Nudge it to re-read the tree.
      _notifyLibraryChanged();
      return out;
    } catch (e) {
      debugPrint('[Auto] library load failed: $e');
      return const AutoLibrarySnapshot();
    }
  }

  /// Serves Android Auto's browse tree.
  ///
  /// Shape: root -> "Up Next" + one node per non-empty category -> playlists
  /// -> tracks. Categories follow the Android Auto browse convention so the
  /// car UI renders them as separate shelves instead of one long list.
  Future<List<MediaItem>> getChildren(String parentMediaId) async {
    if (parentMediaId == rootId || parentMediaId.isEmpty) {
      final lib = await _library();
      final items = <MediaItem>[
        MediaItem(
          id: queueId,
          title: 'Up Next',
          album: 'Current queue',
          artUri: await resolveArtUri(_current),
          // Not directly playable - it expands to the queue instead.
          playable: false,
        ),
      ];

      for (final entry in <(String, String, List<PlaylistModel>)>[
        ('own', 'My Playlists', lib.own),
        ('shared', 'Shared with me', lib.shared),
        ('device', 'On this device', lib.device),
        ('community', 'Community', lib.community),
      ]) {
        final (id, title, source) = entry;
        final withTracks = source.where((p) => p.tracks.isNotEmpty).toList();
        if (withTracks.isEmpty) continue;
        items.add(
          MediaItem(
            id: '$categoryPrefix$id',
            title: title,
            album: id == 'device'
                // Folders are songs, not curated playlists, so a song count is
                // the useful number here.
                ? '${withTracks.fold<int>(0, (n, p) => n + p.tracks.length)} songs'
                : '${withTracks.length} playlist${withTracks.length == 1 ? '' : 's'}',
            artUri: await resolveArtUri(withTracks.first.tracks.first),
            playable: false,
          ),
        );
      }
      return items;
    }

    if (parentMediaId == queueId) {
      return trackItems(_queueSnapshot);
    }

    if (parentMediaId.startsWith(categoryPrefix)) {
      final which = parentMediaId.substring(categoryPrefix.length);
      final lib = await _library();
      final source = switch (which) {
        'own' => lib.own,
        'shared' => lib.shared,
        'device' => lib.device,
        'community' => lib.community,
        _ => const <PlaylistModel>[],
      };
      final items = <MediaItem>[];
      for (final p in source) {
        if (p.tracks.isEmpty) continue;
        items.add(await playlistItem(p));
      }
      return items;
    }

    if (parentMediaId.startsWith(playlistPrefix)) {
      final id = parentMediaId.substring(playlistPrefix.length);
      final lib = await _library();
      for (final p in lib.all) {
        if (p.id == id) return trackItems(p.tracks);
      }
    }
    return const [];
  }

  // --- Playback from the browse tree -------------------------------------

  /// Resolves a browsed media id to the full track list plus the index to start
  /// from. Returns null when the id is unknown.
  Future<(List<TrackModel>, int)?> _resolve(String mediaId) async {
    if (mediaId == queueId) {
      return (_queueSnapshot, _currentIndexInQueue);
    }

    if (mediaId.startsWith(playlistPrefix)) {
      final pid = mediaId.substring(playlistPrefix.length);
      final lib = await _library();
      for (final p in lib.all) {
        if (p.id == pid && p.tracks.isNotEmpty) return (p.tracks, 0);
      }
      return null;
    }

    // A track row: locate it in a playlist so the whole playlist becomes the
    // queue, matching how the app behaves when you tap a track in-app.
    final lib = await _library();
    for (final p in lib.all) {
      final idx = p.tracks.indexWhere((t) => t.id == mediaId);
      if (idx >= 0) return (p.tracks, idx);
    }
    final idx = _queueSnapshot.indexWhere((t) => t.id == mediaId);
    if (idx >= 0) return (_queueSnapshot, idx);
    return null;
  }

  /// Called when the user taps a row in Android Auto.
  Future<void> playFromMediaId(String mediaId) async {
    final resolved = await _resolve(mediaId);
    if (resolved == null) return;
    await _play(resolved.$1, resolved.$2);
  }

  /// Android Auto voice search, e.g. `play <something>`.
  Future<void> playFromSearch(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return;
    final lib = await _library();
    List<TrackModel>? bestTracks;
    var bestIndex = 0;
    var bestScore = 1 << 30;
    for (final p in lib.all) {
      final playlistHit = p.name.toLowerCase().contains(q);
      for (var i = 0; i < p.tracks.length; i++) {
        final t = p.tracks[i];
        final inTitle = t.title.toLowerCase().contains(q);
        final inArtist = t.artists.toLowerCase().contains(q);
        if (!playlistHit && !inTitle && !inArtist) continue;
        // Title match beats artist match beats playlist-name match.
        final score = inTitle ? 0 : (inArtist ? 1 : 2);
        if (score < bestScore) {
          bestScore = score;
          bestTracks = p.tracks;
          bestIndex = i;
        }
      }
    }
    if (bestTracks != null) await _play(bestTracks, bestIndex);
  }

  int get _currentIndexInQueue {
    if (_current == null) return 0;
    final i = _queueSnapshot.indexWhere((t) => t.id == _current!.id);
    return i < 0 ? 0 : i;
  }

  Future<void> _play(List<TrackModel> tracks, int index) async {
    if (tracks.isEmpty) return;
    final i = index.clamp(0, tracks.length - 1);
    try {
      await _playTracks?.call(tracks, i);
    } catch (e) {
      debugPrint('[Auto] playback failed: $e');
    }
  }

  // --- MediaItem builders -------------------------------------------------

  /// Fires when the library contents change, so the handler can push a
  /// subscription update and the car UI refreshes an already-open tree instead
  /// of showing whatever was there when it first connected.
  static final List<VoidCallback> _listeners = [];

  /// Tells any open Android Auto browse tree to re-read itself.
  ///
  /// The car caches whatever tree it was handed, so without this a playlist
  /// imported while the car screen was open would not appear until the car
  /// reconnected.
  static void libraryChanged() => _notifyLibraryChanged();

  static void addLibraryListener(VoidCallback l) => _listeners.add(l);

  static void removeLibraryListener(VoidCallback l) => _listeners.remove(l);

  static void _notifyLibraryChanged() {
    for (final l in List.of(_listeners)) {
      try {
        l();
      } catch (_) {}
    }
  }

  /// Browsable playlist row. The `playlist:` id lets [getChildren] expand it
  /// into tracks and [playFromMediaId] start the whole playlist.
  Future<MediaItem> playlistItem(PlaylistModel p) async {
    final first = p.tracks.isNotEmpty ? p.tracks.first : null;
    Uri? art;
    if (p.coverUrl.isNotEmpty) {
      art = Uri.tryParse(p.coverUrl);
    } else if (first != null) {
      art = await resolveArtUri(first);
    }
    return MediaItem(
      id: '$playlistPrefix${p.id}',
      title: p.name,
      album: p.owner.isNotEmpty ? p.owner : 'Playlist',
      artist: '${p.tracks.length} tracks',
      artUri: art,
      playable: false,
    );
  }

  /// Playable rows with artwork + duration fully resolved, so Android Auto
  /// shows real lengths and covers instead of "unknown" / placeholders.
  Future<List<MediaItem>> trackItems(List<TrackModel> tracks) async {
    final items = <MediaItem>[];
    for (final t in tracks) {
      items.add(
        MediaItem(
          id: t.id,
          title: t.title,
          artist: t.artists,
          album: t.album.isNotEmpty ? t.album : 'Spotterfy',
          duration: await resolveDuration(t),
          artUri: await resolveArtUri(t),
        ),
      );
    }
    return items;
  }

  /// Best-effort synchronous item for the live queue. Uses whatever has already
  /// been resolved; the handler re-publishes the queue once the async
  /// resolution finishes so Auto picks up the improved metadata.
  MediaItem trackItemSync(TrackModel t) => MediaItem(
    id: t.id,
    title: t.title,
    artist: t.artists,
    album: t.album.isNotEmpty ? t.album : 'Spotterfy',
    duration: t.durationMs > 0
        ? Duration(milliseconds: t.durationMs)
        : _durationCache[t.id],
    artUri: t.cover.isNotEmpty ? Uri.tryParse(t.cover) : _artUriCache[t.id],
  );

  // --- Caches -------------------------------------------------------------

  static final Map<String, Uri?> _artUriCache = {};
  static final Map<String, Duration?> _durationCache = {};
  static Future<Directory>? _artDirFuture;

  static bool isStorageTrack(TrackModel t) {
    final src = t.sourceUrl;
    return t.id.startsWith('storage_') ||
        src.startsWith('/') ||
        src.startsWith('file://');
  }

  /// Resolves a usable artwork URI for [t].
  ///
  /// Remote covers pass straight through. On-device files have no URL (the art
  /// is embedded in the ID3 tag), so the bytes are extracted once and written
  /// to a cache file - `audio_service` explicitly supports `file://` artUri.
  static Future<Uri?> resolveArtUri(TrackModel? t) async {
    if (t == null) return null;
    final cached = _artUriCache[t.id];
    if (cached != null || _artUriCache.containsKey(t.id)) return cached;

    Uri? uri;
    if (t.cover.isNotEmpty) {
      uri = Uri.tryParse(t.cover);
    } else if (isStorageTrack(t)) {
      uri = await _extractEmbeddedArt(t);
    }
    _artUriCache[t.id] = uri;
    return uri;
  }

  static Future<Uri?> _extractEmbeddedArt(TrackModel t) async {
    try {
      final path = t.sourceUrl.replaceFirst('file://', '');
      if (path.isEmpty) return null;
      final bytes = await StorageCoverCache.load(path);
      if (bytes == null || bytes.isEmpty) return null;
      final dir = await (_artDirFuture ??= _createArtDir());
      // Stable filename per track so the same art is never rewritten.
      final file = File(
        '${dir.path}/${t.id.hashCode.abs()}${_artExtension(bytes)}',
      );
      if (!await file.exists()) {
        await file.writeAsBytes(bytes, flush: true);
      }
      return Uri.file(file.path);
    } catch (e) {
      debugPrint('[Auto] art extraction failed for ${t.id}: $e');
      return null;
    }
  }

  /// Embedded art can be JPEG or PNG (or WebP/GIF), so pick the extension from
  /// the magic bytes rather than always writing `.jpg`.
  static String _artExtension(List<int> b) {
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return '.png';
    }
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return '.jpg';
    }
    if (b.length >= 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
      return '.gif';
    }
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return '.webp';
    }
    return '.jpg';
  }

  static Future<Directory> _createArtDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/media_art');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Storage tracks are built with `durationMs: 0`, so the real length has to
  /// be read from the file - otherwise Android Auto shows "unknown" for most
  /// queue rows.
  static Future<Duration?> resolveDuration(TrackModel t) async {
    if (t.durationMs > 0) return Duration(milliseconds: t.durationMs);
    if (_durationCache.containsKey(t.id)) return _durationCache[t.id];
    Duration? result;
    if (isStorageTrack(t)) {
      try {
        final path = t.sourceUrl.replaceFirst('file://', '');
        if (path.isNotEmpty) {
          result = readMetadata(File(path)).duration;
        }
      } catch (e) {
        debugPrint('[Auto] duration read failed for ${t.id}: $e');
      }
    }
    _durationCache[t.id] = result;
    return result;
  }

  @visibleForTesting
  static void clearCaches() {
    _artUriCache.clear();
    _durationCache.clear();
  }
}
