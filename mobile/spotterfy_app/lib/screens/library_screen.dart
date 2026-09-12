// ignore_for_file: unnecessary_underscores
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/playlist_card.dart';
import 'playlist_detail_screen.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/profile_screen.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() => setState(() => _query = _searchController.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotterfyTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 48,
        leading: Consumer<AuthProvider>(builder: (_, auth, __) => GestureDetector(
          onTap: () => Navigator.push(context, swipeRoute(const ProfileScreen())),
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Center(child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: SpotterfyTheme.card, width: 1.4), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 5)]), child: CircleAvatar(radius: 14, backgroundColor: SpotterfyTheme.surface, backgroundImage: (auth.user?.photoUrl.isNotEmpty ?? false) ? NetworkImage(auth.user!.photoUrl) : null, child: (auth.user?.photoUrl.isEmpty ?? true) ? Icon(Icons.person, color: SpotterfyTheme.muted, size: 16) : null))),
          ),
        )),
        title: Container(
          height: 36,
          decoration: BoxDecoration(color: SpotterfyTheme.card, borderRadius: BorderRadius.circular(18)),
          child: TextField(
            controller: _searchController,
            style: TextStyle(color: SpotterfyTheme.text, fontSize: 14),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search, color: SpotterfyTheme.muted, size: 18),
              prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 36),
              hintText: 'Search playlists or storage',
              hintStyle: TextStyle(color: SpotterfyTheme.muted, fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              isDense: true,
              suffixIcon: _query.isNotEmpty ? IconButton(icon: Icon(Icons.clear, color: SpotterfyTheme.muted, size: 16), onPressed: () => _searchController.clear(), padding: EdgeInsets.zero, constraints: const BoxConstraints()) : null,
            ),
          ),
        ),
        titleSpacing: 8,
        actions: [
          AnimatedBuilder(
            animation: _tabController,
            builder: (_, __) => _tabController.index == 0
                ? IconButton(icon: Icon(Icons.add, color: SpotterfyTheme.muted, size: 20), onPressed: () => _showImportSheet(context), padding: EdgeInsets.zero, constraints: const BoxConstraints())
                : const SizedBox(width: 8),
          ),
          const SizedBox(width: 12),
        ],
      ),
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
    if (list.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.library_music, size: 48, color: SpotterfyTheme.muted),
          const SizedBox(height: 12),
          Text(_query.isNotEmpty ? 'No matches' : 'No playlists yet', style: TextStyle(color: SpotterfyTheme.text, fontWeight: FontWeight.w600)),
          if (_query.isNotEmpty) TextButton(onPressed: () => _searchController.clear(), child: Text('Clear search', style: TextStyle(color: SpotterfyTheme.primary))),
        ]),
      );
    }
    return ListView.builder(
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
                ElevatedButton(onPressed: () async { await [Permission.audio, Permission.storage].request(); (context as Element).markNeedsBuild(); }, child: const Text('Grant')),
                TextButton(onPressed: openAppSettings, child: Text('Open settings', style: TextStyle(color: SpotterfyTheme.primary))),
              ]),
            ),
          );
        }
        return FutureBuilder<List<FileSystemEntity>>(
          future: _listMusicFiles(),
          builder: (context, s) {
            if (!s.hasData) return Center(child: CircularProgressIndicator(color: SpotterfyTheme.primary));
            var files = s.data!;
            if (_query.isNotEmpty) {
              files = files.where((f) => f.path.toLowerCase().contains(_query)).toList();
            }
            if (files.isEmpty) return Center(child: Text(_query.isNotEmpty ? 'No matches' : 'No local music found', style: TextStyle(color: SpotterfyTheme.muted)));
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: files.length,
              itemBuilder: (_, i) {
                final f = files[i];
                final name = f.path.split('/').last;
                return ListTile(
                  leading: Container(width: 48, height: 48, decoration: BoxDecoration(color: SpotterfyTheme.surface, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.audio_file, color: SpotterfyTheme.primary)),
                  title: Text(name, style: TextStyle(color: SpotterfyTheme.text, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(f.path, style: TextStyle(color: SpotterfyTheme.muted, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<bool> _hasStoragePerm() async => await Permission.audio.isGranted || await Permission.storage.isGranted;
  Future<List<FileSystemEntity>> _listMusicFiles() async {
    final dirs = <Directory>[];
    for (final p in ['/storage/emulated/0/Music', '/storage/emulated/0/Download']) {
      final d = Directory(p);
      if (await d.exists()) dirs.add(d);
    }
    final all = <FileSystemEntity>[];
    for (final d in dirs) {
      try {
        final list = await d.list().toList();
        all.addAll(list.where((e) => e.path.toLowerCase().endsWith('.mp3') || e.path.toLowerCase().endsWith('.m4a') || e.path.toLowerCase().endsWith('.opus')));
      } catch (_) {}
    }
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