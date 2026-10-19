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
  testWidgets('every bar changes length, and the centre is always the long '
      'one', (tester) async {
    await tester.pumpWidget(
      _host(const Center(child: AnimatedEqualizer(size: 36, barWidth: 4))),
    );

    final lengths = <int, Set<String>>{
      for (var i = 0; i < 3; i++) i: <String>{},
    };
    // Sample a little over two full cycles.
    for (var step = 0; step < 60; step++) {
      await tester.pump(const Duration(milliseconds: 40));
      final h = _bars(tester);
      expect(
        h[1],
        greaterThan(h[0]),
        reason: 'centre bar must stay longer than the left one',
      );
      expect(
        h[1],
        greaterThan(h[2]),
        reason: 'centre bar must stay longer than the right one',
      );
      for (var i = 0; i < 3; i++) {
        lengths[i]!.add(h[i].toStringAsFixed(1));
      }
    }

    for (var i = 0; i < 3; i++) {
      expect(
        lengths[i]!.length,
        greaterThan(5),
        reason: 'bar $i should grow and shrink while playing',
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
    final before = _bars(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_bars(tester), before);
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
