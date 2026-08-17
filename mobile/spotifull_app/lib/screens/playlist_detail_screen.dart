import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotifull_app/models/playlist_model.dart';
import 'package:spotifull_app/models/track_model.dart';
import 'package:spotifull_app/providers/player_provider.dart';
import 'package:spotifull_app/providers/auth_provider.dart';
import 'package:spotifull_app/providers/playlist_provider.dart';
import 'package:spotifull_app/services/api_service.dart';
import 'package:spotifull_app/widgets/track_tile.dart';
import 'package:spotifull_app/screens/player_screen.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final PlaylistModel playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  late PlaylistModel _playlist;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _playlist = widget.playlist;
    _maybeSyncTracks();
  }

  Future<void> _maybeSyncTracks() async {
    if (_playlist.source != 'spotify' || _playlist.isCustom) return;

    final needsSync = _playlist.lastTrackSync == null ||
        DateTime.now().difference(_playlist.lastTrackSync!).inMinutes >= 5;

    if (!needsSync) return;

    setState(() => _syncing = true);

    final playlistUrl = 'https://open.spotify.com/playlist/${_playlist.id}';
    final scraped = await ApiService.scrapePlaylist(playlistUrl);

    if (!mounted) return;

    if (scraped != null && scraped.tracks.isNotEmpty) {
      setState(() {
        _playlist.tracks = scraped.tracks;
        _playlist.lastTrackSync = DateTime.now();
        _syncing = false;
      });

      final auth = context.read<AuthProvider>();
      if (auth.user != null) {
        await context.read<PlaylistProvider>().syncPlaylistTracks(
          auth.user!.uid,
          _playlist.id,
          scraped.tracks,
        );
      }
    } else {
      setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07110b),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_playlist.name, style: const TextStyle(color: Colors.white, fontSize: 18)),
        actions: [
          if (_syncing)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2, color: const Color(0xFF10b981),
                ),
              ),
            ),
          if (_playlist.isCustom)
            IconButton(
              icon: const Icon(Icons.share, color: Color(0xFFa1a1aa)),
              onPressed: () => _sharePlaylist(context),
            ),
        ],
      ),
      body: _playlist.tracks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.music_note_outlined, color: const Color(0xFFa1a1aa), size: 64),
                  const SizedBox(height: 16),
                  Text('No tracks', style: TextStyle(color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 8),
                  if (_playlist.isCustom)
                    ElevatedButton(
                      onPressed: () => _addTrack(context),
                      child: Text('Add tracks from your library'),
                    ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: _playlist.tracks.length,
              itemBuilder: (_, i) {
                final track = _playlist.tracks[i];
                return TrackTile(
                  track: track,
                  onPlay: () => _playTrack(context, track, i),
                );
              },
            ),
    );
  }

  void _playTrack(BuildContext context, TrackModel track, int index) {
    final player = context.read<PlayerProvider>();
    player.setQueue(_playlist.tracks, startIndex: index);
    player.play(track, queue: _playlist.tracks);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const PlayerScreen(),
    ));
  }

  void _sharePlaylist(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Share feature coming soon')),
    );
  }

  void _addTrack(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Add track feature coming soon')),
    );
  }
}
