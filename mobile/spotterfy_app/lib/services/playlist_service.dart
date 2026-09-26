import 'dart:async';
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

  /// Reads the community catalogue (playlists created by *other* users),
  /// newest first. Ordering is done server-side on `createdAt` so no composite
  /// index is required and the newest playlists are guaranteed to be inside
  /// the window; the caller filters/name-matches locally because Firestore
  /// can't do a case-insensitive "contains".
  Future<List<PlaylistModel>> getCommunityPlaylists({
    String? excludeUid,
    int limit = 30,
    String nameQuery = '',
  }) async {
    final q = nameQuery.trim().toLowerCase();
    final out = <PlaylistModel>[];
    try {
      // Single-field index on createdAt is automatic -> no composite index.
      final snap = await _firestore
          .collection('playlists')
          .orderBy('createdAt', descending: true)
          .limit(300)
          .get();
      for (final d in snap.docs) {
        if (out.length >= limit) break;
        final PlaylistModel p;
        try {
          p = PlaylistModel.fromJson(d.data(), d.id);
        } catch (e) {
          debugPrint('skipping malformed playlist ${d.id}: $e');
          continue;
        }
        if (p.creatorUid.isEmpty) continue;
        if (excludeUid != null && p.creatorUid == excludeUid) continue;
        if (q.isNotEmpty && !p.name.toLowerCase().contains(q)) continue;
        out.add(p);
      }
    } catch (e) {
      debugPrint('getCommunityPlaylists failed: $e');
    }
    return out;
  }

  /// Case-insensitive name search over playlists created by *other* users.
  Future<List<PlaylistModel>> searchOtherUsersPlaylists(
    String query, {
    String? excludeUid,
    int limit = 20,
  }) =>
      getCommunityPlaylists(excludeUid: excludeUid, limit: limit, nameQuery: query);

  /// Playlists created by [uid], newest first. Used by the Discover profile
  /// lookup so a found profile can show that user's playlists. Ordered before
  /// limiting so the newest N are the ones returned.
  Future<List<PlaylistModel>> getPlaylistsByCreator(String uid, {int limit = 30}) async {
    try {
      // Uses the (creatorUid ASC, createdAt DESC) composite index.
      final snap = await _firestore
          .collection('playlists')
          .where('creatorUid', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      final list = <PlaylistModel>[];
      for (final d in snap.docs) {
        try {
          list.add(PlaylistModel.fromJson(d.data(), d.id));
        } catch (e) {
          debugPrint('skipping malformed playlist ${d.id}: $e');
        }
      }
      list.sort((a, b) => (b.lastTrackSync ?? b.createdAt).compareTo(a.lastTrackSync ?? a.createdAt));
      return list;
    } catch (e) {
      debugPrint('getPlaylistsByCreator failed: $e');
      return [];
    }
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

  /// Firestore rejects `in` queries with more than 10 values, so the URL list
  /// is fetched in chunks and merged. (There are far more than 10 discover
  /// playlists now, which previously made the whole query fail.)
  static const int _whereInChunk = 10;

  Future<List<PlaylistModel>> getDiscoverPlaylists(List<String> spotifyUrls) async {
    if (spotifyUrls.isEmpty) return [];
    final cleanUrls = spotifyUrls.map((u) => u.split('?').first).toList();
    final byUrl = <String, PlaylistModel>{};
    for (var i = 0; i < cleanUrls.length; i += _whereInChunk) {
      final chunk = cleanUrls.sublist(i, (i + _whereInChunk).clamp(0, cleanUrls.length));
      if (chunk.isEmpty) continue;
      try {
        final snap = await _firestore.collection('discoverCache').where('spotifyUrl', whereIn: chunk).get();
        for (final d in snap.docs) {
          try {
            final u = (d.data()['spotifyUrl'] as String?) ?? '';
            byUrl[u] = PlaylistModel.fromJson(d.data(), d.id);
          } catch (e) {
            debugPrint('skipping malformed discoverCache doc ${d.id}: $e');
          }
        }
      } catch (e) {
        debugPrint('getDiscoverPlaylists chunk failed: $e');
      }
    }
    return cleanUrls.map((u) => byUrl[u]).whereType<PlaylistModel>().toList();
  }

  Stream<List<PlaylistModel>> streamDiscoverPlaylists(List<String> spotifyUrls) {
    if (spotifyUrls.isEmpty) return Stream.value([]);
    final cleanUrls = spotifyUrls.map((u) => u.split('?').first).toList();
    // Merge the per-chunk streams into one.
    final streams = <Stream<QuerySnapshot<Map<String, dynamic>>>>[];
    for (var i = 0; i < cleanUrls.length; i += _whereInChunk) {
      final chunk = cleanUrls.sublist(i, (i + _whereInChunk).clamp(0, cleanUrls.length));
      if (chunk.isEmpty) continue;
      streams.add(_firestore.collection('discoverCache').where('spotifyUrl', whereIn: chunk).snapshots());
    }
    late StreamController<List<PlaylistModel>> out;
    final subs = <StreamSubscription<dynamic>>[];
    out = StreamController<List<PlaylistModel>>.broadcast(onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
    });
    for (final c in streams) {
      subs.add(c.listen((snap) {
        if (out.isClosed) return;
        final byUrl = <String, PlaylistModel>{};
        for (final d in snap.docs) {
          try {
            final u = (d.data()['spotifyUrl'] as String?) ?? '';
            byUrl[u] = PlaylistModel.fromJson(d.data(), d.id);
          } catch (_) {}
        }
        out.add(cleanUrls.map((u) => byUrl[u]).whereType<PlaylistModel>().toList());
      }, onError: (Object e) {
        debugPrint('streamDiscoverPlaylists chunk error: $e');
      }));
    }
    return out.stream;
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
