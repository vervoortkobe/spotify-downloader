import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotterfy_app/services/network_stats_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/app_chrome.dart';

// Follows the accent, so these cannot be const any more.
final _playlistColor = SpotterfyTheme.primary;
const _imageColor = Color(0xFF38bdf8);
final _otherColor = SpotterfyTheme.mutedDark;

class StorageSnapshot {
  final int at;
  final int playlistCache;
  final int images;
  final int other;
  const StorageSnapshot({
    required this.at,
    required this.playlistCache,
    required this.images,
    required this.other,
  });
  int get total => playlistCache + images + other;
}

class StorageUsageScreen extends StatefulWidget {
  const StorageUsageScreen({super.key});

  @override
  State<StorageUsageScreen> createState() => _StorageUsageScreenState();
}

class _StorageUsageScreenState extends State<StorageUsageScreen> {
  bool _loading = true;
  bool _resetting = false;
  int _playlistCache = 0;
  int _images = 0;
  int _other = 0;

  @override
  void initState() {
    super.initState();
    _measure(recordHistory: true);
  }

  Future<int> _dirSize(Directory dir) async {
    var total = 0;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        try {
          if (e is File) total += await e.length();
        } catch (_) {}
      }
    } catch (_) {}
    return total;
  }

  Future<void> _measure({bool recordHistory = false}) async {
    setState(() => _loading = true);
    var playlistCache = 0;
    var images = 0;
    var other = 0;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final pcDir = Directory('${docs.path}/playlist_cache');
      playlistCache = await _dirSize(pcDir);
      final docsTotal = await _dirSize(docs);
      other = (docsTotal - playlistCache).clamp(0, docsTotal);
      try {
        final tmp = await getTemporaryDirectory();
        images = await _dirSize(tmp);
      } catch (_) {}
    } catch (_) {}
    List<StorageSnapshot> history = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('storage_history_v1');
      if (raw != null) {
        history = ((jsonDecode(raw) as List<dynamic>?) ?? []).map((e) {
          final m = e as Map<String, dynamic>;
          return StorageSnapshot(
            at: (m['at'] as num? ?? 0).toInt(),
            playlistCache: (m['playlistCache'] as num? ?? 0).toInt(),
            images: (m['images'] as num? ?? 0).toInt(),
            other: (m['other'] as num? ?? 0).toInt(),
          );
        }).toList();
      }
      if (recordHistory) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final lastAt = history.isEmpty ? 0 : history.last.at;
        if (now - lastAt > const Duration(hours: 1).inMilliseconds) {
          history.add(
            StorageSnapshot(
              at: now,
              playlistCache: playlistCache,
              images: images,
              other: other,
            ),
          );
          if (history.length > 30) {
            history = history.sublist(history.length - 30);
          }
          await prefs.setString(
            'storage_history_v1',
            jsonEncode(
              history
                  .map(
                    (s) => {
                      'at': s.at,
                      'playlistCache': s.playlistCache,
                      'images': s.images,
                      'other': s.other,
                    },
                  )
                  .toList(),
            ),
          );
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _playlistCache = playlistCache;
      _images = images;
      _other = other;
      _loading = false;
    });
  }

  Future<void> _resetCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotterfyTheme.surface,
        title: Text(
          'Reset cache?',
          style: TextStyle(color: SpotterfyTheme.text),
        ),
        content: Text(
          'Deletes playlist track files and cached covers. Playlists re-download on demand.',
          style: TextStyle(color: SpotterfyTheme.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: SpotterfyTheme.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _resetting = true);
    try {
      final docs = await getApplicationDocumentsDirectory();
      final pcDir = Directory('${docs.path}/playlist_cache');
      if (await pcDir.exists()) {
        await for (final e in pcDir.list(followLinks: false)) {
          try {
            await e.delete(recursive: true);
          } catch (_) {}
        }
      }
      await DefaultCacheManager().emptyCache();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _resetting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cache cleared'), duration: Duration(seconds: 2)),
    );
    await _measure(recordHistory: true);
  }

  @override
  Widget build(BuildContext context) {
    final total = _playlistCache + _images + _other;
    return HideAppChrome(
      child: AppGradientScaffold(
        title: 'Storage Usage',
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'App storage',
                style: TextStyle(
                  color: SpotterfyTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _card(
                _loading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Column(
                        children: [
                          _usageRow(
                            _playlistColor,
                            'Playlist files',
                            _playlistCache,
                            total,
                          ),
                          const SizedBox(height: 10),
                          _usageRow(
                            _imageColor,
                            'Cover images',
                            _images,
                            total,
                          ),
                          const SizedBox(height: 10),
                          _usageRow(
                            _otherColor,
                            'Other app data',
                            _other,
                            total,
                          ),
                          Divider(color: SpotterfyTheme.card, height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total',
                                style: TextStyle(
                                  color: SpotterfyTheme.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                NetworkStatsService.formatBytes(total),
                                style: TextStyle(
                                  color: SpotterfyTheme.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: (_loading || _resetting) ? null : _resetCache,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            SpotterfyTheme.primary.withValues(alpha: 0.12),
                            SpotterfyTheme.primary.withValues(alpha: 0.04),
                          ],
                        ),
                        border: Border.all(
                          color: SpotterfyTheme.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _resetting
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: SpotterfyTheme.primary,
                                  ),
                                )
                              : Icon(
                                  Icons.logout_rounded,
                                  size: 20,
                                  color: SpotterfyTheme.primary,
                                ),
                          const SizedBox(width: 10),
                          Text(
                            _resetting ? 'Clearing cache…' : 'Reset cache',
                            style: TextStyle(
                              color: SpotterfyTheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: SpotterfyTheme.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  Widget _usageRow(Color color, String label, int value, int total) {
    final frac = total > 0 ? value / total : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(color: SpotterfyTheme.text, fontSize: 13),
                ),
              ],
            ),
            Text(
              NetworkStatsService.formatBytes(value),
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 6,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: frac.clamp(0.0, 1.0),
              child: Container(color: color),
            ),
          ),
        ),
      ],
    );
  }
}