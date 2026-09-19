import 'dart:io';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/animated_equalizer.dart';
import 'package:spotterfy_app/widgets/playlist_card.dart';
import 'playlist_detail_screen.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/widgets/base_page.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _query = '';
  String? _openedFolderPath;
  final Map<String, Uint8List?> _coverCache = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _searchController.addListener(() => setState(() => _query = _searchController.text.trim().toLowerCase()));
    // Auto-sync playlists: show cache instantly, then fetch remote.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensurePlaylistsLoaded();
    });
  }

  Future<void> _ensurePlaylistsLoaded() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final prov = context.read<PlaylistProvider>();
    if (auth.user != null && prov.playlists.isEmpty && !prov.isLoading) {
      await prov.loadPlaylists(auth.user!.uid);
    }
  }

  Future<void> _onRefreshPlaylists() async {
    final auth = context.read<AuthProvider>();
    final prov = context.read<PlaylistProvider>();
    if (auth.user != null) {
      await prov.loadPlaylists(auth.user!.uid, forceRefresh: true);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BasePageScaffold(
      searchController: _searchController,
      searchHint: 'Search playlists or storage',
      query: _query,
      // Extra trailing icon for Library: + to import (visible only on Playlists tab) -> Storage has no icon so search bar uses full width like Discover/Search
      action: _tabController.index == 0
          ? IconButton(
              icon: Icon(Icons.add, color: SpotterfyTheme.muted, size: 20),
              onPressed: () => _showImportSheet(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            )
          : null,
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: SpotterfyTheme.muted,
            indicatorColor: SpotterfyTheme.primary,
            dividerColor: Colors.transparent,
            tabs: const [Tab(text: 'Playlists'), Tab(text: 'Storage')],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _playlistsTab(context.watch<PlaylistProvider>()),
                _storageTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _playlistsTab(PlaylistProvider prov) {
    var list = prov.playlists;
    if (_query.isNotEmpty) {
      list = list.where((p) => p.name.toLowerCase().contains(_query) || p.tracks.any((t) => t.title.toLowerCase().contains(_query))).toList();
    }
    // Show loading spinner over cache while first sync runs
    if (prov.isLoading && prov.playlists.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: SpotterfyTheme.primary));
    }
    if (list.isEmpty) {
      return RefreshIndicator(
        onRefresh: _onRefreshPlaylists,
        color: SpotterfyTheme.primary,
        backgroundColor: SpotterfyTheme.surface,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 100, top: 32),
          children: [
            Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.library_music, size: 48, color: SpotterfyTheme.muted),
                const SizedBox(height: 12),
                Text(_query.isNotEmpty ? 'No matches' : 'No playlists yet', style: TextStyle(color: SpotterfyTheme.text, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(_query.isNotEmpty ? 'Try a different search' : 'Pull down to refresh or tap + to import', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
                const SizedBox(height: 12),
                if (_query.isNotEmpty)
                  TextButton(onPressed: () => _searchController.clear(), child: Text('Clear search', style: TextStyle(color: SpotterfyTheme.primary)))
                else
                  OutlinedButton.icon(onPressed: _onRefreshPlaylists, icon: const Icon(Icons.refresh, size: 18), label: const Text('Refresh')),
              ]),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _onRefreshPlaylists,
      color: SpotterfyTheme.primary,
      backgroundColor: SpotterfyTheme.surface,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final p = list[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PlaylistCard(
              playlist: p,
              onTap: () => Navigator.push(context, swipeRoute(PlaylistDetailScreen(playlist: p))),
              onPlay: p.tracks.isEmpty ? null : () {},
            ),
          );
        },
      ),
    );
  }

  Widget _storageTab() {
    return FutureBuilder<bool>(
      future: _hasStoragePerm(),
      builder: (context, snap) {
        if (!snap.hasData) return Center(child: CircularProgressIndicator(color: SpotterfyTheme.primary));
        if (snap.data == false) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.folder_off, size: 48, color: SpotterfyTheme.muted),
                const SizedBox(height: 12),
                Text('Storage permission needed', style: TextStyle(color: SpotterfyTheme.text, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('Allow access to display downloaded songs stored on device.', textAlign: TextAlign.center, style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: () async { await [Permission.audio, Permission.storage, Permission.manageExternalStorage].request(); (context as Element).markNeedsBuild(); }, child: const Text('Grant')),
                TextButton(onPressed: openAppSettings, child: Text('Open settings', style: TextStyle(color: SpotterfyTheme.primary))),
              ]),
            ),
          );
        }
        return FutureBuilder<List<FileSystemEntity>>(
          future: _listMusicFiles(),
          builder: (context, s) {
            if (s.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: SpotterfyTheme.primary));
            if (s.hasError) return Center(child: Text('Error: ${s.error}', style: TextStyle(color: SpotterfyTheme.muted)));
            var files = (s.data ?? []).whereType<File>().toList();
            if (files.isEmpty) {
              return RefreshIndicator(
                onRefresh: () async => (context as Element).markNeedsBuild(),
                child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                  const SizedBox(height: 80),
                  Center(child: Text(_query.isNotEmpty ? 'No matches' : 'No local music found\nTip: check Music/Download subfolders', textAlign: TextAlign.center, style: TextStyle(color: SpotterfyTheme.muted))),
                ]),
              );
            }
            // Group by parent folder -> subfolders as playlists (user requested)
            final Map<String, List<File>> groups = {};
            for (final f in files) {
              final parent = File(f.path).parent.path;
              groups.putIfAbsent(parent, () => []).add(f);
            }
            // Sort folders by name
            final folderPaths = groups.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
            // Filter by query (folder name or any file in folder)
            List<String> filteredFolders = folderPaths;
            if (_query.isNotEmpty) {
              final q = _query.toLowerCase();
              filteredFolders = folderPaths.where((p) {
                final folderName = p.split('/').last.toLowerCase();
                if (folderName.contains(q)) return true;
                return groups[p]!.any((f) => f.path.toLowerCase().contains(q));
              }).toList();
            }
            // Inline folder detail (keeps MiniPlayer visible, not a new route)
            if (_openedFolderPath != null && groups.containsKey(_openedFolderPath)) {
              final folderPath = _openedFolderPath!;
              final folderFilesAll = groups[folderPath]!;
              final folderName = folderPath.split('/').last.isEmpty ? 'Music' : folderPath.split('/').last;
              var detailFiles = folderFilesAll;
              if (_query.isNotEmpty) {
                detailFiles = folderFilesAll.where((f) => f.path.toLowerCase().contains(_query.toLowerCase())).toList();
              }
              final folderTracks = detailFiles.map((f) {
                final path = f.path;
                final name = path.split('/').last.replaceAll(RegExp(r'\.(mp3|m4a|opus|flac|wav|ogg|aac)$', caseSensitive: false), '');
                return TrackModel(id: 'storage_${path.hashCode}', title: name.isEmpty ? 'Unknown' : name, artists: folderName, album: 'Local', cover: '', sourceUrl: path);
              }).toList()..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
              // Keep sorted files aligned with sorted tracks for cover lookup
              detailFiles = List<File>.from(detailFiles)..sort((a, b) => a.path.split('/').last.toLowerCase().compareTo(b.path.split('/').last.toLowerCase()));
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: Row(children: [
                    IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => setState(() => _openedFolderPath = null)),
                    Expanded(child: Text(folderName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text('${detailFiles.length} songs', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
                    const SizedBox(width: 8),
                    IconButton(icon: Icon(Icons.play_arrow_rounded, color: SpotterfyTheme.primary, size: 28), onPressed: detailFiles.isEmpty ? null : () async { await context.read<PlayerProvider>().play(folderTracks.first, queue: folderTracks); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playing $folderName'))); }),
                  ]),
                ),
                Expanded(
                  child: detailFiles.isEmpty
                      ? Center(child: Text('No matches', style: TextStyle(color: SpotterfyTheme.muted)))
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 100),
                          itemCount: detailFiles.length,
                          itemBuilder: (_, i) {
                            final f = detailFiles[i];
                            final t = folderTracks[i];
                            final isPlaying = context.watch<PlayerProvider>().currentTrack?.id == t.id;
                            return ListTile(
                              leading: _buildStorageCover(f.path, isPlaying),
                              title: Text(t.title, style: TextStyle(color: isPlaying ? SpotterfyTheme.primary : Colors.white, fontSize: 13, fontWeight: isPlaying ? FontWeight.w600 : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(folderName, style: TextStyle(color: SpotterfyTheme.muted, fontSize: 11), maxLines: 1),
                              trailing: isPlaying ? const AnimatedEqualizer(size: 18, color: SpotterfyTheme.primary) : const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                              onTap: () async { await context.read<PlayerProvider>().play(t, queue: folderTracks); },
                            );
                          },
                        ),
                ),
              ]);
            }
            if (filteredFolders.isEmpty) {
              return Center(child: Text('No matches for "$_query"', style: TextStyle(color: SpotterfyTheme.muted)));
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: filteredFolders.length,
              itemBuilder: (_, idx) {
                final folderPath = filteredFolders[idx];
                final folderFiles = groups[folderPath]!;
                final folderName = folderPath.split('/').last.isEmpty ? 'Music' : folderPath.split('/').last;
                final count = folderFiles.length;
                final folderTracks = folderFiles.map((f) {
                  final path = f.path;
                  final name = path.split('/').last.replaceAll(RegExp(r'\.(mp3|m4a|opus|flac|wav|ogg|aac)$', caseSensitive: false), '');
                  return TrackModel(id: 'storage_${path.hashCode}', title: name.isEmpty ? 'Unknown' : name, artists: folderName, album: 'Local', cover: '', sourceUrl: path);
                }).toList()..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
                final isActiveFolder = folderFiles.any((f) => context.watch<PlayerProvider>().currentTrack?.id == 'storage_${f.path.hashCode}');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _openedFolderPath = folderPath),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: isActiveFolder ? SpotterfyTheme.card : SpotterfyTheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: isActiveFolder ? SpotterfyTheme.primary.withValues(alpha: 0.6) : SpotterfyTheme.card, width: isActiveFolder ? 1.2 : 0.8)),
                      child: Row(children: [
                        Container(width: 56, height: 56, decoration: BoxDecoration(color: isActiveFolder ? SpotterfyTheme.primary.withValues(alpha: 0.15) : SpotterfyTheme.card, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.folder, color: isActiveFolder ? SpotterfyTheme.primary : SpotterfyTheme.muted, size: 28)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(folderName, style: TextStyle(color: isActiveFolder ? SpotterfyTheme.primary : SpotterfyTheme.text, fontSize: 14, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text('$count ${count == 1 ? 'song' : 'songs'} • ${folderPath.replaceFirst('/storage/emulated/0/', '')}', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ])),
                        IconButton(icon: Icon(Icons.play_arrow_rounded, color: isActiveFolder ? SpotterfyTheme.primary : SpotterfyTheme.text, size: 28), onPressed: () async { await context.read<PlayerProvider>().play(folderTracks.first, queue: folderTracks); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playing $folderName'))); }),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right, color: SpotterfyTheme.muted, size: 20),
                      ]),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<Uint8List?> _getCover(String path) async {
    if (_coverCache.containsKey(path)) return _coverCache[path];
    try {
      final meta = readMetadata(File(path), getImage: true);
      Uint8List? bytes;
      if (meta.pictures.isNotEmpty) bytes = meta.pictures.first.bytes;
      _coverCache[path] = bytes;
      return bytes;
    } catch (_) {
      _coverCache[path] = null;
      return null;
    }
  }

  Widget _buildStorageCover(String path, bool isPlaying) {
    return FutureBuilder<Uint8List?>(
      future: _getCover(path),
      builder: (_, snap) {
        if (snap.hasData && snap.data != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(snap.data!, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Container(width: 48, height: 48, color: SpotterfyTheme.surface, child: Icon(Icons.audio_file, color: SpotterfyTheme.muted))),
          );
        }
        return Container(width: 48, height: 48, decoration: BoxDecoration(color: isPlaying ? SpotterfyTheme.primary.withValues(alpha: 0.2) : SpotterfyTheme.surface, borderRadius: BorderRadius.circular(8), border: isPlaying ? Border.all(color: SpotterfyTheme.primary, width: 1.2) : null), child: Icon(Icons.audio_file, color: isPlaying ? SpotterfyTheme.primary : SpotterfyTheme.muted));
      },
    );
  }

  Future<bool> _hasStoragePerm() async {
    // Android 13+ needs audio, 11+ may need manageExternalStorage for full scan
    try {
      if (await Permission.audio.isGranted) return true;
      if (await Permission.storage.isGranted) return true;
      if (await Permission.manageExternalStorage.isGranted) return true;
    } catch (_) {}
    return false;
  }

  Future<List<FileSystemEntity>> _listMusicFiles() async {
    final exts = ['.mp3', '.m4a', '.opus', '.flac', '.wav', '.ogg', '.aac'];
    bool isAudio(String p) => exts.any((e) => p.toLowerCase().endsWith(e));
    final candidates = <String>[
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Documents',
    ];
    final all = <FileSystemEntity>[];
    for (final p in candidates) {
      final d = Directory(p);
      if (!await d.exists()) continue;
      try {
        // Recursive to catch subfolders (user reported folders/songs not found)
        await for (final e in d.list(recursive: true, followLinks: false)) {
          if (e is File && isAudio(e.path)) {
            all.add(e);
            if (all.length > 800) break; // cap to avoid OOM
          }
        }
      } catch (_) {}
    }
    // Include MediaStore via best-effort fallback: if still empty, try non-recursive old path
    if (all.isEmpty) {
      for (final p in candidates.take(2)) {
        final d = Directory(p);
        if (!await d.exists()) continue;
        try {
          final list = await d.list().toList();
          all.addAll(list.where((e) => e is File && isAudio(e.path)));
        } catch (_) {}
      }
    }
    all.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    return all;
  }

  void _showImportSheet(BuildContext context) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0f1d17),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 24, right: 24, top: 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFF3f3f46), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Import playlist', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(hintText: 'Paste Spotify / YouTube / SoundCloud URL', hintStyle: TextStyle(color: const Color(0xFFa1a1aa), fontSize: 13), filled: true, fillColor: const Color(0xFF0a1410), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: const Color(0xFF1a3a2a))), prefixIcon: Icon(Icons.link, color: SpotterfyTheme.primary, size: 20)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () async {
                final url = controller.text.trim();
                if (url.isEmpty) return;
                Navigator.pop(ctx);
                final auth = context.read<AuthProvider>();
                final prov = context.read<PlaylistProvider>();
                final existing = prov.getPlaylistByUrl(url);
                if (existing != null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Already in library: ${existing.name}')));
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Importing...')));
                final playlist = await prov.importFromUrl(url);
                if (playlist != null && auth.user != null) {
                  await prov.savePlaylist(auth.user!.uid, playlist);
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported "${playlist.name}"')));
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(prov.error ?? 'Import failed')));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: SpotterfyTheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Import', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}