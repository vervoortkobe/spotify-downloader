import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/services/network_stats_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// Slim black banner under the search bar announcing connectivity changes.
/// Persistent while offline, auto-hides a few seconds after reconnecting.
class ConnectivityBanner extends StatelessWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final net = context.watch<NetworkStatsService>();
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: net.bannerVisible
          ? Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    net.bannerIsOffline
                        ? Icons.signal_wifi_off
                        : (net.isCellular ? Icons.signal_cellular_alt : Icons.wifi),
                    size: 14,
                    color: net.bannerIsOffline
                        ? const Color(0xFFef4444)
                        : (net.isCellular ? const Color(0xFF38bdf8) : SpotterfyTheme.primary),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      net.bannerMessage,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox(width: double.infinity, height: 0),
    );
  }
}
