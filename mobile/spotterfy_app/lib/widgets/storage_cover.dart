import 'dart:io';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/material.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// In-memory cache of embedded covers keyed by file path, so play/pause or
/// position ticks (which rebuild listeners constantly) never re-read files
/// and the cover never flashes, reloads or disappears.
class StorageCoverCache {
  static final Map<String, Uint8List?> _cache = {};

  static bool contains(String path) => _cache.containsKey(path);

  static Future<Uint8List?> load(String path) async {
    if (_cache.containsKey(path)) return _cache[path];
    Uint8List? bytes;
    try {
      final meta = readMetadata(File(path), getImage: true);
      if (meta.pictures.isNotEmpty) bytes = meta.pictures.first.bytes;
    } catch (_) {}
    _cache[path] = bytes;
    return bytes;
  }
}

/// Embedded cover art for an on-device audio file.
/// Memoizes its load future per path: rebuilds reuse the same future, so the
/// image stays put instead of flashing a spinner/placeholder every rebuild.
class StorageCover extends StatefulWidget {
  final String path;
  final double size;
  final double iconSize;
  final double radius;

  const StorageCover({
    super.key,
    required this.path,
    this.size = 48,
    this.iconSize = 24,
    this.radius = 8,
  });

  @override
  State<StorageCover> createState() => _StorageCoverState();
}

class _StorageCoverState extends State<StorageCover> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _future = StorageCoverCache.load(widget.path);
  }

  @override
  void didUpdateWidget(covariant StorageCover old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _future = StorageCoverCache.load(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (_, snap) {
        final bytes = snap.data;
        if (bytes != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(widget.radius),
            child: Image.memory(
              bytes,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => _fallback(),
            ),
          );
        }
        return _fallback();
      },
    );
  }

  Widget _fallback() => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: SpotterfyTheme.surface,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: Icon(Icons.music_note, color: SpotterfyTheme.muted, size: widget.iconSize),
      );
}
