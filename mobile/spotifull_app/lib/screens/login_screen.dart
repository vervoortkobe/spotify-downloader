import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotifull_app/providers/auth_provider.dart';
import 'package:spotifull_app/screens/home_screen.dart';
import 'package:spotifull_app/screens/approval_screen.dart';
import 'package:spotifull_app/screens/admin_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07110b),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.library_music, color: const Color(0xFF10b981), size: 80),
              const SizedBox(height: 16),
              Text('Spotifull', style: TextStyle(
                color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold,
              )),
              const SizedBox(height: 8),
              Text('Download & stream your favorite music',
                style: TextStyle(color: const Color(0xFFa1a1aa), fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              Consumer<AuthProvider>(
                builder: (context, auth, _) {
                  return SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: auth.isSigningIn ? null : () async {
                        final success = await auth.signInWithGoogle();
                        if (!context.mounted) return;
                        if (success) {
                          if (!auth.isApproved) {
                            Navigator.pushReplacement(
                              context, MaterialPageRoute(builder: (_) => const ApprovalScreen()));
                          } else if (auth.isAdmin) {
                            Navigator.pushReplacement(
                              context, MaterialPageRoute(builder: (_) => const AdminScreen()));
                          } else {
                            Navigator.pushReplacement(
                              context, MaterialPageRoute(builder: (_) => const HomeScreen()));
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10b981),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: auth.isSigningIn
                          ? SizedBox(width: 24, height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.login, size: 20),
                                SizedBox(width: 12),
                                Text('Sign in with Google',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                              ],
                            ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
