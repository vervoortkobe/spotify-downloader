import 'package:flutter_test/flutter_test.dart';
import 'package:spotterfy_app/providers/jam_provider.dart';

void main() {
  group('JamProvider.createSession', () {
    // Both guards run before the Firestore-backed service is touched, so these
    // tests need no Firebase setup.
    test('refuses a session with no friends invited', () async {
      final jam = JamProvider();
      await expectLater(
        jam.createSession('me', 'Solo jam', const []),
        throwsA(isA<StateError>()),
      );
    });

    test('does not count inviting yourself as a friend', () async {
      final jam = JamProvider();
      await expectLater(
        jam.createSession('me', 'Solo jam', const [], invite: ['me']),
        throwsA(isA<StateError>()),
      );
    });
  });
}
