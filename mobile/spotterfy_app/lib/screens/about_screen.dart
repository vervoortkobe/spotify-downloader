import 'package:flutter/material.dart';

import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/app_chrome.dart';
import 'package:spotterfy_app/services/api_service.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HideAppChrome(
      child: AppGradientScaffold(
        title: 'About Spotterfy',
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('App'),
              _infoCard([
                _infoRow('App name', 'Spotterfy'),
                _infoRow('Version', '${ApiService.appVersionLabel} ${ApiService.appVersion}'),
                _infoRow('Platform', 'Android'),
              ]),
              const SizedBox(height: 24),
              _sectionTitle('What is Spotterfy?'),
              _textCard(
                'Spotterfy is a free music streaming and download app that lets you listen to your favorite songs with no ads. Save playlists, download tracks for offline listening, and enjoy your music how it\'s supposed to be — for free.',
              ),
              const SizedBox(height: 24),
              _sectionTitle('Features'),
              _textCard(
                '• Ad-free music streaming\n'
                '• Playlist import from Spotify, YouTube, and SoundCloud\n'
                '• Offline downloads\n'
                '• Equalizer support\n'
                '• Crossfade between songs\n'
                '• OLED dark theme support\n'
                '• Multiple accent colors',
              ),
              const SizedBox(height: 24),
              _sectionTitle('Tech'),
              _textCard(
                'Built with Flutter and powered by Firebase. Spotterfy uses a custom backend for playlist scraping and audio streaming.',
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

  Widget _infoCard(List<Widget> children) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: SpotterfyTheme.surface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(children: children),
  );

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: SpotterfyTheme.muted, fontSize: 14),
        ),
        Text(
          value,
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