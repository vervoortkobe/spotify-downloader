import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/status_provider.dart';
import 'package:spotterfy_app/services/network_stats_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/app_chrome.dart';

final _wifiColor = SpotterfyTheme.primary;
final _cellColor = Color(0xFF38bdf8);

class DataUsageScreen extends StatelessWidget {
  const DataUsageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final net = context.watch<NetworkStatsService>();
    final status = context.watch<StatusProvider>();
    return HideAppChrome(
      child: AppGradientScaffold(
        title: 'Data Usage',
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
              _servicesCard(status, net),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: TextStyle(
        color: SpotterfyTheme.muted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: SpotterfyTheme.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  Widget _nowCard(NetworkStatsService net) {
    final connLabel = !net.online
        ? 'OFFLINE'
        : (net.isCellular ? 'MOBILE DATA' : 'WI-FI');
    final connColor = !net.online
        ? const Color(0xFFef4444)
        : (net.isCellular ? _cellColor : _wifiColor);
    final connIcon = !net.online
        ? Icons.signal_wifi_off
        : (net.isCellular ? Icons.signal_cellular_alt : Icons.wifi);
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: connColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: connColor.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(connIcon, size: 14, color: connColor),
                const SizedBox(width: 6),
                Text(
                  connLabel,
                  style: TextStyle(
                    color: connColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _speedTile(
                  Icons.arrow_downward,
                  _wifiColor,
                  'Down',
                  '${NetworkStatsService.formatBytes(net.downSpeed)}/s',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _speedTile(
                  Icons.arrow_upward,
                  _cellColor,
                  'Up',
                  '${NetworkStatsService.formatBytes(net.upSpeed)}/s',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'This session: ↓ ${NetworkStatsService.formatBytes(net.downBytes)} · ↑ ${NetworkStatsService.formatBytes(net.upBytes)}',
            style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _speedTile(IconData icon, Color color, String label, String value) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: SpotterfyTheme.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: SpotterfyTheme.muted, fontSize: 11),
                ),
                Text(
                  value,
                  style: TextStyle(
                    color: SpotterfyTheme.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _monthCard(NetworkStatsService net) {
    final wifi = net.totalWifi;
    final cell = net.totalCellular;
    final total = wifi + cell;
    return _card(
      Column(
        children: [
          _usageRow(_wifiColor, 'Wi-Fi', wifi, total),
          const SizedBox(height: 10),
          _usageRow(_cellColor, 'Mobile data', cell, total),
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
    );
  }

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

  Widget _historyCard(NetworkStatsService net) {
    final data = net.history;
    final hasData = data.any((m) => m.total > 0);
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _legendDot(_wifiColor, 'Wi-Fi'),
              const SizedBox(width: 16),
              _legendDot(_cellColor, 'Mobile'),
              const Spacer(),
              if (net.historyLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasData && !net.historyLoading)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No usage recorded yet',
                  style: TextStyle(color: SpotterfyTheme.muted, fontSize: 13),
                ),
              ),
            )
          else
            _UsageLineChart(data: data, currentMonth: net.month),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
    ],
  );

  Widget _servicesCard(StatusProvider status, NetworkStatsService net) {
    final backend = status.backendOnline;
    final warp = status.warpConnected;
    final connTitle = !net.online
        ? 'Offline'
        : (net.isCellular ? 'Mobile data' : 'Wi-Fi');
    final connIcon = !net.online
        ? Icons.signal_wifi_off
        : (net.isCellular ? Icons.signal_cellular_alt : Icons.wifi);
    final connColor = !net.online ? const Color(0xFFef4444) : _wifiColor;
    return _card(
      Column(
        children: [
          _serviceRow(
            icon: connIcon,
            title: 'Connected',
            state: connTitle,
            color: connColor,
          ),
          Divider(color: SpotterfyTheme.card, height: 20),
          _serviceRow(
            icon: Icons.cloud_outlined,
            title: 'Backend',
            state: backend == null
                ? 'Checking…'
                : (backend ? 'Online' : 'Offline'),
            color: backend == null
                ? SpotterfyTheme.muted
                : (backend ? _wifiColor : const Color(0xFFef4444)),
          ),
          Divider(color: SpotterfyTheme.card, height: 20),
          _serviceRow(
            icon: warp == true ? Icons.shield : Icons.shield_outlined,
            title: 'WARP',
            state: warp == null ? 'Checking…' : (warp ? 'Connected' : 'Off'),
            color: warp == null
                ? SpotterfyTheme.muted
                : (warp ? _wifiColor : SpotterfyTheme.muted),
          ),
        ],
      ),
    );
  }

  Widget _serviceRow({
    required IconData icon,
    required String title,
    required String state,
    required Color color,
  }) => Row(
    children: [
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 12),
      Text(
        title,
        style: TextStyle(
          color: SpotterfyTheme.text,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      const Spacer(),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          state,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

/// Interactive line chart for data usage history.
/// Supports tap-and-drag to inspect individual data points.
class _UsageLineChart extends StatefulWidget {
  final List<MonthUsage> data;
  final String currentMonth;
  const _UsageLineChart({required this.data, required this.currentMonth});

  @override
  State<_UsageLineChart> createState() => _UsageLineChartState();
}

class _UsageLineChartState extends State<_UsageLineChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final chartHeight = 200.0;
        return Column(
          children: [
            SizedBox(
              height: chartHeight,
              width: constraints.maxWidth,
              child: GestureDetector(
                onTapDown: (details) => _handleTap(details.localPosition, constraints.maxWidth, chartHeight),
                onHorizontalDragUpdate: (details) => _handleTap(details.localPosition, constraints.maxWidth, chartHeight),
                child: CustomPaint(
                  painter: _UsageLineChartPainter(
                    data: widget.data,
                    currentMonth: widget.currentMonth,
                    selectedIndex: _selectedIndex,
                  ),
                ),
              ),
            ),
            if (_selectedIndex != null && _selectedIndex! >= 0 && _selectedIndex! < widget.data.length)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _buildDetailCard(widget.data[_selectedIndex!]),
              ),
          ],
        );
      },
    );
  }

  void _handleTap(Offset position, double width, double height) {
    const labelH = 20.0;
    final chartH = height - labelH;
    final chartTop = 18.0;
    final chartBottom = chartH - 4;
    if (position.dy < chartTop || position.dy > chartBottom) return;

    final data = widget.data;
    if (data.isEmpty) return;

    final n = data.length;
    final stepX = n > 1 ? width / (n - 1) : width / 2;
    final x = n > 1 ? position.dx : width / 2;
    final idx = (x / stepX).round().clamp(0, n - 1);

    setState(() => _selectedIndex = idx);
  }

  Widget _buildDetailCard(MonthUsage m) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SpotterfyTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _wifiColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m.shortLabel,
            style: TextStyle(
              color: SpotterfyTheme.text,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _detailRow(_wifiColor, 'Wi-Fi', m.wifi),
          const SizedBox(height: 4),
          _detailRow(_cellColor, 'Mobile', m.cellular),
          const SizedBox(height: 4),
          _detailRow(SpotterfyTheme.mutedDark, 'Total', m.total),
        ],
      ),
    );
  }

  Widget _detailRow(Color color, String label, int value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12),
            ),
          ],
        ),
        Text(
          NetworkStatsService.formatBytes(value),
          style: TextStyle(
            color: SpotterfyTheme.text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _UsageLineChartPainter extends CustomPainter {
  final List<MonthUsage> data;
  final String currentMonth;
  final int? selectedIndex;
  _UsageLineChartPainter({
    required this.data,
    required this.currentMonth,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 20.0;
    const topPad = 18.0;
    final chartH = size.height - labelH;
    final maxV = data.fold<int>(1, (m, e) => e.total > m ? e.total : m).toDouble();
    final n = data.length;

    // Grid
    final gridPaint = Paint()
      ..color = SpotterfyTheme.card
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = topPad + (chartH - topPad) * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (n == 0) return;

    Offset pt(int i, double v) {
      final x = n > 1 ? (size.width / (n - 1)) * i : size.width / 2;
      final y = chartH - (maxV > 0 ? (v / maxV) * (chartH - topPad - 4) : 0);
      return Offset(x, y);
    }

    void drawLine(List<Offset> pts, Color color, double width) {
      if (pts.isEmpty) return;
      final paint = Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (pts.length == 1) {
        canvas.drawCircle(pts.first, width / 2, Paint()..color = color);
        return;
      }
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    // Draw lines
    drawLine(
      [for (var i = 0; i < n; i++) pt(i, data[i].wifi.toDouble())],
      _wifiColor,
      2.5,
    );
    drawLine(
      [for (var i = 0; i < n; i++) pt(i, data[i].cellular.toDouble())],
      _cellColor,
      2,
    );

    // Draw points and selection
    final labelStyle = TextStyle(color: SpotterfyTheme.muted, fontSize: 10);
    for (var i = 0; i < n; i++) {
      final p = pt(i, data[i].total.toDouble());
      final isSelected = selectedIndex == i;

      // Point
      canvas.drawCircle(
        p,
        isSelected ? 5 : 3,
        Paint()..color = isSelected ? _wifiColor : SpotterfyTheme.text,
      );

      // Selection highlight
      if (isSelected) {
        final wifiPt = pt(i, data[i].wifi.toDouble());
        final cellPt = pt(i, data[i].cellular.toDouble());
        canvas.drawCircle(wifiPt, 4, Paint()..color = _wifiColor);
        canvas.drawCircle(cellPt, 4, Paint()..color = _cellColor);

        // Vertical selection line
        final selLinePaint = Paint()
          ..color = SpotterfyTheme.muted.withValues(alpha: 0.3)
          ..strokeWidth = 1;
        canvas.drawLine(
          Offset(p.dx, topPad),
          Offset(p.dx, chartH),
          selLinePaint,
        );
      }

      // Date labels: first, middle, last
      if (i == 0 || i == n - 1 || i == n ~/ 2) {
        final d = data[i].month;
        final tp = TextPainter(
          text: TextSpan(text: d, style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final double x = (i == 0 ? 0.0 : (i == n - 1 ? size.width - tp.width : p.dx - tp.width / 2));
        tp.paint(canvas, Offset(x.clamp(0.0, size.width - tp.width), chartH + 4));
      }
    }

    // Max value label
    final maxLabel = TextPainter(
      text: TextSpan(
        text: NetworkStatsService.formatBytes(maxV.toInt()),
        style: labelStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    maxLabel.paint(canvas, Offset(size.width - maxLabel.width, 0));
  }

  @override
  bool shouldRepaint(covariant _UsageLineChartPainter old) =>
      old.data != data || old.currentMonth != currentMonth || old.selectedIndex != selectedIndex;
}