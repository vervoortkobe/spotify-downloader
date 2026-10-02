import 'package:flutter/material.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/data_usage_screen.dart';
import 'package:spotterfy_app/screens/equalizer_screen.dart';
import 'package:spotterfy_app/screens/profile_screen.dart';
import 'package:spotterfy_app/screens/storage_usage_screen.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';

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
    final name = auth.user?.displayName ?? '';
    final spotifyUrl = auth.user?.spotifyProfileUrl ?? '';

    return AppGradientScaffold(
      title: 'Settings',
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile section. Name and Spotify URL used to sit in their own
              // loose rows under "Account", split from the Profile entry they
              // actually describe; they are grouped here so everything about
              // who you are reads as one block, each row showing its current
              // value instead of just a chevron.
              Text(
                'Profile',
                style: TextStyle(
                  color: SpotterfyTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _settingsItem(
                Icons.person,
                'Profile',
                subtitle: name.isEmpty ? 'Not set' : name,
                onTap: () =>
                    Navigator.push(context, swipeRoute(const ProfileScreen())),
              ),
              _settingsItem(
                Icons.edit,
                'Name',
                subtitle: name.isEmpty ? 'Not set' : name,
                onTap: _showNameDialog,
              ),
              _settingsItem(
                Icons.link,
                'Spotify URL',
                subtitle: spotifyUrl.isEmpty ? 'Not linked' : spotifyUrl,
                onTap: _showSpotifyUrlDialog,
              ),
              _settingsItem(Icons.notifications, 'Notifications', onTap: () {}),
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
              _settingsItem(Icons.brightness_6, 'Theme', onTap: () {}),
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
              _settingsItem(Icons.audiotrack, 'Audio Quality', onTap: () {}),
              _settingsItem(
                Icons.graphic_eq,
                'Equalizer',
                onTap: () {
                  Navigator.push(context, swipeRoute(const EqualizerScreen()));
                },
              ),
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
              _settingsItem(
                Icons.data_usage,
                'Data Usage',
                onTap: () {
                  Navigator.push(context, swipeRoute(const DataUsageScreen()));
                },
              ),
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
              _settingsItem(
                Icons.info_outline,
                'About Spotterfy',
                onTap: () {},
              ),
              _settingsItem(Icons.privacy_tip, 'Privacy Policy', onTap: () {}),
              _settingsItem(Icons.feedback, 'Send Feedback', onTap: () {}),
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

  /// Shows a dialog to edit the display name.
  Future<void> _showNameDialog() async {
    final auth = context.read<AuthProvider>();
    final currentName = auth.user?.displayName ?? '';
    final controller = TextEditingController(text: currentName);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotterfyTheme.surface,
        title: const Text('Edit display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Display name',
            hintStyle: TextStyle(color: SpotterfyTheme.muted),
            filled: true,
            fillColor: const Color(0xFF0a1410),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFF1a3a2a)),
            ),
          ),
          maxLines: 1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: SpotterfyTheme.muted),
            ),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty && name != currentName) {
                auth.updateDisplayName(name);
                if (!context.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Display name updated')),
                );
              } else {
                if (!context.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No changes made')),
                );
              }
            },
            child: const Text(
              'Save',
              style: TextStyle(color: SpotterfyTheme.primary),
            ),
          ),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  /// Shows a dialog to edit the Spotify profile URL.
  Future<void> _showSpotifyUrlDialog() async {
    final auth = context.read<AuthProvider>();
    final currentUrl = auth.user?.spotifyProfileUrl ?? '';
    final controller = TextEditingController(text: currentUrl);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotterfyTheme.surface,
        title: const Text('Edit Spotify URL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Spotify profile URL',
            hintStyle: TextStyle(color: SpotterfyTheme.muted),
            filled: true,
            fillColor: const Color(0xFF0a1410),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFF1a3a2a)),
            ),
          ),
          maxLines: 1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: SpotterfyTheme.muted),
            ),
          ),
          TextButton(
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty && url != currentUrl) {
                auth.updateSpotifyProfileUrl(url);
                if (!context.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Spotify URL updated')),
                );
              } else {
                if (!context.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No changes made')),
                );
              }
            },
            child: const Text(
              'Save',
              style: TextStyle(color: SpotterfyTheme.primary),
            ),
          ),
        ],
      ),
    );
    if (mounted) setState(() {});
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
