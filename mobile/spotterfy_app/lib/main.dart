import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/playlist_provider.dart';
import 'providers/equalizer_provider.dart';
import 'providers/player_provider.dart';
import 'providers/jam_provider.dart';
import 'providers/admin_provider.dart';
import 'providers/download_provider.dart';
import 'providers/social_provider.dart';
import 'providers/status_provider.dart';
import 'providers/theme_controller.dart';
import 'providers/playback_settings_controller.dart';
import 'services/network_stats_service.dart';
import 'screens/splash_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase is deliberately NOT awaited here. Awaiting before runApp meant the
  // first Flutter frame could not be drawn until initialisation finished, so
  // launch showed a stalled native splash and then appeared to hang.
  // The splash now owns initialisation, which also gives us somewhere to offer
  // a retry if it fails.
  runApp(const SpotterfyApp());
}

class SpotterfyApp extends StatelessWidget {
  const SpotterfyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(), lazy: true),
        // Also eager: it binds the Android Auto library loader, which has to be
        // present before the car asks for the browse tree.
        ChangeNotifierProvider(create: (_) => PlaylistProvider(), lazy: false),
        ChangeNotifierProvider(create: (_) => EqualizerProvider(), lazy: true),
        // Eager: this provider owns the audio handler, and Android Auto can bind
        // to the media browser service in a cold process where no screen has read
        // any provider yet. Lazy left nothing to answer the browse tree, so the
        // car showed a full-screen error instead of the library.
        ChangeNotifierProvider(create: (_) => PlayerProvider(), lazy: false),
        ChangeNotifierProvider(create: (_) => JamProvider(), lazy: true),
        ChangeNotifierProvider(create: (_) => AdminProvider(), lazy: true),
        ChangeNotifierProvider(
          create: (_) => DownloadProvider()..load(),
          lazy: true,
        ),
        // Social state follows the signed-in uid; the splash screen starts it
        // once auth is resolved.
        ChangeNotifierProvider(create: (_) => SocialProvider(), lazy: true),
        ChangeNotifierProvider(create: (_) => StatusProvider(), lazy: true),
        ChangeNotifierProvider(
          create: (_) => NetworkStatsService(),
          lazy: true,
        ),
      ],
      child: Builder(
        builder: (context) {
          // The palette is applied once before the first frame, then re-applied
          // and repainted whenever ThemeController fires. Rebuilding here (below
          // MaterialApp) is what makes the change reach every screen: the
          // colours in SpotterfyTheme are plain statics, so a widget only picks
          // up a new one when its build() runs again.
          final theme = ThemeController.instance;
          final playbackSettings = PlaybackSettingsController.instance;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!theme.isLoaded) theme.load();
            if (!playbackSettings.isLoaded) playbackSettings.load();
          });
          return ListenableBuilder(
            listenable: theme,
            builder: (context, _) => MaterialApp(
              navigatorKey: navigatorKey,
              title: 'Spotterfy',
              debugShowCheckedModeBanner: false,
              theme: SpotterfyTheme.darkTheme,
              home: const _PlaybackPresenceSync(child: SplashScreen()),
            ),
          );
        },
      ),
    );
  }
}

/// Mirrors the current player selection to the signed-in user's Firestore
/// presence record. It watches provider notifications but writes only when the
/// selected playing track changes, never on position ticks.
class _PlaybackPresenceSync extends StatefulWidget {
  final Widget child;

  const _PlaybackPresenceSync({required this.child});

  @override
  State<_PlaybackPresenceSync> createState() => _PlaybackPresenceSyncState();
}

class _PlaybackPresenceSyncState extends State<_PlaybackPresenceSync> {
  AuthProvider? _auth;
  PlayerProvider? _player;
  String? _lastSignature;
  Timer? _retryTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    final player = context.read<PlayerProvider>();
    if (_auth != auth || _player != player) {
      _auth?.removeListener(_sync);
      _player?.removeListener(_sync);
      _auth = auth;
      _player = player;
      auth.addListener(_sync);
      player.addListener(_sync);
      _lastSignature = null;
      _sync();
    }
  }

  void _sync() {
    final auth = _auth;
    final player = _player;
    final user = auth?.user;
    if (auth == null || player == null || user == null) return;

    final track = player.isPlaying ? player.currentTrack : null;
    final signature = '${user.uid}:${track?.id ?? ''}';
    if (signature == _lastSignature) return;
    _retryTimer?.cancel();
    _lastSignature = signature;
    unawaited(
      auth
          .updateListeningStatus(
            track?.id,
            trackTitle: track?.title ?? '',
            trackArtist: track?.artists ?? '',
            trackArtwork: track?.artwork ?? '',
          )
          .catchError((Object error) {
            debugPrint('[Presence] now-playing update failed: $error');
            _lastSignature = null;
            _retryTimer?.cancel();
            _retryTimer = Timer(const Duration(seconds: 15), _sync);
          }),
    );
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _auth?.removeListener(_sync);
    _player?.removeListener(_sync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
