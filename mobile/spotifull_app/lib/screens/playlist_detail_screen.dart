import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotifull_app/models/playlist_model.dart';
import 'package:spotifull_app/models/track_model.dart';
import 'package:spotifull_app/providers/player_provider.dart';
import 'package:spotifull_app/providers/auth_provider.dart';
import 'package:spotifull_app/providers/playlist_provider.dart';
import 'package:spotifull_app/widgets/track_tile.dart';
import 'package:spotifull_app/screens/player_screen.dart';

class PlaylistDetailScreen extends StatelessWidget {
  final PlaylistModel playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07110b),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(playlist.name, style: const TextStyle(color: Colors.white, fontSize: 18)),
        actions: [
          if (playlist.isCustom)
            IconButton(
              icon: const Icon(Icons.share, color: Color(0xFFa1a1aa)),
              onPressed: () => _sharePlaylist(context),
            ),
        ],
      ),
      body: playlist.tracks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.music_note_outlined, color: const Color(0xFFa1a1aa), size: 64),
                  const SizedBox(height: 16),
                  Text('No tracks', style: TextStyle(color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 8),
                  if (playlist.isCustom)
                    ElevatedButton(
                      onPressed: () => _addTrack(context),
                      child: Text('Add tracks from your library'),
                    ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: playlist.tracks.length,
              itemBuilder: (_, i) {
                final track = playlist.tracks[i];
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
    player.setQueue(playlist.tracks, startIndex: index);
    player.play(track, queue: playlist.tracks);
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const PlayerScreen(),
    ));
  }

  void _sharePlaylist(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;
    final prov = context.read<PlaylistProvider>();
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
