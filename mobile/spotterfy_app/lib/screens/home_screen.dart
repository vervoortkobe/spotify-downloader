import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/widgets/playlist_card.dart';
import 'package:spotterfy_app/screens/playlist_detail_screen.dart';
import 'package:spotterfy_app/screens/admin_screen.dart';
import 'package:spotterfy_app/screens/jam_screen.dart';
import 'package:spotterfy_app/screens/login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';

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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _syncSpotifyPlaylists(AuthProvider auth, PlaylistProvider playlistProv) async {
    final profileUrl = auth.user!.spotifyProfileUrl;
    if (profileUrl.isEmpty) return;

    final playlists = await ApiService.scrapeUserPlaylists(profileUrl);
    if (!mounted || playlists == null) return;

    for (final p in playlists) {
      final playlistId = p['id'] as String;
      final playlistUrl = 'https://open.spotify.com/playlist/$playlistId';
      final remoteTrackCount = p['trackCount'] as int? ?? 0;
      final remoteName = p['name'] as String? ?? '';

      final existing = playlistProv.getPlaylistByUrl(playlistUrl);
      if (existing == null) {
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
            lastTrackSync: DateTime.now(),
          );
          await playlistProv.savePlaylist(auth.user!.uid, enriched);
        }
      } else {
        // Detect if playlist changed on Spotify (track count, name, or empty)
        final bool changed = (remoteTrackCount > 0 && existing.tracks.length != remoteTrackCount) ||
            (remoteName.isNotEmpty && existing.name != remoteName) ||
            existing.tracks.isEmpty;

        if (changed) {
          final scraped = await ApiService.scrapePlaylist(playlistUrl);
          if (scraped != null && scraped.tracks.isNotEmpty) {
            existing.name = scraped.name;
            existing.tracks = scraped.tracks;
            if (scraped.tracks.isNotEmpty) {
              existing.coverUrl = scraped.tracks.first.cover;
            }
            existing.lastTrackSync = DateTime.now();
            await playlistProv.updatePlaylist(auth.user!.uid, existing);
          }
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
          'Spotterfy',
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
      body: Column(
        children: [
          _header(auth, playlistProv),
          Expanded(
            child: playlistProv.isLoading
                ? _loadingView()
                : RefreshIndicator(
                    onRefresh: () => _onRefresh(auth, playlistProv),
                    color: const Color(0xFF10b981),
                    backgroundColor: const Color(0xFF0f1d17),
                    child: _listView(auth, playlistProv),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _importPlaylist,
        backgroundColor: const Color(0xFF10b981),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _header(AuthProvider auth, PlaylistProvider prov) {
    final name = auth.user?.displayName.isNotEmpty == true
        ? auth.user!.displayName.split(' ').first
        : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name != null ? 'Hi, $name' : 'Your Library',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            prov.isLoading
                ? 'Loading your playlists…'
                : '${prov.playlists.length} playlist${prov.playlists.length == 1 ? '' : 's'}',
            style: const TextStyle(color: Color(0xFFa1a1aa), fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search your playlists',
              hintStyle: const TextStyle(color: Color(0xFFa1a1aa)),
              filled: true,
              fillColor: const Color(0xFF0a1410),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF10b981)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Color(0xFFa1a1aa)),
                      onPressed: () => setState(() => _searchQuery = ''),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF1a3a2a)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF1a3a2a)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF10b981)),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingView() {
    return Center(
      child: CircularProgressIndicator(
        color: const Color(0xFF10b981),
      ),
    );
  }

  List<PlaylistModel> _filtered(PlaylistProvider prov) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return prov.playlists;
    return prov.playlists
        .where((p) => p.name.toLowerCase().contains(q))
        .toList();
  }

  Widget _emptyState(PlaylistProvider prov) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.library_music_outlined,
              color: Color(0xFFa1a1aa),
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'No playlists yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap + to import a Spotify, YouTube, or SoundCloud playlist',
              style: TextStyle(color: Color(0xFFa1a1aa), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _importPlaylist,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Import Playlist',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10b981),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, color: Color(0xFFa1a1aa), size: 56),
            const SizedBox(height: 16),
            const Text(
              'No matches',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No playlists match "$_searchQuery"',
              style: const TextStyle(color: Color(0xFFa1a1aa), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _searchQuery = ''),
              child: const Text('Clear search',
                  style: TextStyle(color: Color(0xFF10b981))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listView(AuthProvider auth, PlaylistProvider prov) {
    final filtered = _filtered(prov);
    if (prov.playlists.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [_emptyState(prov)],
      );
    }
    if (filtered.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [_noResults()],
      );
    }
    return RawScrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      trackVisibility: false,
      thickness: 4,
      radius: const Radius.circular(8),
      thumbColor: const Color(0xFF10b981).withValues(alpha: 0.5),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          final p = filtered[i];
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
      ),
    );
  }

  Future<void> _onRefresh(AuthProvider auth, PlaylistProvider prov) async {
    if (auth.user != null) {
      await prov.loadPlaylists(auth.user!.uid, forceRefresh: true);
      if (auth.user!.spotifyProfileUrl.isNotEmpty && mounted) {
        await _syncSpotifyPlaylists(auth, prov);
      }
    }
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

                       final existing = prov.getPlaylistByUrl(url);
                       debugPrint('Import: existing playlist = ${existing?.name ?? "none"}');

                       final playlist = await prov.importFromUrl(
                         url,
                         service: _service,
                         creatorUid: auth.user?.uid,
                       );
                       if (!context.mounted) return;
                       setState(() => _loading = false);
                        if (playlist != null) {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            if (existing != null) {
                              final bool hadChanges = existing.tracks.length != playlist.tracks.length ||
                                  existing.name != playlist.name;
                              existing.name = playlist.name;
                              existing.tracks = playlist.tracks;
                              if (playlist.tracks.isNotEmpty) {
                                existing.coverUrl = playlist.tracks.first.cover;
                              }
                              existing.lastTrackSync = DateTime.now();
                              await prov.updatePlaylist(auth.user!.uid, existing);
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(hadChanges
                                      ? 'Playlist updated (${playlist.tracks.length} tracks)'
                                      : 'Playlist is already up to date (${playlist.tracks.length} tracks)'),
                                ),
                              );
                            } else {
                              debugPrint('Import: calling savePlaylist for new playlist');
                              await prov.savePlaylist(auth.user!.uid, playlist);
                              debugPrint('Import: savePlaylist returned');
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Imported "${playlist.name}" (${playlist.tracks.length} tracks)'),
                                ),
                              );
                            }
                          } catch (e) {
                            if (!context.mounted) return;
                            messenger.showSnackBar(
                              SnackBar(content: Text('Import failed: $e')),
                            );
                          }
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
