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

  /// Public accessor for the per-playlist on-device track file (used to
  /// backfill tracks before restoring a playlist that is missing remotely).
  Future<List<TrackModel>> loadCachedTracks(String uid, String playlistId) =>
      _loadTracksFromCache(uid, playlistId);

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
    if (playlist.creatorUid.isEmpty) playlist.creatorUid = uid;
    final docRef = _firestore.collection('playlists').doc(playlist.id);
    await docRef.set(playlist.toFirestore(), SetOptions(merge: true));
    await _saveTracksToCache(uid, playlist.id, playlist.tracks);
  }

  Future<List<PlaylistModel>> getUserPlaylists(String uid) async {
    final snap = await _firestore
        .collection('playlists')
        .where('creatorUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .get();

    final playlists = <PlaylistModel>[];
    for (final doc in snap.docs) {
      final p = PlaylistModel.fromJson(doc.data(), doc.id);
      if (p.tracks.isEmpty) {
        final cached = await _loadTracksFromCache(uid, doc.id);
        if (cached.isNotEmpty) p.tracks = cached;
      }
      playlists.add(p);
    }
    return playlists;
  }

  Future<void> deletePlaylist(String uid, String playlistId) async {
    await _firestore.collection('playlists').doc(playlistId).delete();
    await _deleteCache(uid, playlistId);
  }

  Future<void> sharePlaylist(String uid, String playlistId, String friendUid) async {
    await _firestore.collection('playlists').doc(playlistId).update({
      'sharedWith': FieldValue.arrayUnion([friendUid]),
    });
  }

  Future<List<PlaylistModel>> getSharedPlaylists(String uid) async {
    final snap = await _firestore
        .collection('playlists')
        .where('sharedWith', arrayContains: uid)
        .get();
    return snap.docs.map((d) => PlaylistModel.fromJson(d.data(), d.id)).toList();
  }

  Future<List<PlaylistModel>> getOtherUsersPlaylists(String uid, {int limit = 20}) async {
    final snap = await _firestore
        .collection('playlists')
        .where('creatorUid', isNotEqualTo: uid)
        .orderBy('creatorUid')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => PlaylistModel.fromJson(d.data(), d.id)).toList();
  }

  Future<void> addTrackToPlaylist(String uid, String playlistId, TrackModel track) async {
    await _firestore
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
    final docRef = _firestore.collection('playlists').doc(playlistId);
    try {
      await docRef.update({
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'lastTrackSync': DateTime.now(),
      });
    } on FirebaseException catch (e) {
      // Legacy docs saved with creatorUid:'' fail the update rule
      // (resource.data.creatorUid != uid). Reclaim by re-creating the doc
      // with correct ownership; otherwise keep local cache only.
      if (e.code == 'permission-denied') {
        try {
          final existing = await docRef.get();
          final data = existing.data();
          final owner = (data?['creatorUid'] as String?) ?? '';
          if (!existing.exists || owner.isEmpty) {
            await docRef.set({
              'creatorUid': uid,
              'name': (data?['name'] as String?) ?? 'Playlist',
              'tracks': tracks.map((t) => t.toJson()).toList(),
              'createdAt': data?['createdAt'] ?? FieldValue.serverTimestamp(),
              'lastTrackSync': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } else {
            rethrow;
          }
        } catch (_) {
          rethrow;
        }
      } else {
        rethrow;
      }
    }
    await _saveTracksToCache(uid, playlistId, tracks);
  }

  Future<void> updateLastSpotifySync(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'lastSpotifySync': DateTime.now(),
    });
  }

  // --- Discover cache (Firestore, populated by backend daily job) ---
  String _stableId(String clean) {
    var h = 5381;
    for (final c in clean.codeUnits) {
      h = ((h << 5) + h) + c;
    }
    return (h & 0x7fffffff).toString();
  }

  Future<List<PlaylistModel>> getDiscoverPlaylists(List<String> spotifyUrls) async {
    if (spotifyUrls.isEmpty) return [];
    final cleanUrls = spotifyUrls.map((u) => u.split('?').first).toList();
    // Firestore whereIn max 10, genre+artist 5 each so safe
    final snap = await _firestore.collection('discoverCache').where('spotifyUrl', whereIn: cleanUrls).get();
    final byUrl = {for (final d in snap.docs) (d.data()['spotifyUrl'] as String? ?? ''): PlaylistModel.fromJson(d.data(), d.id)};
    return cleanUrls.map((u) => byUrl[u]).whereType<PlaylistModel>().toList();
  }

  Stream<List<PlaylistModel>> streamDiscoverPlaylists(List<String> spotifyUrls) {
    if (spotifyUrls.isEmpty) return Stream.value([]);
    final cleanUrls = spotifyUrls.map((u) => u.split('?').first).toList();
    return _firestore.collection('discoverCache').where('spotifyUrl', whereIn: cleanUrls).snapshots().map((snap) {
      final byUrl = {for (final d in snap.docs) (d.data()['spotifyUrl'] as String? ?? ''): PlaylistModel.fromJson(d.data(), d.id)};
      return cleanUrls.map((u) => byUrl[u]).whereType<PlaylistModel>().toList();
    });
  }

  Future<void> cacheDiscoverPlaylist(PlaylistModel playlist) async {
    final clean = (playlist.spotifyUrl.isNotEmpty ? playlist.spotifyUrl : playlist.id).split('?').first;
    // Query-first to find existing doc id, else create with stable id
    final existing = await _firestore.collection('discoverCache').where('spotifyUrl', isEqualTo: clean).limit(1).get();
    final docId = existing.docs.isNotEmpty ? existing.docs.first.id : _stableId(clean);
    await _firestore.collection('discoverCache').doc(docId).set({
      ...playlist.toFirestore(),
      'spotifyUrl': clean,
      'lastScrapedAt': FieldValue.serverTimestamp(),
      'trackCount': playlist.tracks.length,
    }, SetOptions(merge: true));
  }

  Future<PlaylistModel?> fetchDiscoverPlaylistWithCache(String spotifyUrl, {required Future<PlaylistModel?> Function() fetcher}) async {
    final clean = spotifyUrl.split('?').first;
    // Query by field (covers both legacy hashCode docs and new md5 docs)
    final q = await _firestore.collection('discoverCache').where('spotifyUrl', isEqualTo: clean).limit(1).get();
    if (q.docs.isNotEmpty) {
      final doc = q.docs.first;
      final data = doc.data();
      final ts = (data['lastScrapedAt'] as Timestamp?);
      final ageHours = ts == null ? 999 : DateTime.now().difference(ts.toDate()).inHours;
      if (ageHours < 12) return PlaylistModel.fromJson(data, doc.id);
      if (ageHours < 48) {
        fetcher().then((fresh) { if (fresh != null) cacheDiscoverPlaylist(fresh); });
        return PlaylistModel.fromJson(data, doc.id);
      }
    }
    final fresh = await fetcher();
    if (fresh != null) await cacheDiscoverPlaylist(fresh);
    return fresh;
  }
}
