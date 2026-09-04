import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/screens/login_screen.dart';
import 'package:spotterfy_app/screens/approval_screen.dart';
import 'package:spotterfy_app/screens/onboarding_screen.dart';
import 'package:spotterfy_app/screens/admin_screen.dart';
import 'package:spotterfy_app/screens/main_screen.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (!auth.isLoggedIn) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        } else if (!auth.isApproved) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ApprovalScreen()),
          );
        } else if (auth.needsOnboarding) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const OnboardingScreen()),
          );
        } else if (auth.isAdmin) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AdminScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MainScreen()),
          );
        }
      });
    }

    return Scaffold(
      backgroundColor: SpotterfyTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('logo/spotterfy_black_bg.png', width: 120, height: 120),
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
