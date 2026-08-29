import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/widgets/track_tile.dart';
import 'package:spotterfy_app/screens/player_screen.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final PlaylistModel playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  late PlaylistModel _playlist;
  final ScrollController _scrollController = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _playlist = widget.playlist;
    _maybeSyncTracks();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _maybeSyncTracks() async {
    if (_playlist.isCustom) return;

    final needsSync = _playlist.lastTrackSync == null ||
        _playlist.tracks.isEmpty ||
        DateTime.now().difference(_playlist.lastTrackSync!).inMinutes >= 5;

    if (!needsSync) return;
    await _forceSyncTracks(showFeedback: false);
  }

  Future<void> _forceSyncTracks({bool showFeedback = true}) async {
    if (_playlist.isCustom) return;

    setState(() => _syncing = true);

    final playlistUrl = _playlist.spotifyUrl.isNotEmpty
        ? _playlist.spotifyUrl
        : 'https://open.spotify.com/playlist/${_playlist.id}';

    final scraped = await ApiService.scrapePlaylist(playlistUrl, service: _playlist.source);

    if (!mounted) return;

    if (scraped != null) {
      final int previousCount = _playlist.tracks.length;
      final bool hasChanged = previousCount != scraped.tracks.length ||
          _playlist.name != scraped.name ||
          (scraped.tracks.isNotEmpty && previousCount > 0 && scraped.tracks.first.id != _playlist.tracks.first.id);

      setState(() {
        _playlist.name = scraped.name.isNotEmpty ? scraped.name : _playlist.name;
        _playlist.tracks = scraped.tracks;
        if (scraped.tracks.isNotEmpty) {
          _playlist.coverUrl = scraped.tracks.first.cover;
        }
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

      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(hasChanged
                ? 'Playlist updated (${scraped.tracks.length} tracks)'
                : 'Playlist is up to date (${scraped.tracks.length} tracks)'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      setState(() => _syncing = false);
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to check for playlist updates')),
        );
      }
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
          if (!_playlist.isCustom)
            IconButton(
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF10b981),
                      ),
                    )
                  : const Icon(Icons.sync, color: Color(0xFFa1a1aa)),
              tooltip: 'Check for updates',
              onPressed: _syncing ? null : () => _forceSyncTracks(showFeedback: true),
            ),
          if (_playlist.isCustom)
            IconButton(
              icon: const Icon(Icons.share, color: Color(0xFFa1a1aa)),
              onPressed: () => _sharePlaylist(context),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _forceSyncTracks(showFeedback: true),
        color: const Color(0xFF10b981),
        backgroundColor: const Color(0xFF0f1d17),
        child: _playlist.tracks.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.music_note_outlined, color: Color(0xFFa1a1aa), size: 64),
                          const SizedBox(height: 16),
                          const Text('No tracks found', style: TextStyle(color: Colors.white, fontSize: 18)),
                          const SizedBox(height: 8),
                          if (_playlist.isCustom)
                            ElevatedButton(
                              onPressed: () => _addTrack(context),
                              child: const Text('Add tracks from your library'),
                            )
                          else
                            TextButton.icon(
                              onPressed: () => _forceSyncTracks(showFeedback: true),
                              icon: const Icon(Icons.refresh, color: Color(0xFF10b981)),
                              label: const Text('Fetch Tracks', style: TextStyle(color: Color(0xFF10b981))),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : RawScrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                trackVisibility: false,
                thickness: 4,
                radius: const Radius.circular(8),
                thumbColor: const Color(0xFF10b981).withValues(alpha: 0.5),
                child: ListView.builder(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
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
              ),
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
      const SnackBar(content: Text('Share feature coming soon')),
    );
  }

  void _addTrack(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add track feature coming soon')),
    );
  }
}
