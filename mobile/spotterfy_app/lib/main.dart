import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'services/firebase_service.dart' as fb;
import 'services/notification_service.dart';
import 'providers/auth_provider.dart';
import 'providers/playlist_provider.dart';
import 'providers/player_provider.dart';
import 'providers/jam_provider.dart';
import 'providers/admin_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/player_screen.dart';
import 'widgets/mini_player.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await fb.FirebaseService.initialize();
  await NotificationService().initialize();
  NotificationService().onNotificationTap = () {
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  };
  runApp(const SpotterfyApp());
}

class SpotterfyApp extends StatelessWidget {
  const SpotterfyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PlaylistProvider()),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider(create: (_) => JamProvider()),
        ChangeNotifierProvider(create: (_) => AdminProvider()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Spotterfy',
        debugShowCheckedModeBanner: false,
        theme: SpotterfyTheme.darkTheme,
        home: const SplashScreen(),
        builder: (context, child) {
          return Stack(
            children: [
              child!,
              Consumer<PlayerProvider>(
                builder: (context, player, _) {
                  if (player.currentTrack == null) {
                    return const SizedBox.shrink();
                  }
                  return Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const MiniPlayer(),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
