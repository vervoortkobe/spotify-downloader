import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'services/firebase_service.dart' as fb;
import 'providers/auth_provider.dart';
import 'providers/playlist_provider.dart';
import 'providers/equalizer_provider.dart';
import 'providers/player_provider.dart';
import 'providers/jam_provider.dart';
import 'providers/admin_provider.dart';
import 'providers/status_provider.dart';
import 'services/network_stats_service.dart';
import 'screens/splash_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await fb.FirebaseService.initialize();
  runApp(const SpotterfyApp());
}

class SpotterfyApp extends StatelessWidget {
  const SpotterfyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(), lazy: true),
        ChangeNotifierProvider(create: (_) => PlaylistProvider(), lazy: true),
        ChangeNotifierProvider(create: (_) => EqualizerProvider(), lazy: true),
        ChangeNotifierProvider(create: (_) => PlayerProvider(), lazy: true),
        ChangeNotifierProvider(create: (_) => JamProvider(), lazy: true),
        ChangeNotifierProvider(create: (_) => AdminProvider(), lazy: true),
        ChangeNotifierProvider(create: (_) => StatusProvider(), lazy: true),
        ChangeNotifierProvider(create: (_) => NetworkStatsService(), lazy: true),
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
