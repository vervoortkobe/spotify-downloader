// ignore_for_file: unnecessary_underscores
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/playlist_detail_screen.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/widgets/base_page.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  // Required Spotify URLs for Discover placeholders
  static const _genreUrls = [
    "https://open.spotify.com/playlist/37i9dQZF1DX1kfybUJZB6S?si=85f8b85180e040cc",
    "https://open.spotify.com/playlist/37i9dQZF1DWWSuZL7uNdVA?si=36f04acd51f04d90",
    "https://open.spotify.com/playlist/37i9dQZF1EIdZFdTlGR1gX?si=4a89868b2aff4f13",
    "https://open.spotify.com/playlist/37i9dQZF1EIdDyy28MYSyS?si=d1f12c5fb5c84e69",
    "https://open.spotify.com/playlist/37i9dQZF1EQfqRaYoWBGEg?si=bda257ead902463e",
  ];
  static const _artistUrls = [
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO37wTNS?si=d30ba68980f8411d",
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO0PRpBu?si=c4dc443bd3b14107",
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO0lhGr6?si=c2960a61f7134cb2",
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO2O09Hg?si=7056b2b4c9a44633",
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO3tjkZi?si=6bdf9e673dfb4f3c",
  ];

  static const _genreFallbackNames = [
    'Top Hits',
    'Mood Booster',
    'All Out 80s',
    'Rock Classics',
    'Pop Rising',
  ];
  static const _artistFallbackNames = [
    'This Is Artist Mix 1',
    'This Is Artist Mix 2',
    'This Is Artist Mix 3',
    'This Is Artist Mix 4',
    'This Is Artist Mix 5',
  ];

  List<PlaylistModel> _genrePlaylists = [];
  List<PlaylistModel> _artistPlaylists = [];
  bool _loadingGenres = true;
  bool _loadingArtists = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() => _query = _searchController.text.trim().toLowerCase()));
    _loadDiscoverPlaylists();
  }

  Future<void> _loadDiscoverPlaylists() async {
    // Load genres and artists in parallel
    await Future.wait([_loadGenrePlaylists(), _loadArtistPlaylists()]);
  }

  Future<void> _loadGenrePlaylists() async {
    setState(() => _loadingGenres = true);
    final results = await Future.wait(_genreUrls.asMap().entries.map((e) async {
      final idx = e.key;
      final url = e.value;
      try {
        final scraped = await ApiService.scrapePlaylist(url);
        if (scraped != null) {
          // Use scraped data, keep original spotifyUrl for identity
          return scraped;
        }
      } catch (_) {}
      // Fallback placeholder if scrape fails / offline
      return PlaylistModel(
        id: url.hashCode.toString(),
        name: _genreFallbackNames[idx % _genreFallbackNames.length],
        coverUrl: '',
        tracks: [],
        creatorUid: 'placeholder_discover',
        source: 'spotify',
        spotifyUrl: url,
      );
    }));
    if (!mounted) return;
    setState(() {
      _genrePlaylists = results;
      _loadingGenres = false;
    });
  }

  Future<void> _loadArtistPlaylists() async {
    setState(() => _loadingArtists = true);
    final results = await Future.wait(_artistUrls.asMap().entries.map((e) async {
      final idx = e.key;
      final url = e.value;
      try {
        final scraped = await ApiService.scrapePlaylist(url);
        if (scraped != null) return scraped;
      } catch (_) {}
      return PlaylistModel(
        id: url.hashCode.toString(),
        name: _artistFallbackNames[idx % _artistFallbackNames.length],
        coverUrl: '',
        tracks: [],
        creatorUid: 'placeholder_discover',
        source: 'spotify',
        spotifyUrl: url,
      );
    }));
    if (!mounted) return;
    setState(() {
      _artistPlaylists = results;
      _loadingArtists = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BasePageScaffold(
      searchController: _searchController,
      searchHint: 'Search Discover',
      query: _query,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section(context, 'Top genres', _genrePlaylists, _query, isLoading: _loadingGenres),
            _section(context, 'Top artists', _artistPlaylists, _query, isLoading: _loadingArtists),
            _otherUsersSection(context, _query),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<PlaylistModel> data, String query, {bool isLoading = false}) {
    if (isLoading && data.isEmpty) {
      // Shimmer-like placeholder while scraping
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [Text(title, style: TextStyle(color: SpotterfyTheme.text, fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(width: 6), Icon(Icons.chevron_right, color: SpotterfyTheme.muted, size: 18)]),
          ),
          SizedBox(
            height: 170,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 5,
              itemBuilder: (_, i) => Container(
                width: 140,
                margin: EdgeInsets.only(right: i == 4 ? 0 : 12),
                decoration: BoxDecoration(color: SpotterfyTheme.card, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(height: 110, decoration: BoxDecoration(color: SpotterfyTheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(12)))),
                  Padding(padding: const EdgeInsets.all(8), child: Container(height: 12, width: 90, decoration: BoxDecoration(color: SpotterfyTheme.surface, borderRadius: BorderRadius.circular(6)))),
                ]),
              ),
            ),
          ),
        ],
      );
    }
    var filtered = data;
    if (query.isNotEmpty) filtered = data.where((p) => p.name.toLowerCase().contains(query)).toList();
    final display = filtered.take(5).toList();
    if (display.isEmpty && query.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [Text(title, style: TextStyle(color: SpotterfyTheme.text, fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(width: 6), Icon(Icons.chevron_right, color: SpotterfyTheme.muted, size: 18)]),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('No matches for "$query"', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12))),
        ],
      );
    }
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

  // Placeholders for "Other users" when none exist – never show own playlists
  List<PlaylistModel> get _otherUsersPlaceholders => List.generate(5, (i) => PlaylistModel(
        id: 'other_placeholder_$i',
        name: ['Community Picks', 'Late Night Mix', 'Chill Discovery', 'Viral Vault', 'Fresh Finds'][i % 5],
        coverUrl: '',
        tracks: [],
        creatorUid: 'placeholder_other',
        source: 'spotify',
      ));

  Widget _otherUsersSection(BuildContext context, String query) {
    final prov = context.watch<PlaylistProvider>();
    final auth = context.watch<AuthProvider>();
    // Strictly other users – never show own playlists
    var list = prov.playlists.where((p) => p.creatorUid != auth.user?.uid && p.creatorUid.isNotEmpty).toList();
    list.sort((a, b) => (b.lastTrackSync ?? b.createdAt).compareTo(a.lastTrackSync ?? a.createdAt));
    final bool isPlaceholder = list.isEmpty;
    if (isPlaceholder) {
      list = _otherUsersPlaceholders;
    }
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      list = list.where((p) => p.name.toLowerCase().contains(q)).toList();
    }
    final display = list.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: GestureDetector(
            onTap: () {
              // Don't navigate to grid if we're showing placeholders with no real data
              final realList = prov.playlists.where((p) => p.creatorUid != auth.user?.uid && p.creatorUid.isNotEmpty).toList();
              final target = realList.isEmpty ? display : realList.where((p) => query.isEmpty || p.name.toLowerCase().contains(query)).toList();
              Navigator.push(context, swipeRoute(_SectionPage(title: "Other users' playlists", playlists: target)));
            },
            child: Row(children: [Text("Other users' playlists", style: TextStyle(color: SpotterfyTheme.text, fontSize: 18, fontWeight: FontWeight.w800)), const SizedBox(width: 6), Icon(Icons.chevron_right, color: SpotterfyTheme.muted, size: 18)]),
          ),
        ),
        if (display.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('No matches for "$query"', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)))
        else
          SizedBox(
            height: 170,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: display.length,
              itemBuilder: (_, i) {
                final p = display[i];
                final bool isReal = !isPlaceholder || prov.playlists.any((r) => r.id == p.id);
                return GestureDetector(
                  onTap: () {
                    if (!isReal) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No community playlists yet – be the first to share!')));
                      return;
                    }
                    Navigator.push(context, swipeRoute(PlaylistDetailScreen(playlist: p)));
                  },
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
        if (isPlaceholder && query.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('No community playlists yet – showing suggestions', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 11, fontStyle: FontStyle.italic)),
          ),
      ],
    );
  }
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
