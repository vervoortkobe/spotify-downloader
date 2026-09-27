import 'package:flutter/material.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/data_usage_screen.dart';
import 'package:spotterfy_app/screens/equalizer_screen.dart';
import 'package:spotterfy_app/screens/storage_usage_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _checkingUpdates = false;

  @override
  Widget build(BuildContext context) {
    return AppGradientScaffold(
      title: 'Settings',
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Account section
              Text(
                'Account',
                style: TextStyle(
                  color: SpotterfyTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _settingsItem(Icons.person, 'Profile', () {}),
              _settingsItem(Icons.notifications, 'Notifications', () {}),
              const SizedBox(height: 24),

              // Appearance section
              Text(
                'Appearance',
                style: TextStyle(
                  color: SpotterfyTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _settingsItem(Icons.brightness_6, 'Theme', () {}),
              const SizedBox(height: 24),

              // Playback section
              Text(
                'Playback',
                style: TextStyle(
                  color: SpotterfyTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _settingsItem(Icons.audiotrack, 'Audio Quality', () {}),
              _settingsItem(Icons.graphic_eq, 'Equalizer', () {
                Navigator.push(context, swipeRoute(const EqualizerScreen()));
              }),
              const SizedBox(height: 24),

              // Network section
              Text(
                'Network',
                style: TextStyle(
                  color: SpotterfyTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _settingsItem(Icons.data_usage, 'Data Usage', () {
                Navigator.push(context, swipeRoute(const DataUsageScreen()));
              }),
              const SizedBox(height: 24),

              // Storage section
              Text(
                'Storage',
                style: TextStyle(
                  color: SpotterfyTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _settingsItem(Icons.storage, 'Storage usage', () {
                Navigator.push(context, swipeRoute(const StorageUsageScreen()));
              }),
              const SizedBox(height: 24),

              // About section
              Text(
                'About',
                style: TextStyle(
                  color: SpotterfyTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _settingsItem(Icons.info_outline, 'About Spotterfy', () {}),
              _settingsItem(Icons.privacy_tip, 'Privacy Policy', () {}),
              _settingsItem(Icons.feedback, 'Send Feedback', () {}),
              const SizedBox(height: 24),

              // Version + update check, pinned to the bottom of the page.
              _versionRow(context),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// App version with a "Check for updates" action beside it.
  Widget _versionRow(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      decoration: BoxDecoration(
        color: SpotterfyTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: SpotterfyTheme.muted, size: 20),
          const SizedBox(width: 12),
          Text(
            '${ApiService.appVersionLabel} ${ApiService.appVersion}',
            style: const TextStyle(
              color: SpotterfyTheme.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _checkingUpdates
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: SpotterfyTheme.primary,
                  ),
                )
              : TextButton.icon(
                  onPressed: _checkForUpdates,
                  icon: const Icon(Icons.system_update, size: 18),
                  label: const Text('Check for updates'),
                  style: TextButton.styleFrom(
                    foregroundColor: SpotterfyTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
        ],
      ),
    );
  }

  /// Compares this build against the server's published version.
  ///
  /// The three outcomes are reported distinctly: an update exists, we're
  /// current, or the check itself failed (offline) - the last one must not be
  /// shown as "you're up to date".
  Future<void> _checkForUpdates() async {
    if (_checkingUpdates) return;
    setState(() => _checkingUpdates = true);
    final latest = await ApiService.checkForUpdates();
    if (!mounted) return;
    setState(() => _checkingUpdates = false);

    final remote = latest?['version']?.trim() ?? '';
    if (latest == null || remote.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not check for updates')),
      );
      return;
    }
    if (_isNewer(remote, ApiService.appVersion)) {
      final label = latest['label'] ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Update available: ${label.isEmpty ? '' : '$label '}$remote',
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Spotterfy is up to date')));
  }

  /// Dotted-version comparison, so 1.0.10 correctly beats 1.0.9.
  static bool _isNewer(String remote, String local) {
    List<int> parse(String v) => v
        .split(RegExp(r'[^0-9]+'))
        .where((p) => p.isNotEmpty)
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final a = parse(remote);
    final b = parse(local);
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  Widget _settingsItem(IconData icon, String title, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: SpotterfyTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: SpotterfyTheme.muted, size: 20),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(color: SpotterfyTheme.text, fontSize: 16),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: SpotterfyTheme.muted, size: 20),
          ],
        ),
      ),
    );
  }
}
