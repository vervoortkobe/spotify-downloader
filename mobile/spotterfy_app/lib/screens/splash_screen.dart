import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/social_provider.dart';
import 'package:spotterfy_app/screens/login_screen.dart';
import 'package:spotterfy_app/screens/onboarding_screen.dart';
import 'package:spotterfy_app/screens/admin_screen.dart';
import 'package:spotterfy_app/screens/main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _precached = false;
  bool _navigated = false;

  late final AnimationController _intro;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  late final Animation<double> _textSlide;
  late final Animation<double> _glowPulse;

  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _green = Color(0xFF1DB954);

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();

    _logoScale = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0, 0.7, curve: Curves.easeOutBack),
    );
    _logoFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0, 0.45, curve: Curves.easeOut),
    );
    _textSlide = Tween<double>(begin: 14, end: 0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.25, 0.75, curve: Curves.easeOutCubic),
      ),
    );
    _textFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.3, 0.7, curve: Curves.easeOut),
    );
    // Independent slow loop for the glow so it keeps breathing after the intro.
    _glowPulse = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _intro, curve: Curves.linear));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precached = true;
      // Precache logo off critical path, don't block first frame
      precacheImage(const AssetImage('logo/spotterfy_black_bg.png'), context);
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  void _maybeNavigate(AuthProvider auth) {
    if (_navigated || auth.isLoading) return;
    _navigated = true;
    // Friend/notification/message streams only start once we know who is
    // signed in, otherwise they'd subscribe as a null uid and silently do
    // nothing.
    if (auth.isLoggedIn && mounted) {
      context.read<SocialProvider>().syncUid(auth.user?.uid);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Widget target;
      if (!auth.isLoggedIn) {
        target = const LoginScreen();
      } else if (auth.needsOnboarding) {
        target = const OnboardingScreen();
      } else if (auth.isAdmin) {
        target = const AdminScreen();
      } else {
        target = const MainScreen();
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => target),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    _maybeNavigate(auth);

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Soft green aurora behind the logo.
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _glowPulse,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(
                  (_glowPulse.value < 0.5
                      ? _glowPulse.value * 2
                      : (1 - _glowPulse.value) * 2),
                );
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.35),
                      radius: 1.0,
                      colors: [
                        _green.withValues(alpha: 0.20 + 0.10 * t),
                        _green.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Faint vertical sheen for depth.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x14000000),
                  Color(0x00000000),
                  Color(0x26000000),
                ],
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: Container(
                      width: 128,
                      height: 128,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(34),
                        border: Border.all(
                          color: _green.withValues(alpha: 0.85),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _green.withValues(alpha: 0.30),
                            blurRadius: 34,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Image.asset(
                          'logo/spotterfy_black_bg.png',
                          width: 128,
                          height: 128,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                FadeTransition(
                  opacity: _textFade,
                  child: Transform.translate(
                    offset: Offset(0, _textSlide.value),
                    child: Column(
                      children: [
                        const Text(
                          'Spotterfy',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 4,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Music, downloaded',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 12,
                            letterSpacing: 2.2,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                // Slim determinate-looking bar reads calmer than a spinner.
                FadeTransition(
                  opacity: _textFade,
                  child: SizedBox(
                    width: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        backgroundColor: Colors.white.withValues(alpha: 0.10),
                        valueColor: const AlwaysStoppedAnimation(_green),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
