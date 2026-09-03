import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/status_provider.dart';
import 'package:spotterfy_app/services/network_stats_service.dart';

class FloatingStatusBar extends StatelessWidget {
  const FloatingStatusBar({super.key});

  Widget _pill({required Widget icon, required String label, required Color color, required Color bg, String? sub}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
          if (sub != null) Text(sub, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 9)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<StatusProvider>();
    final net = context.watch<NetworkStatsService>();
    final backend = status.backendOnline;
    final warp = status.warpConnected;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF020604).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (backend == null)
                    _pill(icon: const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1.5)), label: 'Backend …', color: const Color(0xFFa1a1aa), bg: Colors.white.withValues(alpha: 0.04))
                  else if (backend)
                    _pill(icon: Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF10b981), shape: BoxShape.circle)), label: 'Backend', color: const Color(0xFF10b981), bg: const Color(0xFF10b981).withValues(alpha: 0.12))
                  else
                    _pill(icon: const Icon(Icons.wifi_off, size: 10, color: Color(0xFFef4444)), label: 'Backend Off', color: const Color(0xFFef4444), bg: const Color(0xFFef4444).withValues(alpha: 0.12)),
                  if (warp == null)
                    _pill(icon: const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1.5)), label: 'WARP …', color: const Color(0xFFa1a1aa), bg: Colors.white.withValues(alpha: 0.04))
                  else if (warp)
                    _pill(icon: const Icon(Icons.shield, size: 10, color: Color(0xFF10b981)), label: 'WARP', color: const Color(0xFF10b981), bg: const Color(0xFF10b981).withValues(alpha: 0.12))
                  else
                    _pill(icon: const Icon(Icons.shield_outlined, size: 10, color: Color(0xFFa1a1aa)), label: 'WARP Off', color: const Color(0xFFa1a1aa), bg: Colors.white.withValues(alpha: 0.04)),
                  if (!net.online)
                    _pill(icon: const Icon(Icons.signal_wifi_off, size: 10, color: Color(0xFFef4444)), label: 'OFFLINE', color: const Color(0xFFef4444), bg: const Color(0xFFef4444).withValues(alpha: 0.12))
                  else
                    _pill(icon: Icon(net.connType == 'cellular' ? Icons.signal_cellular_alt : Icons.wifi, size: 10, color: const Color(0xFFa1a1aa)), label: net.connType.toUpperCase(), color: const Color(0xFFa1a1aa), bg: Colors.white.withValues(alpha: 0.04)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    const Icon(Icons.arrow_downward, size: 11, color: Color(0xFF10b981)),
                    Text(' ${NetworkStatsService.formatBytes(net.downSpeed)}/s', style: const TextStyle(color: Color(0xFFd4d4d8), fontSize: 10, fontFamily: 'monospace')),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_upward, size: 11, color: Color(0xFF38bdf8)),
                    Text(' ${NetworkStatsService.formatBytes(net.upSpeed)}/s', style: const TextStyle(color: Color(0xFFd4d4d8), fontSize: 10, fontFamily: 'monospace')),
                  ],
                ),
                if (net.online)
                  Text('Month ${NetworkStatsService.formatBytes(net.totalMonth)} · WiFi ${NetworkStatsService.formatBytes(net.totalWifi)} · 4G ${NetworkStatsService.formatBytes(net.totalCellular)}',
                      style: const TextStyle(color: Color(0xFF71717a), fontSize: 8)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
