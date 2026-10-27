import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/animated_equalizer.dart';
import 'package:spotterfy_app/widgets/track_tile.dart';

/// Bar heights, left to right, of the equalizer on screen.
List<double> _bars(WidgetTester tester) {
  final bars = find.descendant(
    of: find.byType(AnimatedEqualizer),
    matching: find.byType(Container),
  );
  return [for (var i = 0; i < 3; i++) tester.getSize(bars.at(i)).height];
}

/// Vertical bounce offsets, left to right, of the equalizer's three bars.
///
/// The current design keeps each bar's height fixed and translates the whole
/// bar upwards, so measuring the child Container's height alone would report a
/// static value even while the indicator is animating.
List<double> _bounce(WidgetTester tester) {
  final transforms = find.descendant(
    of: find.byType(AnimatedEqualizer),
    matching: find.byType(Transform),
  );
  return [
    for (var i = 0; i < 3; i++)
      tester.widget<Transform>(transforms.at(i)).transform.getTranslation().y,
  ];
}

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: const MediaQueryData(),
    child: Material(color: SpotterfyTheme.surface, child: child),
  ),
);

TrackModel _track(String id, String title) =>
    TrackModel(id: id, title: title, artists: 'Artist');

void main() {
  testWidgets('every bar bounces, and the centre is always the long one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const Center(child: AnimatedEqualizer(size: 36, barWidth: 4))),
    );

    final bounces = <int, Set<String>>{
      for (var i = 0; i < 3; i++) i: <String>{},
    };
    // Sample a little over two full cycles.
    for (var step = 0; step < 60; step++) {
      await tester.pump(const Duration(milliseconds: 40));
      final heights = _bars(tester);
      expect(
        heights[1],
        greaterThan(heights[0]),
        reason: 'centre bar must stay longer than the left one',
      );
      expect(
        heights[1],
        greaterThan(heights[2]),
        reason: 'centre bar must stay longer than the right one',
      );
      final offsets = _bounce(tester);
      for (var i = 0; i < 3; i++) {
        bounces[i]!.add(offsets[i].toStringAsFixed(1));
      }
    }

    for (var i = 0; i < 3; i++) {
      expect(
        bounces[i]!.length,
        greaterThan(5),
        reason: 'bar $i should bounce while playing',
      );
    }
  });

  testWidgets('a paused indicator holds still', (tester) async {
    await tester.pumpWidget(
      _host(
        const Center(
          child: AnimatedEqualizer(size: 36, barWidth: 4, animating: false),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    final before = _bounce(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_bounce(tester), before);
  });

  testWidgets('a row only puts the bars on its cover while playing', (
    tester,
  ) async {
    Future<void> pump({required bool playing}) {
      return tester.pumpWidget(
        _host(
          Column(
            children: [
              TrackTile(
                track: _track('playing', 'Currently playing'),
                isPlaying: playing,
                isSelected: true,
                onPlay: () {},
              ),
              // Highlighted as the current track but paused.
              TrackTile(
                track: _track('paused', 'Playing but paused'),
                isSelected: true,
                onPlay: () {},
              ),
            ],
          ),
        ),
      );
    }

    await pump(playing: true);
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(AnimatedEqualizer), findsOneWidget);

    await pump(playing: false);
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(AnimatedEqualizer), findsNothing);
  });
}
