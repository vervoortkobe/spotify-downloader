import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotterfy_app/services/network_stats_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';

const _playlistColor = SpotterfyTheme.primary;
const _imageColor = Color(0xFF38bdf8);
const _otherColor = Color(0xFFa1a1aa);

class StorageSnapshot {
  final int at;
  final int playlistCache;
  final int images;
  final int other;
  const StorageSnapshot({required this.at, required this.playlistCache, required this.images, required this.other});
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
  List<StorageSnapshot> _history = [];

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
          history.add(StorageSnapshot(at: now, playlistCache: playlistCache, images: images, other: other));
          if (history.length > 30) history = history.sublist(history.length - 30);
          await prefs.setString('storage_history_v1', jsonEncode(history.map((s) => {
                'at': s.at,
                'playlistCache': s.playlistCache,
                'images': s.images,
                'other': s.other,
              }).toList()));
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _playlistCache = playlistCache;
      _images = images;
      _other = other;
      _history = history;
      _loading = false;
    });
  }

  Future<void> _resetCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotterfyTheme.surface,
        title: const Text('Reset cache?', style: TextStyle(color: SpotterfyTheme.text)),
        content: const Text('Deletes playlist track files and cached covers. Playlists re-download on demand.',
            style: TextStyle(color: SpotterfyTheme.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: SpotterfyTheme.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset', style: TextStyle(color: Colors.red))),
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache cleared'), duration: Duration(seconds: 2)));
    await _measure(recordHistory: true);
  }

  @override
  Widget build(BuildContext context) {
    final total = _playlistCache + _images + _other;
    return SwipeBackWrapper(
      child: Scaffold(
        backgroundColor: SpotterfyTheme.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('Storage usage', style: TextStyle(color: SpotterfyTheme.text, fontWeight: FontWeight.bold, fontSize: 22)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('App storage', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _card(_loading
                  ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)))
                  : Column(children: [
                      _usageRow(_playlistColor, 'Playlist files', _playlistCache, total),
                      const SizedBox(height: 10),
                      _usageRow(_imageColor, 'Cover images', _images, total),
                      const SizedBox(height: 10),
                      _usageRow(_otherColor, 'Other app data', _other, total),
                      const Divider(color: SpotterfyTheme.card, height: 24),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Total', style: TextStyle(color: SpotterfyTheme.text, fontSize: 14, fontWeight: FontWeight.w700)),
                        Text(NetworkStatsService.formatBytes(total),
                            style: const TextStyle(color: SpotterfyTheme.text, fontSize: 14, fontWeight: FontWeight.w700)),
                      ]),
                    ])),
              const SizedBox(height: 20),
              const Text('History', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _legendDot(_playlistColor, 'Playlists'),
                  const SizedBox(width: 16),
                  _legendDot(_imageColor, 'Images'),
                  const SizedBox(width: 16),
                  _legendDot(_otherColor, 'Other'),
                ]),
                const SizedBox(height: 12),
                if (_history.length < 2)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Not enough history yet — check back later', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 13))),
                  )
                else
                  SizedBox(height: 190, child: _StorageGraph(history: _history)),
              ])),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (_loading || _resetting) ? null : _resetCache,
                  icon: _resetting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cleaning_services_outlined, size: 18),
                  label: Text(_resetting ? 'Clearing…' : 'Reset cache'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
        decoration: BoxDecoration(color: SpotterfyTheme.surface, borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  Widget _usageRow(Color color, String label, int value, int total) {
    final frac = total > 0 ? value / total : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: SpotterfyTheme.text, fontSize: 13)),
        ]),
        Text(NetworkStatsService.formatBytes(value),
            style: const TextStyle(color: SpotterfyTheme.text, fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
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
    ]);
  }

  Widget _legendDot(Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
      ]);
}

class _StorageGraph extends StatelessWidget {
  final List<StorageSnapshot> history;
  const _StorageGraph({required this.history});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StorageGraphPainter(history: history),
      child: Container(),
    );
  }
}

class _StorageGraphPainter extends CustomPainter {
  final List<StorageSnapshot> history;
  _StorageGraphPainter({required this.history});

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 20.0;
    const topPad = 18.0;
    final chartH = size.height - labelH;
    final maxV = history.fold<int>(1, (m, s) => s.total > m ? s.total : m).toDouble();
    final n = history.length;
    final stepX = n > 1 ? size.width / (n - 1) : 0.0;

    final gridPaint = Paint()..color = SpotterfyTheme.card..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = topPad + (chartH - topPad) * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    Offset pt(int i, int v) {
      final x = n > 1 ? stepX * i : size.width / 2;
      final y = chartH - (maxV > 0 ? (v / maxV) * (chartH - topPad - 4) : 0);
      return Offset(x, y);
    }

    void line(List<Offset> pts, Color color, double width) {
      if (pts.isEmpty) return;
      final paint = Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (pts.length == 1) {
        canvas.drawCircle(pts.first, width / 2, paint);
        return;
      }
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    line([for (var i = 0; i < n; i++) pt(i, history[i].other)], _otherColor, 2);
    line([for (var i = 0; i < n; i++) pt(i, history[i].images)], _imageColor, 2);
    line([for (var i = 0; i < n; i++) pt(i, history[i].playlistCache)], _playlistColor, 2.5);

    for (var i = 0; i < n; i++) {
      canvas.drawCircle(pt(i, history[i].total), 3, Paint()..color = SpotterfyTheme.text);
    }

    // Date labels: first, middle, last
    final labelStyle = const TextStyle(color: SpotterfyTheme.muted, fontSize: 10);
    void label(int i, double align) {
      final d = DateTime.fromMillisecondsSinceEpoch(history[i].at);
      final text = '${d.day}/${d.month}';
      final tp = TextPainter(text: TextSpan(text: text, style: labelStyle), textDirection: TextDirection.ltr)..layout();
      final x = (n > 1 ? stepX * i : size.width / 2) - tp.width * align;
      tp.paint(canvas, Offset(x.clamp(0.0, size.width - tp.width), chartH + 4));
    }

    if (n > 0) {
      label(0, 0);
      if (n > 2) label(n ~/ 2, 0.5);
      if (n > 1) label(n - 1, 1);
    }

    final maxLabel = TextPainter(
        text: TextSpan(text: NetworkStatsService.formatBytes(maxV.toInt()), style: labelStyle),
        textDirection: TextDirection.ltr)
      ..layout();
    maxLabel.paint(canvas, Offset(size.width - maxLabel.width, 0));
  }

  @override
  bool shouldRepaint(covariant _StorageGraphPainter old) => old.history != history;
}
