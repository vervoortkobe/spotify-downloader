import 'package:flutter/material.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// The app-wide page background.
///
/// Extracted from [BasePageScaffold] so every screen can opt into the same look
/// instead of hand-rolling a flat `SpotterfyTheme.background` fill, which is
/// what left the profile and settings pages looking out of place.
class AppBackground extends StatelessWidget {
  final Widget child;

  /// Unified dark gradient, matching the Jam/Chat page and onboarding waves.
  static const gradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0d1f14), Color(0xFF07110b), Color(0xFF050a07)],
  );

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: gradient),
      child: child,
    );
  }
}

/// A [Scaffold] pre-wrapped in [AppBackground].
///
/// Drop-in replacement for a bare `Scaffold(backgroundColor: ...)` on pages that
/// should match Discover / Library / Chat. Pass [appBar] to supply a custom one;
/// otherwise a transparent bar with the standard title is built.
class AppGradientScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final bool extendBodyBehindAppBar;

  /// Title for the default app bar. Ignored when [appBar] is supplied.
  final String? title;

  const AppGradientScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.extendBodyBehindAppBar = false,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: extendBodyBehindAppBar,
        appBar:
            appBar ??
            AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              title: title == null
                  ? null
                  : Text(
                      title!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
              // Fade behind the bar so content scrolls under it cleanly, the
              // same treatment BasePageScaffold uses.
              flexibleSpace: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      SpotterfyTheme.background.withValues(alpha: 0.95),
                      SpotterfyTheme.background.withValues(alpha: 0.8),
                      SpotterfyTheme.background.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
        body: body,
        floatingActionButton: floatingActionButton,
      ),
    );
  }
}
