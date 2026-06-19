import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'services/firebase_service.dart' as fb;
import 'providers/auth_provider.dart';
import 'providers/playlist_provider.dart';
import 'providers/player_provider.dart';
import 'providers/jam_provider.dart';
import 'providers/admin_provider.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await fb.FirebaseService.initialize();
  runApp(const SpotifullApp());
}

class SpotifullApp extends StatelessWidget {
  const SpotifullApp({super.key});

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
        title: 'Spotifull',
        debugShowCheckedModeBanner: false,
        theme: SpotifullTheme.darkTheme,
        home: const SplashScreen(),
      ),
    );
  }
}
