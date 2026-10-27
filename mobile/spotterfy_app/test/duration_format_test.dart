import 'package:flutter_test/flutter_test.dart';
import 'package:spotterfy_app/utils/duration_format.dart';

void main() {
  group('formatDuration', () {
    test('uses mm:ss under an hour and hh:mm:ss from an hour on', () {
      expect(formatDuration(Duration.zero), '00:00');
      expect(formatDuration(const Duration(seconds: 5)), '00:05');
      expect(formatDuration(const Duration(minutes: 3, seconds: 45)), '03:45');
      expect(
        formatDuration(const Duration(hours: 1, minutes: 5, seconds: 32)),
        '01:05:32',
      );
      expect(
        formatDuration(const Duration(hours: 12, minutes: 34, seconds: 56)),
        '12:34:56',
      );
    });

    test('truncates sub-second remainders instead of rounding up', () {
      expect(formatDuration(const Duration(milliseconds: 59600)), '00:59');
      expect(formatDuration(const Duration(milliseconds: 999)), '00:00');
    });

    test('clamps negative durations to zero', () {
      expect(formatDuration(const Duration(seconds: -5)), '00:00');
    });

    test('millisecond helper matches the Duration form', () {
      expect(formatDurationMs(0), '00:00');
      expect(formatDurationMs(3723000), '01:02:03');
    });
  });
}
