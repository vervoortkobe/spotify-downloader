import 'package:flutter/material.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/app_chrome.dart';

class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HideAppChrome(
      child: AppGradientScaffold(
        title: 'Licenses',
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Open Source'),
              _textCard(
                'Spotterfy is built with open source software. Below are the licenses for the primary dependencies used in this app.',
              ),
              const SizedBox(height: 20),
              _licenseEntry('Flutter', 'BSD 3-Clause License'),
              _licenseEntry('Firebase', 'Apache License 2.0'),
              _licenseEntry('http', 'BSD-style license'),
              _licenseEntry('shared_preferences', 'BSD-style license'),
              _licenseEntry('url_launcher', 'Mozilla Public License 2.0'),
              _licenseEntry('share_plus', 'MIT License'),
              _licenseEntry('audios players', 'MIT License'),
              _licenseEntry('just_audio', 'MIT License'),
              const SizedBox(height: 24),
              _sectionTitle('Flutter Engine'),
              _textCard(
                'The Flutter engine is distributed under the BSD-style license. See the LICENSE file in the Flutter SDK for details.',
              ),
              const SizedBox(height: 24),
              _sectionTitle('Full License Text'),
              _textCard(
                'The complete license texts for all dependencies are available in the pubspec.lock file of the Spotterfy project repository.',
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

  Widget _licenseEntry(String dependency, String license) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          dependency,
          style: TextStyle(color: SpotterfyTheme.muted, fontSize: 14),
        ),
        Text(
          license,
          style: TextStyle(
            color: SpotterfyTheme.text,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
