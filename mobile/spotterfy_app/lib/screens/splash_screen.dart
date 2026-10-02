import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/social_provider.dart';
import 'package:spotterfy_app/screens/login_screen.dart';
import 'package:spotterfy_app/screens/onboarding_screen.dart';
import 'package:spotterfy_app/screens/admin_screen.dart';
import 'package:spotterfy_app/screens/main_screen.dart';
import 'package:spotterfy_app/services/firebase_service.dart' as fb;
import 'package:spotterfy_app/widgets/refresh_button.dart';
import 'package:spotterfy_app/services/audio_handler.dart';

/// Launch screen, and the app's bootstrap gate.
///
/// Firebase is initialised here rather than in `main()` so the first Flutter
/// frame paints immediately. The splash is deliberately cheap to draw: the
/// looping gradients are static layers animated by opacity, and the progress bar
/// is determinate so it stops invalidating frames once done.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

enum _Phase { starting, ready, failed }

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  _Phase _phase = _Phase.starting;
  Object? _error;

  /// Determinate progress: 0.06 while Firebase boots, 0.72 once it is up, and
  /// it fills the rest as we navigate away.
  double _progress = 0.06;

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
      duration: const Duration(milliseconds: 900),
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
    // Slow breath for the aurora. It only runs for the intro, so the screen
    // goes completely idle once booted instead of repainting forever.
    _glowPulse = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _intro, curve: Curves.linear));

    _boot();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Precache the logo so the first paint doesn't wait on a PNG decode.
    precacheImage(const AssetImage('logo/spotterfy_black_bg.png'), context);
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// Initialises Firebase, then hands off to the auth gate.
  ///
  /// Safe to call again from the refresh button. Firebase's own
  /// `initializeApp` is a no-op once the default app exists, so a retry either
  /// succeeds immediately or fails fast and stays on the error state.
  Future<void> _boot() async {
    if (mounted) {
      setState(() {
        _phase = _Phase.starting;
        _error = null;
        _progress = 0.06;
      });
    }
    try {
      await fb.FirebaseService.initialize();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _phase = _Phase.failed;
      });
      return;
    }
    // Connect the media service during boot, not on first playback.
    //
    // Android Auto wakes the app by binding to the MediaBrowserService, which
    // starts the Flutter engine but does NOT start playback. If the audio
    // service were only initialised lazily from play(), the native side would
    // still have no listener when the car asked for the browse tree, and
    // `onLoadChildren` would answer with an empty list - an empty media app.
    unawaited(ensureAudioHandler());
    if (!mounted) return;
    // Hold the bar short of full while auth resolves, so reaching 100% always
    // coincides with actually leaving this screen.
    setState(() {
      _phase = _Phase.ready;
      _progress = 0.72;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Green aurora. The gradient is a constant child and only its opacity
          // animates, so the layer is rasterised once and reused rather than
          // repainting a full-screen gradient on every frame.
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _glowPulse,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(
                  _glowPulse.value < 0.5
                      ? _glowPulse.value * 2
                      : (1 - _glowPulse.value) * 2,
                );
                return Opacity(opacity: 0.55 + 0.45 * t, child: child);
              },
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.35),
                    radius: 1.0,
                    colors: [Color(0x331DB954), Color(0x001DB954)],
                  ),
                ),
              ),
            ),
          ),
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
                  // RepaintBoundary lets the scaled logo and its blur shadow be
                  // cached as one layer instead of re-rastering the shadow on
                  // every frame of the scale animation.
                  child: RepaintBoundary(
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
                ),
                const SizedBox(height: 26),
                RepaintBoundary(
                  child: FadeTransition(
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
                ),
                const SizedBox(height: 40),
                FadeTransition(opacity: _textFade, child: _progressBar()),
                if (_phase == _Phase.failed) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'Could not start',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      '$_error',
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
                // Available while loading *and* on failure, so a hung boot can
                // be nudged without force-closing the app.
                const SizedBox(height: 10),
                FadeTransition(
                  opacity: _textFade,
                  child: RefreshTileButton(
                    busy: _phase == _Phase.starting,
                    color: _phase == _Phase.failed
                        ? _green
                        : Colors.white.withValues(alpha: 0.4),
                    onPressed: _boot,
                  ),
                ),
              ],
            ),
          ),
          // Watches auth and swaps in the real screen. Mounted only once
          // Firebase is up, because AuthProvider touches FirebaseAuth.
          if (_phase == _Phase.ready) const _AuthGate(),
        ],
      ),
    );
  }

  /// Determinate bar. The `TweenAnimationBuilder` settles on its target and then
  /// stops, unlike the indeterminate indicator it replaces, which ticked
  /// forever even after the app was ready.
  Widget _progressBar() {
    return SizedBox(
      width: 120,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: _progress),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 3,
            backgroundColor: Colors.white.withValues(alpha: 0.10),
            valueColor: const AlwaysStoppedAnimation(_green),
          ),
        ),
      ),
    );
  }
}

/// Resolves the signed-in user and replaces the splash with the real screen.
///
/// Split out of [SplashScreen] so the splash's own build never touches
/// [AuthProvider] - constructing it requires an initialised Firebase.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _navigated = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!_navigated && !auth.isLoading) {
      _navigated = true;
      // Friend/notification/message streams only start once we know who is
      // signed in, otherwise they'd subscribe as a null uid and silently do
      // nothing.
      if (auth.isLoggedIn) {
        context.read<SocialProvider>().syncUid(auth.user?.uid);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 200),
            pageBuilder: (_, _, _) => _targetFor(auth),
            transitionsBuilder: (_, anim, _, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      });
    }
    return const SizedBox.shrink();
  }

  Widget _targetFor(AuthProvider auth) {
    if (!auth.isLoggedIn) return const LoginScreen();
    if (auth.needsOnboarding) return const OnboardingScreen();
    if (auth.isAdmin) return const AdminScreen();
    return const MainScreen();
  }
}
