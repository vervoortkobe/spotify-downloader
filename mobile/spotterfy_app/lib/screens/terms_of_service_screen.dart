import 'package:flutter/material.dart';

import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/app_chrome.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HideAppChrome(
      child: AppGradientScaffold(
        title: 'Terms of Service',
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Acceptance of Terms'),
              _textCard(
                'By accessing or using Spotterfy, you agree to be bound by these Terms of Service. If you do not agree with any part of these terms, please do not use the app.',
              ),
              const SizedBox(height: 24),
              _sectionTitle('Use License'),
              _textCard(
                'Permission is granted to temporarily download and use Spotterfy for personal, non-commercial transitory viewing only. This is the grant of a license, not a transfer of title, and under this license you may not:\n\n'
                '• Modify or copy the materials\n'
                '• Use the materials for any commercial purpose\n'
                '• Attempt to decompile or reverse engineer any software\n'
                '• Remove any copyright or other proprietary notations\n'
                '• Transfer the materials to another person',
              ),
              const SizedBox(height: 24),
              _sectionTitle('Disclaimer'),
              _textCard(
                'The materials on Spotterfy are provided on an "as is" basis. Spotterfy makes no warranties, expressed or implied, and hereby disclaims and negates all other warranties including, without limitation, implied warranties or conditions of merchantability, fitness for a particular purpose, or non-infringement of intellectual property or other violation of rights.',
              ),
              const SizedBox(height: 24),
              _sectionTitle('Limitations'),
              _textCard(
                'In no event shall Spotterfy or its suppliers be liable for any damages (including, without limitation, damages for loss of data or profit, or due to business interruption) arising out of the use or inability to use the materials on Spotterfy, even if Spotterfy or a Spotterfy authorized representative has been notified orally or in writing of the possibility of such damage.',
              ),
              const SizedBox(height: 24),
              _sectionTitle('Governing Law'),
              _textCard(
                'These terms and conditions are governed by and construed in accordance with the laws of the applicable jurisdiction and you irrevocably submit to the exclusive jurisdiction of the courts in that jurisdiction.',
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
