import 'package:flutter/material.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/data_usage_screen.dart';
import 'package:spotterfy_app/screens/equalizer_screen.dart';
import 'package:spotterfy_app/screens/profile_settings_screen.dart';
import 'package:spotterfy_app/screens/storage_usage_screen.dart';
import 'package:spotterfy_app/screens/theme_screen.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/playback_settings_controller.dart';
import 'package:spotterfy_app/widgets/app_chrome.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _checkingUpdates = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return HideAppChrome(
      child: AppGradientScaffold(
        title: 'Settings',
        body: SingleChildScrollView(
          // The version block sits at the end of the column, and the mini player is
          // drawn by MainScreen *over* this scroll view rather than inside it. This
          // inset is what stops "Check for updates" landing underneath the mini
          // player and becoming untappable - it has to clear the mini player and
          // the nav bar below it, not just the column.
          padding: const EdgeInsets.only(bottom: 150),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile now leads to a sub-page that owns both fields, instead of
                // Profile / Name / Spotify URL being three unrelated rows here.
                _sectionLabel('Account'),
                _settingsItem(
                  Icons.person,
                  'Profile',
                  subtitle: auth.user?.displayName ?? 'Not set',
                  onTap: () => Navigator.push(
                    context,
                    swipeRoute(const ProfileSettingsScreen()),
                  ),
                ),

                const SizedBox(height: 24),
                _sectionLabel('Appearance'),
                _settingsItem(
                  Icons.brightness_6,
                  'Theme',
                  subtitle: 'Accent colour and OLED black',
                  onTap: () =>
                      Navigator.push(context, swipeRoute(const ThemeScreen())),
                ),

                const SizedBox(height: 24),
                _sectionLabel('Playback'),
                _settingsItem(
                  Icons.graphic_eq,
                  'Equalizer',
                  onTap: () {
                    Navigator.push(context, swipeRoute(EqualizerScreen()));
                  },
                ),
                const SizedBox(height: 8),
                _crossfadeRow(),

                const SizedBox(height: 24),
                _sectionLabel('Network'),
                _settingsItem(
                  Icons.data_usage,
                  'Data Usage',
                  onTap: () {
                    Navigator.push(context, swipeRoute(DataUsageScreen()));
                  },
                ),

                const SizedBox(height: 24),
                _sectionLabel('Storage'),
                _settingsItem(
                  Icons.storage,
                  'Storage usage',
                  onTap: () {
                    Navigator.push(
                      context,
                      swipeRoute(const StorageUsageScreen()),
                    );
                  },
                ),

                const SizedBox(height: 24),
                _sectionLabel('About'),
                _settingsItem(
                  Icons.info_outline,
                  'About Spotterfy',
                  onTap: () {},
                ),
                _settingsItem(
                  Icons.privacy_tip,
                  'Privacy Policy',
                  onTap: () {},
                ),
                _settingsItem(Icons.feedback, 'Send Feedback', onTap: () {}),
                const SizedBox(height: 20),

                // Kept last, but with the scroll inset above it so it clears the
                // mini player instead of hiding behind it.
                _versionRow(context),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Small uppercase-ish heading above a group of rows.
  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        color: SpotterfyTheme.muted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

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
          Icon(Icons.info_outline, color: SpotterfyTheme.muted, size: 20),
          SizedBox(width: 12),
          Text(
            '${ApiService.appVersionLabel} ${ApiService.appVersion}',
            style: TextStyle(
              color: SpotterfyTheme.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          Spacer(),
          _checkingUpdates
              ? SizedBox(
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

  /// Crossfade length between songs, in seconds (0 = off).
  ///
  /// Applied when a track plays out into the next one; manual skips stay
  /// instant. The value is read by PlayerProvider when a fade is scheduled,
  /// so a change takes effect on the next transition.
  Widget _crossfadeRow() {
    final settings = context.watch<PlaybackSettingsController>();
    final seconds = settings.crossfadeSeconds;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: SpotterfyTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.swap_horiz, color: SpotterfyTheme.muted, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Song transition',
                      style: TextStyle(
                        color: SpotterfyTheme.text,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      seconds == 0
                          ? 'Off'
                          : '$seconds second${seconds == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: SpotterfyTheme.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: seconds.toDouble(),
              min: 0,
              max: PlaybackSettingsController.maxSeconds.toDouble(),
              divisions: PlaybackSettingsController.maxSeconds,
              label: seconds == 0 ? 'Off' : '$seconds s',
              activeColor: SpotterfyTheme.primary,
              onChanged: (v) => settings.setCrossfadeSeconds(v.round()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsItem(
    IconData icon,
    String title, {
    required VoidCallback onTap,
    String? subtitle,
  }) {
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(color: SpotterfyTheme.text, fontSize: 16),
                  ),
                  // Current value, so the row doubles as read-only state. The
                  // title stays on one line and the value truncates beneath it
                  // rather than squeezing both against the chevron.
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: SpotterfyTheme.muted,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: SpotterfyTheme.muted, size: 20),
          ],
        ),
      ),
    );
  }
}
