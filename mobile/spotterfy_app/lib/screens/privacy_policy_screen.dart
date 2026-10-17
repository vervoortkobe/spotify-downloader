import 'package:flutter/material.dart';

import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/app_chrome.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HideAppChrome(
      child: AppGradientScaffold(
        title: 'Privacy Policy',
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Data We Collect'),
              _textCard(
                'Spotterfy collects the following data to provide its services:\n\n'
                '• Account information (display name, email, profile photo)\n'
                '• Playlist data (names, track lists, cover art)\n'
                '• Download history\n'
                '• Network usage statistics\n'
                '• Device information for crash reporting',
              ),
              const SizedBox(height: 24),
              _sectionTitle('How We Use Your Data'),
              _textCard(
                'Your data is used to:\n\n'
                '• Authenticate your account\n'
                '• Sync your playlists across devices\n'
                '• Provide offline downloads\n'
                '• Improve app performance and fix bugs\n'
                '• Show relevant content recommendations',
              ),
              const SizedBox(height: 24),
              _sectionTitle('Data Storage'),
              _textCard(
                'All data is stored securely on Firebase servers. We do not sell your personal data to third parties. Your music preferences and playlist data are kept private and only visible to you.',
              ),
              const SizedBox(height: 24),
              _sectionTitle('Your Rights'),
              _textCard(
                'You have the right to:\n\n'
                '• Request a copy of your data\n'
                '• Delete your account and all associated data\n'
                '• Opt out of non-essential data collection\n'
                '• Contact us with any privacy concerns',
              ),
              const SizedBox(height: 24),
              _sectionTitle('Contact'),
              _textCard(
                'For any privacy-related questions or concerns, please use the Send Feedback option in Settings.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
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

  Widget _textCard(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: SpotterfyTheme.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: SpotterfyTheme.text,
        fontSize: 14,
        height: 1.5,
      ),
    ),
  );
}