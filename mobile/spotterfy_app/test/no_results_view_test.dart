import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotterfy_app/widgets/no_results_view.dart';

void main() {
  testWidgets('scrollable: true keeps the panel\'s own scroll view', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: NoResultsView(query: 'abc')),
    );

    expect(find.byType(Scrollable), findsOneWidget);
  });

  testWidgets('scrollable: false drops the inner scroll view', (tester) async {
    // The search page wraps this state in a RefreshIndicator, which brings its
    // own scrollable. Nesting two hands the drag to the inner one, so the pull
    // gesture never reaches the indicator.
    await tester.pumpWidget(
      const MaterialApp(home: NoResultsView(query: 'abc', scrollable: false)),
    );

    expect(find.byType(Scrollable), findsNothing);
    expect(find.textContaining('abc'), findsWidgets);
  });
}
