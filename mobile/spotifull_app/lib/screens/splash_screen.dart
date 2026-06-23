import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotifull_app/providers/auth_provider.dart';
import 'package:spotifull_app/screens/home_screen.dart';
import 'package:spotifull_app/screens/login_screen.dart';
import 'package:spotifull_app/screens/approval_screen.dart';
import 'package:spotifull_app/screens/onboarding_screen.dart';
import 'package:spotifull_app/screens/admin_screen.dart';

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
              context, MaterialPageRoute(builder: (_) => const LoginScreen()));
        } else if (!auth.isApproved) {
          Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const ApprovalScreen()));
        } else if (auth.needsOnboarding) {
          Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const OnboardingScreen()));
        } else if (auth.isAdmin) {
          Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const AdminScreen()));
        } else {
          Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const HomeScreen()));
        }
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF07110b),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_music, color: const Color(0xFF10b981), size: 72),
            const SizedBox(height: 24),
            Text('Spotifull', style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            )),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: Color(0xFF10b981)),
          ],
        ),
      ),
    );
  }
}
