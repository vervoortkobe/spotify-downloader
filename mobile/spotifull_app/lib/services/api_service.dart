import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/track_model.dart';
import '../models/playlist_model.dart';

class ApiService {
  // Change this to your backend URL
  static const String _baseUrl = 'http://10.0.2.2:5000/api'; // Android emulator

  static Future<PlaylistModel?> scrapePlaylist(String url, {String service = 'auto'}) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/scrape-playlist'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'playlistUrl': url, 'service': service}),
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['event'] != 'complete') return null;

      final playlistData = data['data'] as Map<String, dynamic>;
      final tracks = (playlistData['tracks'] as List<dynamic>)
          .map((t) => TrackModel.fromJson(t as Map<String, dynamic>))
          .toList();

      return PlaylistModel(
        id: url.hashCode.toString(),
        name: playlistData['playlistName'] as String? ?? 'Playlist',
        tracks: tracks,
        creatorUid: '',
        source: service == 'auto' ? 'spotify' : service,
      );
    } catch (e) {
      debugPrint('Scrape failed: $e');
      return null;
    }
  }

  static Future<String?> streamTrack(String sourceUrl) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/stream-track'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sourceUrl': sourceUrl}),
      );
      if (response.statusCode != 200) return null;
      // Returns a redirect URL or stream URL
      return response.body;
    } catch (e) {
      debugPrint('Stream failed: $e');
      return null;
    }
  }

  static Future<List<int>?> downloadTrack(TrackModel track, {String? sourceUrlOverride}) async {
    try {
      final sourceUrl = sourceUrlOverride ?? track.sourceUrl;
      final response = await http.post(
        Uri.parse('$_baseUrl/download-track'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          ...track.toJson(),
          'sourceUrl': sourceUrl,
        }),
      );
      if (response.statusCode != 200) return null;
      return response.bodyBytes;
    } catch (e) {
      debugPrint('Download failed: $e');
      return null;
    }
  }
}
