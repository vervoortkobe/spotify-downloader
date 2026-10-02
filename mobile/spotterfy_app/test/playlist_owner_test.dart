import 'package:flutter_test/flutter_test.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/models/track_model.dart';

PlaylistModel _playlist({
  String owner = 'Spotify',
  String creatorUid = 'system_discover',
  bool isUsersOwn = false,
}) => PlaylistModel(
  id: 'p1',
  name: 'Top Hits',
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
}
