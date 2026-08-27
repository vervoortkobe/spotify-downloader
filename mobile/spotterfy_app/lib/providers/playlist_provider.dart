import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/services/playlist_service.dart';

class PlaylistProvider extends ChangeNotifier {
  final PlaylistService _playlistService = PlaylistService();
  List<PlaylistModel> _playlists = [];
  List<PlaylistModel> _sharedPlaylists = [];
  PlaylistModel? _currentPlaylist;
  bool _isLoading = false;
  String? _error;

  List<PlaylistModel> get playlists => _playlists;
  List<PlaylistModel> get sharedPlaylists => _sharedPlaylists;
  PlaylistModel? get currentPlaylist => _currentPlaylist;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadPlaylists(String uid, {bool forceRefresh = false}) async {
    List<PlaylistModel> cached = [];
    if (!forceRefresh) {
      try {
        await _loadCachedPlaylists();
        cached = _playlists;
        if (_playlists.isNotEmpty) {
          notifyListeners(); // Show cache immediately
        }
      } catch (_) {}
    }

    _isLoading = cached.isEmpty;
    notifyListeners();
    try {
      final remotePlaylists = await _playlistService.getUserPlaylists(uid);
      // Merge: prefer remote, but keep locally-cached playlists that were
      // never synced to the cloud (e.g. import while offline / permission denied).
      final merged = <PlaylistModel>[...remotePlaylists];
      final remoteIds = remotePlaylists.map((p) => p.id).toSet();
      for (final c in cached) {
        if (!remoteIds.contains(c.id)) merged.add(c);
      }
      _playlists = merged;
      _error = null;
      try {
        _sharedPlaylists = await _playlistService.getSharedPlaylists(uid);
      } catch (e) {
        debugPrint('getSharedPlaylists failed (non-fatal): $e');
        _sharedPlaylists = [];
      }
      await _saveCachedPlaylists();
    } catch (e) {
      if (_playlists.isEmpty) {
        _error = 'Failed to load playlists';
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _saveCachedPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _playlists.map((p) => p.toCache()).toList();
    await prefs.setString('cached_playlists_v3', jsonEncode(data));
  }

  Future<void> _loadCachedPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    // Clear stale cache from old schemes that didn't store tracks
    await prefs.remove('cached_playlists');
    await prefs.remove('cached_playlists_v2');
    final cached = prefs.getString('cached_playlists_v3');
    if (cached == null) return;
    final data = jsonDecode(cached) as List<dynamic>;
    _playlists = data
        .map((d) => PlaylistModel.fromCache(d as Map<String, dynamic>))
        .toList();
    _playlists.removeWhere((p) => p.id.isEmpty);
  }

  bool hasPlaylistWithUrl(String spotifyUrl) {
    final clean = spotifyUrl.split('?').first;
    return _playlists.any((p) => p.spotifyUrl == clean || p.spotifyUrl == spotifyUrl || p.id == clean || p.id == spotifyUrl || p.id == clean.hashCode.toString());
  }

  PlaylistModel? getPlaylistByUrl(String spotifyUrl) {
    final clean = spotifyUrl.split('?').first;
    try {
      return _playlists.firstWhere(
        (p) => p.spotifyUrl == clean || p.spotifyUrl == spotifyUrl || p.id == clean || p.id == spotifyUrl || p.id == clean.hashCode.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<PlaylistModel?> importFromUrl(String url, {String service = 'auto', String? creatorUid}) async {
    debugPrint('importFromUrl: starting scrape for $url');
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final playlist = await ApiService.scrapePlaylist(url, service: service);
      if (playlist == null) {
        _error = 'Failed to fetch playlist';
        debugPrint('importFromUrl: scrape returned null');
        _isLoading = false;
        notifyListeners();
        return null;
      }
      debugPrint('importFromUrl: scrape succeeded, playlist=${playlist.name}, tracks=${playlist.tracks.length}');
      _currentPlaylist = playlist;
      _isLoading = false;
      notifyListeners();
      return playlist;
    } catch (e) {
      _error = 'Error: $e';
      debugPrint('importFromUrl: exception: $e');
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<void> savePlaylist(String uid, PlaylistModel playlist) async {
    debugPrint('savePlaylist called: uid=$uid, playlist.id=${playlist.id}, playlist.name=${playlist.name}, tracks=${playlist.tracks.length}');
    // Optimistically add locally so it appears in the app immediately / offline.
    final idx = _playlists.indexWhere((p) => p.id == playlist.id);
    if (idx >= 0) {
      _playlists[idx] = playlist;
      debugPrint('savePlaylist: updated existing at index $idx');
    } else {
      _playlists.insert(0, playlist);
      debugPrint('savePlaylist: inserted new at index 0, total playlists=${_playlists.length}');
    }
    _currentPlaylist = playlist;
    _error = null;
    await _saveCachedPlaylists();
    debugPrint('savePlaylist: cache saved, notifying listeners');
    notifyListeners();
    try {
      debugPrint('savePlaylist: attempting cloud write...');
      await _playlistService.savePlaylist(uid, playlist);
      debugPrint('savePlaylist: cloud write succeeded');
      await _saveCachedPlaylists();
    } catch (e) {
      _error = 'Saved locally only. Cloud sync failed: $e';
      debugPrint('savePlaylist remote error: $e');
    }
    notifyListeners();
    debugPrint('savePlaylist: done');
  }

  Future<void> updatePlaylist(String uid, PlaylistModel playlist) async {
    final idx = _playlists.indexWhere((p) => p.id == playlist.id);
    if (idx >= 0) {
      _playlists[idx] = playlist;
    } else {
      _playlists.insert(0, playlist);
    }
    _currentPlaylist = playlist;
    await _saveCachedPlaylists();
    notifyListeners();
    try {
      await _playlistService.savePlaylist(uid, playlist);
      await _saveCachedPlaylists();
    } catch (e) {
      _error = 'Saved locally only. Cloud sync failed: $e';
      debugPrint('updatePlaylist remote error: $e');
    }
    notifyListeners();
  }

  Future<void> deletePlaylist(String uid, String playlistId) async {
    await _playlistService.deletePlaylist(uid, playlistId);
    _playlists.removeWhere((p) => p.id == playlistId);
    await _saveCachedPlaylists();
    notifyListeners();
  }

  Future<void> sharePlaylist(String uid, String playlistId, String friendUid) async {
    await _playlistService.sharePlaylist(uid, playlistId, friendUid);
  }

  Future<void> addTrackToPlaylist(String uid, String playlistId, TrackModel track) async {
    await _playlistService.addTrackToPlaylist(uid, playlistId, track);
  }

  Future<void> syncPlaylistTracks(String uid, String playlistId, List<TrackModel> tracks) async {
    await _playlistService.updatePlaylistTracks(uid, playlistId, tracks);
    final idx = _playlists.indexWhere((p) => p.id == playlistId);
    if (idx >= 0) {
      _playlists[idx].tracks = tracks;
      _playlists[idx].lastTrackSync = DateTime.now();
      await _saveCachedPlaylists();
      notifyListeners();
    }
  }

  void setCurrentPlaylist(PlaylistModel? playlist) {
    _currentPlaylist = playlist;
    notifyListeners();
  }

  PlaylistModel createCustomPlaylist(String name, String creatorUid) {
    return PlaylistModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      creatorUid: creatorUid,
      isCustom: true,
    );
  }
}
