// ignore_for_file: unnecessary_underscores
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/profile_screen.dart';
import 'package:spotterfy_app/screens/playlist_detail_screen.dart';
import 'package:spotterfy_app/models/playlist_model.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() => _query = _searchController.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
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
          child: Padding(padding: const EdgeInsets.only(left: 10), child: Center(child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: SpotterfyTheme.card, width: 1.4), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 5)]), child: CircleAvatar(radius: 14, backgroundColor: SpotterfyTheme.surface, backgroundImage: (auth.user?.photoUrl.isNotEmpty ?? false) ? NetworkImage(auth.user!.photoUrl) : null, child: (auth.user?.photoUrl.isEmpty ?? true) ? Icon(Icons.person, color: SpotterfyTheme.muted, size: 16) : null))),
        ))),
        titleSpacing: 8,
        title: Container(
          height: 36,
          decoration: BoxDecoration(color: SpotterfyTheme.card, borderRadius: BorderRadius.circular(18)),
          child: TextField(
            controller: _searchController,
            style: TextStyle(color: SpotterfyTheme.text, fontSize: 14),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search, color: SpotterfyTheme.muted, size: 18),
              prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 36),
              hintText: 'Search Discover',
              hintStyle: TextStyle(color: SpotterfyTheme.muted, fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              isDense: true,
              suffixIcon: _query.isNotEmpty ? IconButton(icon: Icon(Icons.clear, color: SpotterfyTheme.muted, size: 16), onPressed: () => _searchController.clear(), padding: EdgeInsets.zero, constraints: const BoxConstraints()) : null,
            ),
          ),
        ),
        actions: const [SizedBox(width: 12)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section(context, 'Top genres', _topGenres, _query),
            _section(context, 'Top artists', _topArtists, _query),
            _otherUsersSection(context, _query),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<PlaylistModel> data, String query) {
    var filtered = data;
    if (query.isNotEmpty) filtered = data.where((p) => p.name.toLowerCase().contains(query)).toList();
    final display = filtered.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: GestureDetector(
            onTap: () => Navigator.push(context, swipeRoute(_SectionPage(title: title, playlists: filtered))),
            child: Row(children: [Text(title, style: TextStyle(color: SpotterfyTheme.text, fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(width: 6), Icon(Icons.chevron_right, color: SpotterfyTheme.muted, size: 18)]),
          ),
        ),
        SizedBox(
          height: 170,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: display.length,
            itemBuilder: (_, i) {
              final p = display[i];
              return GestureDetector(
                onTap: () => Navigator.push(context, swipeRoute(PlaylistDetailScreen(playlist: p))),
                child: Container(
                  width: 140,
                  margin: EdgeInsets.only(right: i == display.length - 1 ? 0 : 12),
                  decoration: BoxDecoration(color: SpotterfyTheme.card, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), child: p.coverUrl.isNotEmpty ? Image.network(p.coverUrl, height: 110, width: 140, fit: BoxFit.cover) : Container(height: 110, color: SpotterfyTheme.surface, child: Icon(Icons.music_note, color: SpotterfyTheme.muted))),
                    Padding(padding: const EdgeInsets.all(8), child: Text(p.name, style: TextStyle(color: SpotterfyTheme.text, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _otherUsersSection(BuildContext context, String query) {
    final prov = context.watch<PlaylistProvider>();
    final auth = context.watch<AuthProvider>();
    var list = prov.playlists.where((p) => p.creatorUid != auth.user?.uid).toList();
    list.sort((a, b) => (b.lastTrackSync ?? b.createdAt).compareTo(a.lastTrackSync ?? a.createdAt));
    if (query.isNotEmpty) list = list.where((p) => p.name.toLowerCase().contains(query)).toList();
    final display = list.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: GestureDetector(
            onTap: () => Navigator.push(context, swipeRoute(_SectionPage(title: "Other users' playlists", playlists: list))),
            child: Row(children: [Text("Other users' playlists", style: TextStyle(color: SpotterfyTheme.text, fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(width: 6), Icon(Icons.chevron_right, color: SpotterfyTheme.muted, size: 18)]),
          ),
        ),
        if (display.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('No playlists from other users yet', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 13)))
        else
          SizedBox(
            height: 170,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: display.length,
              itemBuilder: (_, i) {
                final p = display[i];
                return GestureDetector(
                  onTap: () => Navigator.push(context, swipeRoute(PlaylistDetailScreen(playlist: p))),
                  child: Container(width: 140, margin: EdgeInsets.only(right: i == display.length - 1 ? 0 : 12), decoration: BoxDecoration(color: SpotterfyTheme.card, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), child: p.coverUrl.isNotEmpty ? Image.network(p.coverUrl, height: 110, width: 140, fit: BoxFit.cover) : Container(height: 110, color: SpotterfyTheme.surface, child: Icon(Icons.music_note, color: SpotterfyTheme.muted))), Padding(padding: const EdgeInsets.all(8), child: Text(p.name, style: TextStyle(color: SpotterfyTheme.text, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis))]),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  List<PlaylistModel> get _topGenres => List.generate(8, (i) => PlaylistModel(id: 'genre_$i', name: ['Hip Hop Essentials', 'Rock Classics', 'Pop Hits', 'Electronic Vibes', 'R&B Soul', 'Indie Mix', 'Jazz Lounge', 'Classical Focus'][i % 8], coverUrl: '', tracks: [], creatorUid: 'placeholder', source: 'spotify'));
  List<PlaylistModel> get _topArtists => List.generate(8, (i) => PlaylistModel(id: 'artist_$i', name: ['The Weeknd Radio', 'Taylor Swift Mix', 'Drake Essentials', 'Billie Eilish', 'Post Malone', 'Ariana Grande', 'Travis Scott', 'Dua Lipa'][i % 8], coverUrl: '', tracks: [], creatorUid: 'placeholder', source: 'spotify'));
}

class _SectionPage extends StatelessWidget {
  final String title;
  final List<PlaylistModel> playlists;
  const _SectionPage({required this.title, required this.playlists});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotterfyTheme.background,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.4),
        itemCount: playlists.length,
        itemBuilder: (_, i) {
          final p = playlists[i];
          return GestureDetector(
            onTap: () => Navigator.push(context, swipeRoute(PlaylistDetailScreen(playlist: p))),
            child: Container(decoration: BoxDecoration(color: SpotterfyTheme.card, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), child: p.coverUrl.isNotEmpty ? Image.network(p.coverUrl, fit: BoxFit.cover, width: double.infinity) : Container(color: SpotterfyTheme.surface, child: Icon(Icons.music_note, color: SpotterfyTheme.muted)))) , Padding(padding: const EdgeInsets.all(8), child: Text(p.name, style: TextStyle(color: SpotterfyTheme.text, fontWeight: FontWeight.w600, fontSize: 12), maxLines: 2))]),
            ),
          );
        },
      ),
    );
  }
}