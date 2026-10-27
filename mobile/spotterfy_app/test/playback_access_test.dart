import 'package:flutter_test/flutter_test.dart';
import 'package:spotterfy_app/services/playback_access.dart';

void main() {
  final access = PlaybackAccess.instance;

  setUp(access.reset);
  tearDown(access.reset);

  test('fails closed until the account status is known', () {
    expect(access.isKnown, isFalse);
    expect(access.canPlay, isFalse);
  });

  test('a suspended account cannot play, and restoring allows it again', () {
    access.update(suspended: true);
    expect(access.isKnown, isTrue);
    expect(access.isSuspended, isTrue);
    expect(access.canPlay, isFalse);

    access.update(suspended: false);
    expect(access.isSuspended, isFalse);
    expect(access.canPlay, isTrue);
  });

  test('known-status waiters are released once auth reports', () async {
    final waited = access.whenKnown;
    await Future<void>.delayed(Duration.zero);
    access.update(suspended: false);
    await waited;
    expect(access.canPlay, isTrue);
  });

  test('changes notify playback listeners', () {
    var changes = 0;
    access.addListener(() => changes++);

    access.update(suspended: false);
    expect(changes, 1);
    access.update(suspended: false);
    expect(changes, 1);
    access.update(suspended: true);
    expect(changes, 2);
  });
}
