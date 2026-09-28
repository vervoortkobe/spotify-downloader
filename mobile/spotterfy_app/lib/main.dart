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
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Spotterfy',
        debugShowCheckedModeBanner: false,
        theme: SpotterfyTheme.darkTheme,
        home: const SplashScreen(),
      ),
    );
  }
}
