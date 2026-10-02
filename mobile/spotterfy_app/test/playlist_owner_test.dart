import 'package:flutter_test/flutter_test.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/models/track_model.dart';

PlaylistModel _playlist({
  String owner = 'Spotify',
  String creatorUid = 'system_discover',
  bool isUsersOwn = false,
  String name = 'Top Hits',
}) => PlaylistModel(
  id: 'p1',
  name: name,
  owner: owner,
  creatorUid: creatorUid,
  isUsersOwn: isUsersOwn,
  spotifyUrl: 'https://open.spotify.com/playlist/37i9dQZF1DX1kfybUJZB6S',
  source: 'spotify',
  tracks: [
    TrackModel(
      id: 't1',
      title: 'Song',
      artists: 'Artist',
      album: 'Album',
      cover: '',
      sourceUrl: 'https://youtu.be/x',
    ),
  ],
);

void main() {
  group('PlaylistModel.withoutCreator', () {
    test('clears the creator uid, which is what hides the profile button', () {
      // The detail screen draws its profile button purely on "does this
      // playlist have an owner uid", so this is the field that matters.
      final stripped = _playlist().withoutCreator();
      expect(stripped.creatorUid, isEmpty);
    });

    test('keeps the author so the page still reads "By Spotify"', () {
      // The regression this guards: clearing owner as well removed the line
      // entirely, when only the profile affordance should have gone.
      final stripped = _playlist().withoutCreator();
      expect(stripped.owner, 'Spotify');
    });

    test('keeps everything needed to open and play the playlist', () {
      final original = _playlist();
      final stripped = original.withoutCreator();
      expect(stripped.id, original.id);
      expect(stripped.name, original.name);
      expect(stripped.spotifyUrl, original.spotifyUrl);
      expect(stripped.source, original.source);
      expect(stripped.coverUrl, original.coverUrl);
      expect(stripped.tracks.length, original.tracks.length);
      expect(stripped.tracks.first.id, original.tracks.first.id);
      expect(stripped.createdAt, original.createdAt);
    });

    test('leaves the original instance untouched', () {
      final original = _playlist();
      original.withoutCreator();
      expect(original.owner, 'Spotify');
      expect(original.creatorUid, 'system_discover');
    });

    test('a community playlist keeps its real creator and profile button', () {
      // Community rows are never passed through withoutCreator, so a real
      // user's uid must survive the round trip when it is applied.
      final community = _playlist(owner: 'Ada', creatorUid: 'uid-ada');
      final untouched = community.withoutCreator();
      expect(untouched.owner, 'Ada');
      expect(untouched.creatorUid, isEmpty);
    });

    test('the user\'s own playlist stays recognisable as theirs', () {
      final mine = _playlist(
        owner: '',
        creatorUid: 'uid-123',
        isUsersOwn: true,
      );
      final stripped = mine.withoutCreator();
      expect(stripped.isUsersOwn, isTrue);
    });
  });

  group('PlaylistModel.displayName', () {
    test('drops the scraper owner suffix from an imported playlist', () {
      // Spotify/YouTube hand back "Playlist - Owner" as the *name*, so an
      // imported playlist otherwise shows the author twice.
      final p = _playlist(name: 'Top Hits - Spotify');
      expect(p.displayName, 'Top Hits');
    });

    test('drops a "by Owner" suffix too', () {
      final p = _playlist(name: 'Top Hits by Spotify');
      expect(p.displayName, 'Top Hits');
    });

    test('leaves a dash that is part of the title alone', () {
      // A mid-string dash is real content, not an author suffix.
      final p = _playlist(name: 'Jay-Z - The Blueprint');
      expect(p.displayName, 'Jay-Z - The Blueprint');
    });

    test('never returns an empty title', () {
      final p = _playlist(name: ' - Spotify');
      expect(p.displayName.trim(), isNotEmpty);
    });
  });
}
