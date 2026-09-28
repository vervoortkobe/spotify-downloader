import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// One downloaded track on disk.
class DownloadEntry {
  /// Track id it belongs to, so the original title/artwork can be restored.
  final String trackId;
  final String fileName;
  final String title;
  final String artists;
  final int sizeBytes;
  final DateTime downloadedAt;

  const DownloadEntry({
    required this.trackId,
    required this.fileName,
    required this.title,
    required this.artists,
    required this.sizeBytes,
    required this.downloadedAt,
  });

  Map<String, dynamic> toJson() => {
    'trackId': trackId,
    'fileName': fileName,
    'title': title,
    'artists': artists,
    'sizeBytes': sizeBytes,
    'downloadedAt': downloadedAt.toIso8601String(),
  };

  static DownloadEntry? fromJson(Map<String, dynamic> j) {
    final id = j['trackId'];
    final file = j['fileName'];
    if (id is! String || file is! String || id.isEmpty || file.isEmpty) {
      return null;
    }
    return DownloadEntry(
      trackId: id,
      fileName: file,
      title: (j['title'] as String?) ?? '',
      artists: (j['artists'] as String?) ?? '',
      sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
      downloadedAt:
          DateTime.tryParse((j['downloadedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// On-device store for tracks downloaded from inside Spotterfy.
///
/// Files live in **public** storage at `/storage/emulated/0/Spotterfy/Music`
/// rather than app-private `Android/data/…`, so other music apps and file
/// managers can see and play them. Every write is announced to MediaStore via
/// a platform channel - the file existing on disk is not enough for another app
/// to find it.
///
/// The folder is still deliberately **outside** the roots the Library > Storage
/// tab scans (`/Music`, `/Download`, `/Documents`), so downloads never show up
/// there as phantom "playlists".
///
/// A JSON index maps `trackId -> file`, which is what lets the player and the UI
/// recognise a track as downloaded and play the local copy instead of streaming.
class DownloadService {
  DownloadService._internal();
  static final DownloadService instance = DownloadService._internal();

  /// Shared external storage root.
  static const String _publicRoot = '/storage/emulated/0';
  static const String folderName = 'Spotterfy';
  static const String musicFolder = 'Music';
  static const String indexFileName = 'downloads_index.json';

  /// Downloaded audio is always mp3 - the backend pins the mimetype.
  static const String audioExtension = '.mp3';

  /// Bridge to [MainActivity] for MediaStore indexing.
  static const MethodChannel _mediaStore = MethodChannel(
    'com.scooby.spotterfy/media_store',
  );

  Map<String, DownloadEntry> _entries = {};
  bool _loaded = false;
  Directory? _rootDir;

  /// Cached view of what is downloaded. Safe to call synchronously after
  /// [ensureLoaded].
  Map<String, DownloadEntry> get entries => Map.unmodifiable(_entries);

  bool isDownloaded(String trackId) => _entries.containsKey(trackId);

  DownloadEntry? entryFor(String trackId) => _entries[trackId];

  /// Absolute path of the local file for [trackId], or null if not downloaded.
  String? localPathFor(String trackId) {
    final e = _entries[trackId];
    if (e == null) return null;
    return '${_rootDir?.path ?? ''}${Platform.pathSeparator}${e.fileName}';
  }

  Future<Directory> _root() async {
    if (_rootDir != null) return _rootDir!;
    final dir = Directory(
      '$_publicRoot${Platform.pathSeparator}$folderName'
      '${Platform.pathSeparator}$musicFolder',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    _rootDir = dir;
    return dir;
  }

  Future<File> _indexFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File('${docs.path}${Platform.pathSeparator}$indexFileName');
  }

  /// Loads the index once, pruning entries whose file has since disappeared so
  /// a manually deleted file doesn't leave a phantom "downloaded" badge.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _indexFile();
      Map<String, dynamic> raw = {};
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) raw = Map<String, dynamic>.from(decoded);
      }
      final parsed = <String, DownloadEntry>{};
      (raw['entries'] as Map?)?.forEach((k, v) {
        if (v is Map) {
          final e = DownloadEntry.fromJson(Map<String, dynamic>.from(v));
          if (e != null) parsed[e.trackId] = e;
        }
      });

      // Rescue anything still sitting in the old app-private location BEFORE
      // pruning, otherwise the prune below would see it as "missing" and drop
      // the index entry - losing track of files that are perfectly intact.
      final migrated = await _migrateLegacyInto(parsed);

      // Drop anything whose audio file is gone.
      final root = await _root();
      var pruned = false;
      for (final e in parsed.values.toList()) {
        if (!await File(
          '${root.path}${Platform.pathSeparator}${e.fileName}',
        ).exists()) {
          parsed.remove(e.trackId);
          pruned = true;
        }
      }
      _entries = parsed;
      if (pruned || migrated > 0) await _persist();
    } catch (e) {
      debugPrint('[Downloads] index load failed: $e');
      _entries = {};
    }
  }

  /// Moves files from the previous app-private location into the public one.
  ///
  /// Assumes the index has already been parsed; called from [ensureLoaded]
  /// before pruning so existing downloads survive the storage-location change.
  /// Returns how many files were moved.
  Future<int> _migrateLegacyInto(Map<String, DownloadEntry> parsed) async {
    if (parsed.isEmpty) return 0;
    try {
      final oldBase = await getExternalStorageDirectory();
      if (oldBase == null) return 0;
      final oldDir = Directory(
        '${oldBase.path}${Platform.pathSeparator}$folderName'
        '${Platform.pathSeparator}$musicFolder',
      );
      if (!await oldDir.exists()) return 0;

      final newDir = await _root();
      var moved = 0;
      for (final e in parsed.values.toList()) {
        final from = File(
          '${oldDir.path}${Platform.pathSeparator}${e.fileName}',
        );
        if (!await from.exists()) continue;
        final to = File('${newDir.path}${Platform.pathSeparator}${e.fileName}');
        if (await to.exists()) {
          // Already migrated by a previous run; drop the stale duplicate.
          await from.delete();
        } else {
          await from.rename(to.path);
          await _announceToMediaStore(to.path);
        }
        moved++;
      }
      if (moved > 0) {
        debugPrint('[Downloads] migrated $moved file(s) to public storage');
      }
      return moved;
    } catch (e) {
      debugPrint('[Downloads] migration failed: $e');
      return 0;
    }
  }

  Future<void> _persist() async {
    try {
      final file = await _indexFile();
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'entries': _entries.map((k, v) => MapEntry(k, v.toJson())),
        }),
      );
    } catch (e) {
      debugPrint('[Downloads] index write failed: $e');
    }
  }

  /// Filesystem-safe name, falling back to something stable when a title or
  /// artist is empty or made entirely of characters we strip.
  static String _safe(String s, {int max = 60}) {
    var out = s.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    out = out.replaceAll(RegExp(r'\s+'), ' ');
    if (out.isEmpty) out = 'track';
    return out.length > max ? out.substring(0, max).trim() : out;
  }

  /// Picks a filename that is free in the folder, so two tracks with the same
  /// title don't overwrite each other.
  Future<String> _uniqueFileName(
    Directory dir,
    String title,
    String artists,
  ) async {
    final base = artists.isEmpty
        ? _safe(title)
        : '${_safe(title)} - ${_safe(artists, max: 40)}';
    var name = '$base$audioExtension';
    var n = 2;
    while (await File('${dir.path}${Platform.pathSeparator}$name').exists()) {
      final existing = _entries.values.any((e) => e.fileName == name);
      // Reuse a file that isn't claimed by another track, otherwise disambiguate.
      if (!existing) break;
      name = '$base ($n)$audioExtension';
      n++;
    }
    return name;
  }

  /// Tells MediaStore about a new file so other music apps can see it.
  ///
  /// Best-effort: if the channel fails the file is still on disk and playable
  /// from Spotterfy, just not indexed elsewhere.
  static Future<void> _announceToMediaStore(String path) async {
    try {
      await _mediaStore.invokeMethod<bool>('scanFile', {'path': path});
    } catch (e) {
      debugPrint('[Downloads] media scan failed for $path: $e');
    }
  }

  /// Removes a deleted file from the MediaStore index so it stops showing up in
  /// other players.
  static Future<void> _unannounceFromMediaStore(String path) async {
    try {
      await _mediaStore.invokeMethod<bool>('deleteScan', {'path': path});
    } catch (e) {
      debugPrint('[Downloads] media delete scan failed for $path: $e');
    }
  }

  /// Writes [bytes] for [trackId] and records it in the index. Returns the
  /// stored path, or null on failure.
  Future<String?> save({
    required String trackId,
    required List<int> bytes,
    required String title,
    required String artists,
  }) async {
    if (trackId.isEmpty || bytes.isEmpty) return null;
    try {
      await ensureLoaded();
      final dir = await _root();
      // Replace any previous copy for this track.
      await remove(trackId);
      final name = await _uniqueFileName(dir, title, artists);
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(bytes, flush: true);
      _entries[trackId] = DownloadEntry(
        trackId: trackId,
        fileName: name,
        title: title,
        artists: artists,
        sizeBytes: bytes.length,
        downloadedAt: DateTime.now(),
      );
      await _persist();
      // Index it so other music apps can play it.
      await _announceToMediaStore(file.path);
      return file.path;
    } catch (e) {
      debugPrint('[Downloads] save failed for $trackId: $e');
      return null;
    }
  }

  /// Deletes the local file for [trackId] and forgets it. No-op when the track
  /// was never downloaded, so it is safe to call unconditionally.
  Future<bool> remove(String trackId) async {
    final e = _entries.remove(trackId);
    if (e == null) return false;
    try {
      final dir = await _root();
      final path = '${dir.path}${Platform.pathSeparator}${e.fileName}';
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        await _unannounceFromMediaStore(path);
      }
    } catch (err) {
      debugPrint('[Downloads] remove failed for $trackId: $err');
    }
    await _persist();
    return true;
  }

  /// Total bytes used by downloaded audio, for the storage screen.
  int get totalBytes =>
      _entries.values.fold<int>(0, (sum, e) => sum + e.sizeBytes);

  /// Re-checks that every indexed file still exists on disk and forgets the
  /// ones that don't.
  ///
  /// Needed because downloads can vanish from outside the app - a file manager
  /// delete, or the user clearing space. [ensureLoaded] only prunes once per
  /// process, so without this a deleted file would keep showing as downloaded
  /// until the app was restarted.
  ///
  /// Returns the ids that were dropped.
  Future<List<String>> pruneMissingFiles() async {
    if (_entries.isEmpty) return const [];
    try {
      await ensureLoaded();
      final root = await _root();
      final gone = <String>[];
      for (final e in _entries.values.toList()) {
        final f = File('${root.path}${Platform.pathSeparator}${e.fileName}');
        if (!await f.exists()) {
          _entries.remove(e.trackId);
          gone.add(e.trackId);
        }
      }
      if (gone.isNotEmpty) {
        debugPrint('[Downloads] ${gone.length} file(s) removed externally');
        await _persist();
      }
      return gone;
    } catch (e) {
      debugPrint('[Downloads] prune failed: $e');
      return const [];
    }
  }

  /// True when [trackId] is indexed *and* the file is still there.
  ///
  /// Use this before acting on a download (e.g. re-downloading), where acting
  /// on a stale entry would be wrong. Use [isDownloaded] for rendering, where a
  /// stat call per row per build would be far too expensive.
  Future<bool> isDownloadedAndPresent(String trackId) async {
    if (!_entries.containsKey(trackId)) return false;
    final p = localPathFor(trackId);
    if (p == null) return false;
    try {
      return await File(p).exists();
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  void resetForTest() {
    _entries = {};
    _loaded = false;
    _rootDir = null;
  }
}
