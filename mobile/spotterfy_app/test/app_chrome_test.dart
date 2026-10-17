import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotterfy_app/widgets/app_chrome.dart';

void main() {
  testWidgets('HideAppChrome updates visibility outside the build phase', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: AppChrome.instance.revision,
          builder: (context, _, _) =>
              const HideAppChrome(child: Scaffold(body: Text('Settings'))),
        ),
      ),
    );

    expect(AppChrome.instance.miniPlayerVisible, isFalse);
    expect(find.text('Settings'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(AppChrome.instance.miniPlayerVisible, isTrue);
  });
}
