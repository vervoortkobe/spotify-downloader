import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/playlist_model.dart';
import '../models/track_model.dart';

class PlaylistService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> savePlaylist(String uid, PlaylistModel playlist) async {
    final docRef = _firestore.collection('users').doc(uid).collection('playlists').doc();
    await docRef.set(playlist.toFirestore());
    // Store tracks as subcollection for custom playlists
    if (playlist.isCustom && playlist.tracks.isNotEmpty) {
      final batch = _firestore.batch();
      for (final track in playlist.tracks) {
        final trackRef = docRef.collection('tracks').doc(track.id);
        batch.set(trackRef, track.toJson());
      }
      await batch.commit();
    }
  }

  Future<List<PlaylistModel>> getUserPlaylists(String uid) async {
    final snap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('playlists')
        .orderBy('createdAt', descending: true)
        .get();

    final playlists = <PlaylistModel>[];
    for (final doc in snap.docs) {
      final p = PlaylistModel.fromJson(doc.data(), doc.id);
      // Load tracks for custom playlists
      if (p.isCustom) {
        final trackSnap = await doc.reference.collection('tracks').get();
        p.tracks = trackSnap.docs
            .map((t) => TrackModel.fromJson(t.data()))
            .toList();
      }
      playlists.add(p);
    }
    return playlists;
  }

  Future<void> deletePlaylist(String uid, String playlistId) async {
    await _firestore.collection('users').doc(uid).collection('playlists').doc(playlistId).delete();
  }

  Future<void> sharePlaylist(String uid, String playlistId, String friendUid) async {
    await _firestore.collection('users').doc(uid).collection('playlists').doc(playlistId).update({
      'sharedWith': FieldValue.arrayUnion([friendUid]),
    });
  }

  Future<List<PlaylistModel>> getSharedPlaylists(String uid) async {
    final snap = await _firestore
        .collectionGroup('playlists')
        .where('sharedWith', arrayContains: uid)
        .get();
    return snap.docs.map((d) => PlaylistModel.fromJson(d.data(), d.id)).toList();
  }

  Future<void> addTrackToPlaylist(String uid, String playlistId, TrackModel track) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('playlists')
        .doc(playlistId)
        .collection('tracks')
        .doc(track.id)
        .set(track.toJson());
  }

  Future<void> updatePlaylistTracks(
    String uid,
    String playlistId,
    List<TrackModel> tracks,
  ) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('playlists')
        .doc(playlistId)
        .update({
      'lastTrackSync': DateTime.now(),
    });
  }

  Future<void> updateLastSpotifySync(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'lastSpotifySync': DateTime.now(),
    });
  }
}
