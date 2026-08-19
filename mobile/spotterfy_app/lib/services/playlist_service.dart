import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import '../models/playlist_model.dart';
import '../models/track_model.dart';

class PlaylistService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<File> _cacheFile(String uid, String playlistId) async {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${dir.path}/playlist_cache');
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
    return File('${cacheDir.path}/${uid}_$playlistId.json');
  }

  Future<void> _saveTracksToCache(String uid, String playlistId, List<TrackModel> tracks) async {
    try {
      final file = await _cacheFile(uid, playlistId);
      await file.writeAsString(jsonEncode(tracks.map((t) => t.toJson()).toList()));
    } catch (e) {
      debugPrint('Track cache write failed: $e');
    }
  }

  Future<List<TrackModel>> _loadTracksFromCache(String uid, String playlistId) async {
    try {
      final file = await _cacheFile(uid, playlistId);
      if (!await file.exists()) return [];
      final data = jsonDecode(await file.readAsString()) as List<dynamic>;
      return data.map((t) => TrackModel.fromJson(t as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('Track cache read failed: $e');
      return [];
    }
  }

  Future<void> _deleteCache(String uid, String playlistId) async {
    final file = await _cacheFile(uid, playlistId);
    if (await file.exists()) await file.delete();
  }

  Future<void> savePlaylist(String uid, PlaylistModel playlist) async {
    final docRef = _firestore.collection('users').doc(uid).collection('playlists').doc(playlist.id);
    await docRef.set(playlist.toFirestore());
    await _saveTracksToCache(uid, playlist.id, playlist.tracks);
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
      // Load tracks from cache first, then Firestore (which has them embedded now)
      if (p.tracks.isEmpty) {
        final cached = await _loadTracksFromCache(uid, doc.id);
        if (cached.isNotEmpty) {
          p.tracks = cached;
        }
      }
      playlists.add(p);
    }
    return playlists;
  }

  Future<void> deletePlaylist(String uid, String playlistId) async {
    await _firestore.collection('users').doc(uid).collection('playlists').doc(playlistId).delete();
    await _deleteCache(uid, playlistId);
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
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'lastTrackSync': DateTime.now(),
    });
    await _saveTracksToCache(uid, playlistId, tracks);
  }

  Future<void> updateLastSpotifySync(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'lastSpotifySync': DateTime.now(),
    });
  }
}
