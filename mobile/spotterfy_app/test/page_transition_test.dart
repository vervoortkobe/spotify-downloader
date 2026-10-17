import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';

void main() {
  test('now-playing slides up with the same timing as Discover navigation', () {
    final discoverRoute = swipeRoute<void>(const SizedBox()) as SlidePageRoute;
    final playerRoute =
        nowPlayingRoute<void>(const SizedBox()) as NowPlayingPageRoute;

    expect(discoverRoute, isA<SlidePageRoute>());
    expect(discoverRoute.transitionDuration, pageTransitionDuration);
    expect(discoverRoute.reverseTransitionDuration, pageTransitionDuration);
    expect(playerRoute.transitionDuration, discoverRoute.transitionDuration);
    expect(
      playerRoute.reverseTransitionDuration,
      discoverRoute.reverseTransitionDuration,
    );
  });
}
