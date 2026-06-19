import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotifull_app/providers/auth_provider.dart';
import 'package:spotifull_app/screens/home_screen.dart';
import 'package:spotifull_app/screens/login_screen.dart';
import 'package:spotifull_app/screens/approval_screen.dart';
import 'package:spotifull_app/screens/admin_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
    } else if (!auth.isApproved) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ApprovalScreen()));
    } else if (auth.isAdmin) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminScreen()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
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
            CircularProgressIndicator(color: const Color(0xFF10b981)),
          ],
        ),
      ),
    );
  }
}
