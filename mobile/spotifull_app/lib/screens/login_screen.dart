import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:spotifull_app/providers/auth_provider.dart';
import 'package:spotifull_app/screens/home_screen.dart';
import 'package:spotifull_app/screens/approval_screen.dart';
import 'package:spotifull_app/screens/admin_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // Already logged in — redirect
    if (!auth.isLoading && auth.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
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
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF07110b),
      body: Stack(
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: WavesPainter(),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/icon.svg',
                    width: 88,
                    height: 88,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Spotifull',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Download & stream your favorite music',
                    style: TextStyle(
                      color: const Color(0xFFa1a1aa),
                      fontSize: 16,
                    ),
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
        ],
      ),
    );
  }
}

class WavesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint1 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF10b981).withValues(alpha: 0.15),
          const Color(0xFF10b981).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path1 = Path()
      ..moveTo(0, size.height * 0.6)
      ..quadraticBezierTo(
        size.width * 0.25, size.height * 0.5,
        size.width * 0.5, size.height * 0.55,
      )
      ..quadraticBezierTo(
        size.width * 0.75, size.height * 0.6,
        size.width, size.height * 0.5,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path1, paint1);

    final paint2 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF22c55e).withValues(alpha: 0.1),
          const Color(0xFF22c55e).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path2 = Path()
      ..moveTo(0, size.height * 0.45)
      ..quadraticBezierTo(
        size.width * 0.3, size.height * 0.35,
        size.width * 0.6, size.height * 0.4,
      )
      ..quadraticBezierTo(
        size.width * 0.8, size.height * 0.45,
        size.width, size.height * 0.35,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path2, paint2);

    final paint3 = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF065f46).withValues(alpha: 0.08),
          const Color(0xFF065f46).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path3 = Path()
      ..moveTo(0, size.height * 0.7)
      ..quadraticBezierTo(
        size.width * 0.2, size.height * 0.65,
        size.width * 0.4, size.height * 0.7,
      )
      ..quadraticBezierTo(
        size.width * 0.6, size.height * 0.75,
        size.width * 0.8, size.height * 0.7,
      )
      ..quadraticBezierTo(
        size.width * 0.9, size.height * 0.65,
        size.width, size.height * 0.7,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path3, paint3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
