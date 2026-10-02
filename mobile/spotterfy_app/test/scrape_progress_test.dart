import 'package:flutter_test/flutter_test.dart';
import 'package:spotterfy_app/services/api_service.dart';

/// The import notification claims "song 7 of 24 - 29%". If the parsing of
/// `/api/scrape-progress` is wrong the bar either lies about the percentage or
/// claims a total the backend has not reported yet, and neither is visible in
/// normal use - it just looks like a slightly-off number.
void main() {
  group('ScrapeProgress', () {
    test('reports a fraction once the backend knows the total', () {
      const p = ScrapeProgress(completed: 6, total: 24, status: 'scraping');
      expect(p.fraction, closeTo(0.25, 1e-9));
    });

    test('has no fraction while the total is still unknown', () {
      // The backend starts at total:0 and only fills it in once it has
      // enumerated the playlist. A fraction here would be a made-up number.
      const p = ScrapeProgress(completed: 0, total: 0, status: 'starting');
      expect(p.fraction, isNull);
    });

    test('clamps a total that the backend has not caught up with', () {
      // Rounding drift between the track count and the loop counter must not
      // push the bar past 100%.
      const p = ScrapeProgress(completed: 25, total: 24, status: 'scraping');
      expect(p.fraction, 1.0);
    });

    test('never reports a negative fraction', () {
      const q = ScrapeProgress(completed: -1, total: 24, status: 'scraping');
      expect(q.fraction, 0.0);
    });

    test('recognises the terminal states', () {
      expect(
        const ScrapeProgress(
          completed: 1,
          total: 1,
          status: 'complete',
        ).isComplete,
        isTrue,
      );
      expect(
        const ScrapeProgress(completed: 0, total: 0, status: 'error').isError,
        isTrue,
      );
      expect(
        const ScrapeProgress(
          completed: 1,
          total: 2,
          status: 'scraping',
        ).isComplete,
        isFalse,
      );
    });

    test('a finished job reports 100%', () {
      const p = ScrapeProgress(completed: 24, total: 24, status: 'complete');
      expect(p.fraction, 1.0);
    });
  });
}
