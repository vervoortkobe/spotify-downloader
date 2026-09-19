import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/status_provider.dart';
import 'package:spotterfy_app/services/network_stats_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';

const _wifiColor = SpotterfyTheme.primary;
const _cellColor = Color(0xFF38bdf8);

class DataUsageScreen extends StatelessWidget {
  const DataUsageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final net = context.watch<NetworkStatsService>();
    final status = context.watch<StatusProvider>();
    return SwipeBackWrapper(
      child: Scaffold(
        backgroundColor: SpotterfyTheme.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('Data Usage', style: TextStyle(color: SpotterfyTheme.text, fontWeight: FontWeight.bold, fontSize: 22)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Right now'),
              _nowCard(net),
              const SizedBox(height: 20),
              _sectionTitle('This month'),
              _monthCard(net),
              const SizedBox(height: 20),
              _sectionTitle('History'),
              _historyCard(net),
              const SizedBox(height: 20),
              _sectionTitle('Services'),
              _servicesCard(status),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(color: SpotterfyTheme.muted, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: SpotterfyTheme.surface, borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  Widget _nowCard(NetworkStatsService net) {
    final connLabel = !net.online ? 'OFFLINE' : (net.isCellular ? 'MOBILE DATA' : 'WI-FI');
    final connColor = !net.online ? const Color(0xFFef4444) : (net.isCellular ? _cellColor : _wifiColor);
    final connIcon = !net.online
        ? Icons.signal_wifi_off
        : (net.isCellular ? Icons.signal_cellular_alt : Icons.wifi);
    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: connColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: connColor.withValues(alpha: 0.35))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(connIcon, size: 14, color: connColor),
            const SizedBox(width: 6),
            Text(connLabel, style: TextStyle(color: connColor, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _speedTile(Icons.arrow_downward, _wifiColor, 'Down', '${NetworkStatsService.formatBytes(net.downSpeed)}/s')),
          const SizedBox(width: 12),
          Expanded(child: _speedTile(Icons.arrow_upward, _cellColor, 'Up', '${NetworkStatsService.formatBytes(net.upSpeed)}/s')),
        ]),
        const SizedBox(height: 12),
        Text('This session: ↓ ${NetworkStatsService.formatBytes(net.downBytes)} · ↑ ${NetworkStatsService.formatBytes(net.upBytes)}',
            style: const TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
      ],
    ));
  }

  Widget _speedTile(IconData icon, Color color, String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: SpotterfyTheme.card, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: SpotterfyTheme.muted, fontSize: 11)),
            Text(value, style: const TextStyle(color: SpotterfyTheme.text, fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
          ]),
        ]),
      );

  Widget _monthCard(NetworkStatsService net) {
    final wifi = net.totalWifi;
    final cell = net.totalCellular;
    final total = wifi + cell;
    return _card(Column(children: [
      _usageRow(_wifiColor, 'Wi-Fi', wifi, total),
      const SizedBox(height: 10),
      _usageRow(_cellColor, 'Mobile data', cell, total),
      const Divider(color: SpotterfyTheme.card, height: 24),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Total', style: TextStyle(color: SpotterfyTheme.text, fontSize: 14, fontWeight: FontWeight.w700)),
        Text(NetworkStatsService.formatBytes(total), style: const TextStyle(color: SpotterfyTheme.text, fontSize: 14, fontWeight: FontWeight.w700)),
      ]),
    ]));
  }

  Widget _usageRow(Color color, String label, int value, int total) {
    final frac = total > 0 ? value / total : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: SpotterfyTheme.text, fontSize: 13)),
        ]),
        Text(NetworkStatsService.formatBytes(value), style: const TextStyle(color: SpotterfyTheme.text, fontSize: 13, fontWeight: FontWeight.w600)),
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

  Widget _historyCard(NetworkStatsService net) {
    final data = net.history;
    final hasData = data.any((m) => m.total > 0);
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _legendDot(_wifiColor, 'Wi-Fi'),
        const SizedBox(width: 16),
        _legendDot(_cellColor, 'Mobile'),
        const Spacer(),
        if (net.historyLoading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      const SizedBox(height: 12),
      if (!hasData && !net.historyLoading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('No usage recorded yet', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 13))),
        )
      else
        SizedBox(height: 190, child: _UsageGraph(data: data, currentMonth: net.month)),
    ]));
  }

  Widget _legendDot(Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
      ]);

  Widget _servicesCard(StatusProvider status) {
    final backend = status.backendOnline;
    final warp = status.warpConnected;
    return _card(Column(children: [
      _serviceRow(
        icon: Icons.cloud_outlined,
        title: 'Backend',
        state: backend == null ? 'Checking…' : (backend ? 'Online' : 'Offline'),
        color: backend == null ? SpotterfyTheme.muted : (backend ? _wifiColor : const Color(0xFFef4444)),
      ),
      const Divider(color: SpotterfyTheme.card, height: 20),
      _serviceRow(
        icon: warp == true ? Icons.shield : Icons.shield_outlined,
        title: 'WARP',
        state: warp == null ? 'Checking…' : (warp ? 'Connected' : 'Off'),
        color: warp == null ? SpotterfyTheme.muted : (warp ? _wifiColor : SpotterfyTheme.muted),
      ),
    ]));
  }

  Widget _serviceRow({required IconData icon, required String title, required String state, required Color color}) => Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(color: SpotterfyTheme.text, fontSize: 15, fontWeight: FontWeight.w600)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
          child: Text(state, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]);
}

class _UsageGraph extends StatelessWidget {
  final List<MonthUsage> data;
  final String currentMonth;
  const _UsageGraph({required this.data, required this.currentMonth});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _UsageGraphPainter(data: data, currentMonth: currentMonth),
      child: Container(),
    );
  }
}

class _UsageGraphPainter extends CustomPainter {
  final List<MonthUsage> data;
  final String currentMonth;
  _UsageGraphPainter({required this.data, required this.currentMonth});

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 20.0;
    const topPad = 18.0;
    final chartH = size.height - labelH;
    final maxV = data.fold<int>(1, (m, e) => e.total > m ? e.total : m).toDouble();
    final n = data.length;
    final groupW = size.width / n;
    const barW = 14.0;

    final gridPaint = Paint()..color = SpotterfyTheme.card..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = topPad + (chartH - topPad) * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final wifiPaint = Paint()..color = _wifiColor;
    final cellPaint = Paint()..color = _cellColor;
    final labelStyle = const TextStyle(color: SpotterfyTheme.muted, fontSize: 10);
    final valueStyle = const TextStyle(color: SpotterfyTheme.text, fontSize: 9, fontWeight: FontWeight.w600);

    for (var i = 0; i < n; i++) {
      final m = data[i];
      final cx = groupW * i + groupW / 2;
      final isCurrent = m.month == currentMonth;
      final maxBarH = chartH - topPad - 4;
      final wifiH = maxBarH * (m.wifi / maxV);
      final cellH = maxBarH * (m.cellular / maxV);

      RRect bar(double x, double h, Paint p) => RRect.fromRectAndCorners(
            Rect.fromLTWH(x, chartH - h, barW, h),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          );
      if (m.wifi > 0) canvas.drawRRect(bar(cx - barW - 2, wifiH, wifiPaint), wifiPaint);
      if (m.cellular > 0) canvas.drawRRect(bar(cx + 2, cellH, cellPaint), cellPaint);
      if (m.total == 0) {
        canvas.drawCircle(Offset(cx, chartH - 2), 2, Paint()..color = SpotterfyTheme.card);
      }

      if (isCurrent && m.total > 0) {
        // value label above tallest bar
        final vt = TextPainter(text: TextSpan(text: NetworkStatsService.formatBytes(m.total), style: valueStyle), textDirection: TextDirection.ltr)..layout();
        vt.paint(canvas, Offset(cx - vt.width / 2, 0));
        final tp = TextPainter(text: TextSpan(text: m.shortLabel, style: valueStyle), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, chartH + 4));
      } else {
        final tp = TextPainter(text: TextSpan(text: m.shortLabel, style: labelStyle), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, chartH + 4));
      }
      if (isCurrent) {
        canvas.drawCircle(Offset(cx, chartH + 12), 2, Paint()..color = _wifiColor);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _UsageGraphPainter old) => old.data != data || old.currentMonth != currentMonth;
}
