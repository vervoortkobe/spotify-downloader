import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotifull_app/models/playlist_model.dart';
import 'package:spotifull_app/providers/auth_provider.dart';
import 'package:spotifull_app/providers/playlist_provider.dart';
import 'package:spotifull_app/services/api_service.dart';
import 'package:spotifull_app/widgets/playlist_card.dart';
import 'package:spotifull_app/screens/playlist_detail_screen.dart';
import 'package:spotifull_app/screens/admin_screen.dart';
import 'package:spotifull_app/screens/jam_screen.dart';
import 'package:spotifull_app/screens/login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      final playlistProv = context.read<PlaylistProvider>();
      if (auth.user != null) {
        await playlistProv.loadPlaylists(auth.user!.uid);
        if (auth.needsSpotifySync && mounted) {
          await _syncSpotifyPlaylists(auth, playlistProv);
        }
      }
    });
  }

  Future<void> _syncSpotifyPlaylists(AuthProvider auth, PlaylistProvider playlistProv) async {
    final profileUrl = auth.user!.spotifyProfileUrl;
    if (profileUrl.isEmpty) return;

    final playlists = await ApiService.scrapeUserPlaylists(profileUrl);
    if (!mounted || playlists == null) return;

    for (final p in playlists) {
      final playlistId = p['id'] as String;
      final playlistUrl = 'https://open.spotify.com/playlist/$playlistId';

      if (!playlistProv.hasPlaylistWithUrl(playlistUrl)) {
        final scraped = await ApiService.scrapePlaylist(playlistUrl);
        if (scraped != null) {
          final enriched = PlaylistModel(
            id: scraped.id,
            name: scraped.name,
            owner: p['owner'] as String? ?? '',
            coverUrl: scraped.tracks.isNotEmpty ? scraped.tracks.first.cover : '',
            tracks: scraped.tracks,
            creatorUid: auth.user!.uid,
            source: 'spotify',
            spotifyUrl: playlistUrl,
            isUsersOwn: true,
          );
          await playlistProv.savePlaylist(auth.user!.uid, enriched);
        }
      }
    }

    await auth.updateSpotifyProfileUrl(auth.user!.spotifyProfileUrl);
  }

  void _importPlaylist() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0f1d17),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ImportSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final playlistProv = context.watch<PlaylistProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF07110b),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Spotifull',
          style: TextStyle(
            color: const Color(0xFF10b981),
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          if (auth.isAdmin)
            IconButton(
              icon: Icon(
                Icons.admin_panel_settings,
                color: const Color(0xFFa1a1aa),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminScreen()),
              ),
            ),
          IconButton(
            icon: Icon(Icons.groups, color: const Color(0xFFa1a1aa)),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const JamScreen()),
            ),
          ),
          IconButton(
            icon: Icon(Icons.logout, color: const Color(0xFFa1a1aa)),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF0f1d17),
                  title: const Text('Sign Out',
                      style: TextStyle(color: Colors.white)),
                  content: const Text('Are you sure?',
                      style: TextStyle(color: Color(0xFFa1a1aa))),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel',
                          style: TextStyle(color: Color(0xFFa1a1aa))),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Sign Out',
                          style: TextStyle(color: Color(0xFF10b981))),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await auth.signOut();
                if (context.mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => playlistProv.loadPlaylists(auth.user!.uid),
        child: playlistProv.isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: const Color(0xFF10b981),
                ),
              )
            : playlistProv.playlists.isEmpty
            ? _emptyState()
            : _playlistList(playlistProv),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _importPlaylist,
        backgroundColor: const Color(0xFF10b981),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.library_music_outlined,
              color: const Color(0xFFa1a1aa),
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'No playlists yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to import a Spotify, YouTube, or SoundCloud playlist',
              style: TextStyle(color: const Color(0xFFa1a1aa), fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _playlistList(PlaylistProvider prov) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: prov.playlists.length,
      itemBuilder: (_, i) {
        final p = prov.playlists[i];
        return PlaylistCard(
          playlist: p,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PlaylistDetailScreen(playlist: p),
            ),
          ),
          onDelete: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF0f1d17),
                    title: const Text('Delete Playlist',
                        style: TextStyle(color: Colors.white)),
                    content: Text('Delete "${p.name}"?',
                        style: TextStyle(color: const Color(0xFFa1a1aa))),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel',
                            style: TextStyle(color: Color(0xFFa1a1aa))),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete',
                            style: TextStyle(color: Color(0xFFef4444))),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  await prov.deletePlaylist(p.creatorUid, p.id);
                }
              },
          showDelete: true,
        );
      },
    );
  }
}

class _ImportSheet extends StatefulWidget {
  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  final _urlController = TextEditingController();
  final String _service = 'auto';
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3f3f46),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Import Playlist',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _urlController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Paste Spotify / YouTube / SoundCloud URL',
              hintStyle: TextStyle(color: const Color(0xFFa1a1aa)),
              filled: true,
              fillColor: const Color(0xFF0a1410),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: const Color(0xFF1a3a2a)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: const Color(0xFF1a3a2a)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: const Color(0xFF10b981)),
              ),
              prefixIcon: Icon(Icons.link, color: const Color(0xFF10b981)),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _loading
                  ? null
                    : () async {
                      final url = _urlController.text.trim();
                      if (url.isEmpty) return;
                      setState(() => _loading = true);
                      final auth = context.read<AuthProvider>();
                      final prov = context.read<PlaylistProvider>();

                      if (prov.hasPlaylistWithUrl(url)) {
                        if (!context.mounted) return;
                        setState(() => _loading = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Playlist already in your library'),
                          ),
                        );
                        return;
                      }

                      final playlist = await prov.importFromUrl(
                        url,
                        service: _service,
                        creatorUid: auth.user?.uid,
                      );
                      if (!context.mounted) return;
                      setState(() => _loading = false);
                      if (playlist != null) {
                        await prov.savePlaylist(auth.user!.uid, playlist);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(prov.error ?? 'Failed to import'),
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10b981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _loading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Import',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
