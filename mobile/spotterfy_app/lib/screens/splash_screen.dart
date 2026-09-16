import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/screens/login_screen.dart';
import 'package:spotterfy_app/screens/approval_screen.dart';
import 'package:spotterfy_app/screens/onboarding_screen.dart';
import 'package:spotterfy_app/screens/admin_screen.dart';
import 'package:spotterfy_app/screens/main_screen.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _precached = false;
  bool _navigated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precached = true;
      // Precache logo off critical path, don't block first frame
      precacheImage(const AssetImage('logo/spotterfy_black_bg.png'), context);
    }
  }

  void _maybeNavigate(AuthProvider auth) {
    if (_navigated || auth.isLoading) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Widget target;
      if (!auth.isLoggedIn) {
        target = const LoginScreen();
      } else if (!auth.isApproved) {
        target = const ApprovalScreen();
      } else if (auth.needsOnboarding) {
        target = const OnboardingScreen();
      } else if (auth.isAdmin) {
        target = const AdminScreen();
      } else {
        target = const MainScreen();
      }
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => target));
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    _maybeNavigate(auth);

    return Scaffold(
      backgroundColor: SpotterfyTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: const Color(0xFF10b981), width: 3),
                boxShadow: [BoxShadow(color: const Color(0xFF10b981).withValues(alpha: 0.35), blurRadius: 20, spreadRadius: 1)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset('logo/spotterfy_black_bg.png', width: 120, height: 120, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Spotterfy',
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: Color(0xFF10b981)),
          ],
        ),
      ),
    );
  }
}
