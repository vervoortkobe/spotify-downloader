import 'package:flutter/material.dart';
import 'package:spotifull_app/models/playlist_model.dart';
import 'package:spotifull_app/models/track_model.dart';
import 'package:spotifull_app/services/api_service.dart';
import 'package:spotifull_app/services/playlist_service.dart';

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

  Future<void> loadPlaylists(String uid) async {
    _isLoading = true;
    notifyListeners();
    try {
      _playlists = await _playlistService.getUserPlaylists(uid);
      _sharedPlaylists = await _playlistService.getSharedPlaylists(uid);
      _error = null;
    } catch (e) {
      _error = 'Failed to load playlists';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<PlaylistModel?> importFromUrl(String url, {String service = 'auto', String? creatorUid}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final playlist = await ApiService.scrapePlaylist(url, service: service);
      if (playlist == null) {
        _error = 'Failed to fetch playlist';
        _isLoading = false;
        notifyListeners();
        return null;
      }
      _currentPlaylist = playlist;
      _isLoading = false;
      notifyListeners();
      return playlist;
    } catch (e) {
      _error = 'Error: $e';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<void> savePlaylist(String uid, PlaylistModel playlist) async {
    await _playlistService.savePlaylist(uid, playlist);
    _playlists.insert(0, playlist);
    notifyListeners();
  }

  Future<void> deletePlaylist(String uid, String playlistId) async {
    await _playlistService.deletePlaylist(uid, playlistId);
    _playlists.removeWhere((p) => p.id == playlistId);
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
