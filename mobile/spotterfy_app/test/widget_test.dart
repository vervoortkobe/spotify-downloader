import 'package:flutter_test/flutter_test.dart';
import 'package:spotterfy_app/models/track_model.dart';

void main() {
  group('TrackModel', () {
    test('fromJson creates TrackModel correctly', () {
      final json = {
        'id': 'test-id',
        'title': 'Test Song',
        'artists': 'Artist One, Artist Two',
        'album': 'Test Album',
        'cover': 'https://example.com/cover.jpg',
        'releaseDate': '2024-01-01',
        'sourceUrl': 'https://open.spotify.com/track/test',
        'durationMs': 240000,
      };

      final track = TrackModel.fromJson(json);

      expect(track.id, 'test-id');
      expect(track.title, 'Test Song');
      expect(track.artists, 'Artist One, Artist Two');
      expect(track.album, 'Test Album');
      expect(track.cover, 'https://example.com/cover.jpg');
      expect(track.releaseDate, '2024-01-01');
      expect(track.durationMs, 240000);
    });

    test('toJson serializes correctly', () {
      final track = TrackModel(
        id: 'test-id',
        title: 'Test Song',
        artists: 'Artist One',
        album: 'Album',
        cover: 'https://example.com/cover.jpg',
        releaseDate: '2024-06-01',
        sourceUrl: 'https://open.spotify.com/track/test',
        durationMs: 180000,
      );

      final json = track.toJson();

      expect(json['id'], 'test-id');
      expect(json['title'], 'Test Song');
      expect(json['artists'], 'Artist One');
      expect(json['album'], 'Album');
      expect(json['durationMs'], 180000);
    });

    test('copyWith overrides sourceUrl', () {
      final track = TrackModel(
        id: 'id1',
        title: 'Original',
        artists: 'Artist',
        sourceUrl: 'old-url',
      );

      final updated = track.copyWith(sourceUrl: 'new-url');

      expect(updated.sourceUrl, 'new-url');
      expect(updated.id, 'id1');
      expect(updated.title, 'Original');
    });

    test('fromJson handles missing fields with defaults', () {
      final json = <String, dynamic>{};

      final track = TrackModel.fromJson(json);

      expect(track.id, '');
      expect(track.title, '');
      expect(track.durationMs, 0);
    });
  });
}
