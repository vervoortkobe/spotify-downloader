import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/screens/home_screen.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _urlController = TextEditingController();
  bool _loading = false;
  bool _skipped = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() => _loading = true);

    final auth = context.read<AuthProvider>();
    final playlistProv = context.read<PlaylistProvider>();

    final playlists = await ApiService.scrapeUserPlaylists(url);

    if (!mounted) return;

    if (playlists != null && playlists.isNotEmpty) {
      for (final p in playlists) {
        final playlistId = p['id'] as String;
        final playlistUrl = 'https://open.spotify.com/playlist/$playlistId';
        final remoteTrackCount = p['trackCount'] as int? ?? 0;
        final remoteName = p['name'] as String? ?? '';

        final existing = playlistProv.getPlaylistByUrl(playlistUrl);
        if (existing == null) {
          final scraped = await ApiService.scrapePlaylist(playlistUrl);
          if (scraped != null && auth.user != null) {
            final enriched = PlaylistModel(
              id: scraped.id,
              name: scraped.name,
              owner: p['owner'] as String? ?? '',
              coverUrl: scraped.tracks.isNotEmpty ? scraped.tracks.first.cover : '',
              tracks: scraped.tracks,
              creatorUid: auth.user!.uid,
              source: 'spotify',
              spotifyUrl: playlistUrl,
              isUsersOwn: true,
              lastTrackSync: DateTime.now(),
            );
            await playlistProv.savePlaylist(auth.user!.uid, enriched);
          }
        } else {
          final bool changed = (remoteTrackCount > 0 && existing.tracks.length != remoteTrackCount) ||
              (remoteName.isNotEmpty && existing.name != remoteName) ||
              existing.tracks.isEmpty;

          if (changed && auth.user != null) {
            final scraped = await ApiService.scrapePlaylist(playlistUrl);
            if (scraped != null && scraped.tracks.isNotEmpty) {
              existing.name = scraped.name;
              existing.tracks = scraped.tracks;
              if (scraped.tracks.isNotEmpty) {
                existing.coverUrl = scraped.tracks.first.cover;
              }
              existing.lastTrackSync = DateTime.now();
              await playlistProv.updatePlaylist(auth.user!.uid, existing);
            }
          }
        }
      }
      await auth.updateSpotifyProfileUrl(url);
    }

    if (!mounted) return;
    setState(() => _loading = false);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _skip() async {
    setState(() => _skipped = true);
    final auth = context.read<AuthProvider>();
    if (auth.user != null) {
      await auth.updateSpotifyProfileUrl('');
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07110b),
      body: Stack(
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: _OnboardingWavesPainter(),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset('assets/icon.svg', width: 72, height: 72),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome to Spotterfy',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Paste your Spotify profile URL to automatically\nimport your public playlists.',
                    style: TextStyle(
                      color: const Color(0xFFa1a1aa),
                      fontSize: 15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'https://open.spotify.com/user/...',
                      hintStyle: TextStyle(color: const Color(0xFFa1a1aa)),
                      filled: true,
                      fillColor: const Color(0xFF0a1410),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: const Color(0xFF1a3a2a)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: const Color(0xFF1a3a2a)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: SpotterfyTheme.primary),
                      ),
                      prefixIcon: Icon(Icons.link, color: SpotterfyTheme.primary),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SpotterfyTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? SizedBox(
                              width: 24, height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Import Playlists',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _skipped ? null : _skip,
                    child: Text(
                      'Skip for now',
                      style: TextStyle(
                        color: _skipped
                            ? const Color(0xFF3f3f46)
                            : const Color(0xFFa1a1aa),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingWavesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF10b981).withValues(alpha: 0.12),
          const Color(0xFF10b981).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, size.height * 0.65)
      ..quadraticBezierTo(
        size.width * 0.3, size.height * 0.55,
        size.width * 0.6, size.height * 0.6,
      )
      ..quadraticBezierTo(
        size.width * 0.8, size.height * 0.65,
        size.width, size.height * 0.55,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, paint);

    final paint2 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF065f46).withValues(alpha: 0.08),
          const Color(0xFF065f46).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path2 = Path()
      ..moveTo(0, size.height * 0.75)
      ..quadraticBezierTo(
        size.width * 0.25, size.height * 0.7,
        size.width * 0.5, size.height * 0.75,
      )
      ..quadraticBezierTo(
        size.width * 0.75, size.height * 0.8,
        size.width, size.height * 0.72,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
