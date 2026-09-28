import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/models/track_model.dart';

/// Read-only view of the music already on the device, shaped as playlists so it
/// can be surfaced in the Android Auto browse tree.
///
/// The Library > Storage tab has its own explorer with its own caching, and
/// that is deliberately left alone: it walks the tree interactively and needs
/// in-place folder navigation. This is the flat, one-shot version - folder
/// playlists only - which is all the car UI needs and is cheap enough to run
/// off the critical path.
class DeviceLibrary {
  DeviceLibrary._();
  static final DeviceLibrary instance = DeviceLibrary._();

  /// Mirrors the Library > Storage tab.
  static const String primaryRoot = '/storage/emulated/0/Music';

  /// Scanned but never listed as a playlist themselves, matching the app.
  static const List<String> extraRoots = [
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Documents',
  ];

  static const List<String> _audioExts = [
    '.mp3',
    '.m4a',
    '.opus',
    '.flac',
    '.wav',
    '.ogg',
    '.aac',
  ];

  /// Ceiling on files visited per scan. A 10k-track library is already far more
  /// than a car browse tree should offer, and the walk runs while Android Auto
  /// is waiting on a response.
  static const int _maxFiles = 4000;

  /// Playlists are cached: Android Auto re-queries the root every time the tree
  /// is opened, and re-walking storage each time would make the car UI stutter.
  static List<PlaylistModel>? _cache;
  static DateTime? _cachedAt;
  static const Duration _ttl = Duration(minutes: 5);

  /// True while a scan is in flight, so callers can tell "empty" from "not
  /// looked yet".
  static bool _scanning = false;
  static bool get isScanning => _scanning;

  /// Called when a scan finishes so the browse tree can push an update to the
  /// car instead of leaving a stale (possibly empty) list on screen.
  static final List<VoidCallback> _listeners = [];

  static void addListener(VoidCallback l) => _listeners.add(l);

  static void removeListener(VoidCallback l) => _listeners.remove(l);

  static void _notify() {
    for (final l in List.of(_listeners)) {
      try {
        l();
      } catch (_) {}
    }
  }

  /// Playlists built from folders that contain audio, one playlist per folder.
  static Future<List<PlaylistModel>> load({bool force = false}) async {
    final now = DateTime.now();
    final cached = _cache;
    if (!force &&
        cached != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < _ttl) {
      return cached;
    }
    if (_scanning) return cached ?? const [];
    _scanning = true;
    try {
      final out = await _scan();
      _cache = out;
      _cachedAt = now;
      return out;
    } catch (e) {
      debugPrint('[DeviceLibrary] scan failed: $e');
      return _cache ?? const [];
    } finally {
      _scanning = false;
      _notify();
    }
  }

  static Future<List<PlaylistModel>> _scan() async {
    if (!await _canRead()) return const [];

    final roots = <String>[primaryRoot];
    if (!await Directory(primaryRoot).exists()) {
      roots
        ..clear()
        ..addAll(extraRoots);
    }

    final files = <File>[];
    for (final root in roots) {
      if (files.length >= _maxFiles) break;
      await _walk(Directory(root), files);
    }
    if (files.isEmpty) return const [];

    // Group by immediate parent folder, matching how the Storage tab presents
    // a folder: folder name becomes the playlist name and the "artist".
    final grouped = <String, List<TrackModel>>{};
    for (final f in files) {
      final path = f.path;
      final dir = f.parent.path;
      final name = path.split('/').last;
      final title = name.replaceFirst(
        RegExp(r'\.(mp3|m4a|opus|flac|wav|ogg|aac)$', caseSensitive: false),
        '',
      );
      final folder = _folderName(dir);
      grouped
          .putIfAbsent(dir, () => [])
          .add(
            TrackModel(
              // Same id scheme as the Storage tab so downloads and local-file
              // lookups match regardless of which surface built the track.
              id: 'storage_${path.hashCode}',
              title: title.isEmpty ? 'Unknown' : title,
              artists: folder,
              album: 'On this device',
              cover: '',
              sourceUrl: path,
            ),
          );
    }

    final out = <PlaylistModel>[];
    grouped.forEach((dir, tracks) {
      tracks.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
      out.add(
        PlaylistModel(
          // `device:` rather than the `storage_` used by track ids, because
          // other code tests playlist ids against that prefix.
          id: 'device:$dir',
          name: _folderName(dir),
          owner: 'This device',
          tracks: tracks,
          source: 'local',
          creatorUid: 'device',
          isUsersOwn: true,
        ),
      );
    });
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  static String _folderName(String dir) {
    final parts = dir.split('/').where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? dir : parts.last;
  }

  /// Breadth-ish walk with symlink and depth guards.
  ///
  /// `[symlink]` links are skipped so a self-referential link cannot spin the
  /// walk forever on the car's behalf.
  static Future<void> _walk(Directory dir, List<File> out) async {
    if (out.length >= _maxFiles) return;
    List<FileSystemEntity> entries;
    try {
      if (!await dir.exists()) return;
      entries = await dir.list(followLinks: false).toList();
    } catch (_) {
      // Unreadable folder (permissions on one subdir) shouldn't kill the scan.
      return;
    }
    for (final e in entries) {
      if (out.length >= _maxFiles) return;
      if (e is Link) continue;
      final name = e.path.split('/').last;
      if (name.startsWith('.')) continue;
      if (e is File) {
        final lower = e.path.toLowerCase();
        if (_audioExts.any(lower.endsWith)) out.add(e);
      } else if (e is Directory) {
        await _walk(e, out);
      }
    }
  }

  /// Mirrors the Storage tab's permission check: all-files access on API 30+,
  /// plain media read below that.
  static Future<bool> _canRead() async {
    try {
      if (!Platform.isAndroid) return false;
      if (await perm.Permission.manageExternalStorage.isGranted) return true;
      if (await perm.Permission.audio.isGranted) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  @visibleForTesting
  static void clearCache() {
    _cache = null;
    _cachedAt = null;
  }
}
