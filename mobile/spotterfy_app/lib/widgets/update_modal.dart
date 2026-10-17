import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// Shows an update-available modal with Dismiss and Download buttons.
///
/// `data` must contain at least `version`, `label`, `notes` and `url` as
/// returned by [ApiService.checkForUpdates].
///
/// Returns `true` if the user tapped Download, `false` if dismissed.
Future<bool> showUpdateModal(BuildContext context, Map<String, String> data) async {
  final url = data['url'] ?? '';
  final label = data['label'] ?? '';
  final version = data['version'] ?? '';
  final notes = data['notes'] ?? '';

  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      backgroundColor: SpotterfyTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Update available',
        style: TextStyle(color: SpotterfyTheme.text, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${label.isEmpty ? '' : '$label '}$version',
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              notes.isEmpty ? 'A new version of Spotterfy is available.' : notes,
              style: TextStyle(color: SpotterfyTheme.muted, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            'Dismiss',
            style: TextStyle(color: SpotterfyTheme.muted, fontSize: 14),
          ),
        ),
        if (url.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Download',
              style: TextStyle(color: SpotterfyTheme.primary, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    ),
  );

  if (confirmed == true && url.isNotEmpty) {
    await launchUrl(Uri.parse(url));
  }

  return confirmed == true;
}
