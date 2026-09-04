import 'package:flutter/material.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotterfyTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Settings',
          style: TextStyle(
            color: SpotterfyTheme.text,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
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
              _settingsItem(Icons.graphic_eq, 'Equalizer', () {}),
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
            ],
          ),
        ),
      ),
    );
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
            Icon(
              icon,
              color: SpotterfyTheme.muted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right,
              color: SpotterfyTheme.muted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
