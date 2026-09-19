import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/playlist_detail_screen.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/services/playlist_service.dart';
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
  static const _radioStations = [
    {"logo": "https://play-lh.googleusercontent.com/0IsJvPieGJZ6gvvUMWTuU-46gIPJATFX6mirRyS8YxRMFd5bR6COv7pD853HtN_bWBfOaBsn6nkenmQ_qUlViw", "name": "Radio 2 Antwerpen", "streaming_url": "https://icecast.vrtcdn.be/ra2ant-high.mp3?dist=belgiefm"},
    {"logo": "https://play-lh.googleusercontent.com/3xmVTnZ39XVejn53qNev0BODoBS-WX6yLdkcI220QCFYLxblGAHjdtlAFzTPhkfkYipQwRZP4WwFvhL_ae2cLQ", "name": "MNM", "streaming_url": "https://icecast.vrtcdn.be/mnm-high.mp3?dist=belgiefm"},
    {"logo": "https://play-lh.googleusercontent.com/pqPqoFgR_HJkb5BFw87xpDn6E174M0eQaouclw1B-JiVwDBs6I1Y_YW4a3UJ-kTWnN7rAjNkMHxwCZc06PaN", "name": "Qmusic", "streaming_url": "https://audio-streaming.qmusic.be/qmusic.mp3?aw_0_req.userConsentV2=&dist=belgiefm&gdpr=1&pname=redirect-service"},
    {"logo": "https://play-lh.googleusercontent.com/r-P2EpdnaY4rOPtGlRn8h-SGiQWhQkzX3fha5ETTT5XTrr7JXd9gk4HXz4WrFxAbfjqYX6W0V2hVEXpso7Oz=s0-br30", "name": "Studio Brussel", "streaming_url": "https://icecast.vrtcdn.be/stubru-high.mp3?dist=belgiefm"},
    {"logo": "https://play-lh.googleusercontent.com/mH1dOcR6icJHvMYumxc9vEKKtG42baoHjQ9N1-rAvElp5qQluweafMe1U9OjP8CXihwTZiFQVqA-FMJlRNErWQ", "name": "JOE", "streaming_url": "https://audio-streaming.joe.be/joe.mp3?aw_0_req.userConsentV2=&dist=belgiefm&gdpr=1&pname=redirect-service"},
    {"logo": "https://play-lh.googleusercontent.com/9uazPQF3S9NogGkV3VVJhiABPjJsHO6krSMvwf5pU9f1C4ZecYiEGnbEhspFZleZikc1uvnQPOj7TE4ovYX7", "name": "Nostalgie", "streaming_url": "https://29073.live.streamtheworld.com/NOSTALGIEWHATAFEELINGAAC.aac?dist=radioplayer&rp_source=1&__cb=45378569020822&___cb=425693790515817"},
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

  final PlaylistService _discoverService = PlaylistService();
  List<PlaylistModel> _genrePlaylists = [];
  List<PlaylistModel> _artistPlaylists = [];
  bool _loadingCache = true;
  final Set<String> _fetching = {};
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() => _query = _searchController.text.trim().toLowerCase()));
    _initConnectivity();
    _loadDiscoverFromCache();
  }

  Future<void> _initConnectivity() async {
    try {
      final res = await Connectivity().checkConnectivity();
      _isOnline = !(res.contains(ConnectivityResult.none) || res.isEmpty);
      if (mounted) setState(() {});
    } catch (_) {}
    _connSub = Connectivity().onConnectivityChanged.listen((res) {
      final online = !(res.contains(ConnectivityResult.none) || res.isEmpty);
      if (online != _isOnline && mounted) setState(() => _isOnline = online);
    });
  }

  Future<void> _loadDiscoverFromCache() async {
    setState(() => _loadingCache = true);
    try {
      final genres = await _discoverService.getDiscoverPlaylists(_genreUrls);
      final artists = await _discoverService.getDiscoverPlaylists(_artistUrls);
      if (!mounted) return;
      setState(() {
        _genrePlaylists = _mergeWithPlaceholders(_genreUrls, genres, _genreFallbackNames, isGenre: true);
        _artistPlaylists = _mergeWithPlaceholders(_artistUrls, artists, _artistFallbackNames, isGenre: false);
        _loadingCache = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _genrePlaylists = _placeholders(_genreUrls, _genreFallbackNames);
        _artistPlaylists = _placeholders(_artistUrls, _artistFallbackNames);
        _loadingCache = false;
      });
    }
  }

  List<PlaylistModel> _placeholders(List<String> urls, List<String> fallbackNames) {
    return List.generate(urls.length, (i) {
      final url = urls[i].split('?').first;
      return PlaylistModel(
        id: url.hashCode.toString(),
        name: fallbackNames[i % fallbackNames.length],
        coverUrl: '',
        tracks: [],
        creatorUid: 'placeholder_discover',
        source: 'spotify',
        spotifyUrl: url,
      );
    });
  }

  List<PlaylistModel> _mergeWithPlaceholders(List<String> urls, List<PlaylistModel> cached, List<String> fallbackNames, {required bool isGenre}) {
    final byUrl = {for (final p in cached) p.spotifyUrl.split('?').first: p};
    return List.generate(urls.length, (i) {
      final clean = urls[i].split('?').first;
      final hit = byUrl[clean];
      if (hit != null) return hit;
      return PlaylistModel(
        id: clean.hashCode.toString(),
        name: fallbackNames[i % fallbackNames.length],
        coverUrl: '',
        tracks: [],
        creatorUid: 'placeholder_discover',
        source: 'spotify',
        spotifyUrl: clean,
      );
    });
  }

  Future<void> _playRadioStation(Map<String, String> station) async {
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Radio requires internet connection')));
      return;
    }
    final playerProv = context.read<PlayerProvider>();
    final track = TrackModel(
      id: 'radio_${station['name']!.replaceAll(' ', '_').toLowerCase()}',
      title: station['name']!,
      artists: 'Live Radio',
      album: 'Radio',
      cover: station['logo']!,
      sourceUrl: station['streaming_url']!,
    );
    await playerProv.play(track);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playing ${station['name']}')));
  }

  Future<void> _openDiscoverPlaylist(BuildContext context, PlaylistModel p) async {
    if (p.tracks.isNotEmpty) {
      if (!context.mounted) return;
      Navigator.push(context, swipeRoute(PlaylistDetailScreen(playlist: p)));
      return;
    }
    final url = p.spotifyUrl.split('?').first;
    if (url.isEmpty) return;
    if (_fetching.contains(url)) return;
    setState(() => _fetching.add(url));
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(const SnackBar(content: Text('Loading playlist…'), duration: Duration(seconds: 2)));
    try {
      final fresh = await _discoverService.fetchDiscoverPlaylistWithCache(
        url,
        fetcher: () => ApiService.scrapePlaylist(url),
      );
      if (!mounted) return;
      setState(() => _fetching.remove(url));
      if (fresh == null) {
        scaffold.showSnackBar(const SnackBar(content: Text('Failed to load playlist. Try again later.')));
        return;
      }
      setState(() {
        final gIdx = _genrePlaylists.indexWhere((e) => e.spotifyUrl.split('?').first == url);
        if (gIdx >= 0) _genrePlaylists[gIdx] = fresh;
        final aIdx = _artistPlaylists.indexWhere((e) => e.spotifyUrl.split('?').first == url);
        if (aIdx >= 0) _artistPlaylists[aIdx] = fresh;
      });
      if (!context.mounted) return;
      Navigator.push(context, swipeRoute(PlaylistDetailScreen(playlist: fresh)));
    } catch (e) {
      if (mounted) setState(() => _fetching.remove(url));
      scaffold.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
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
            _section(context, 'Top Genres', _genrePlaylists, _query, isLoading: _loadingCache, clickableTitle: false),
            _section(context, 'Top Artists', _artistPlaylists, _query, isLoading: _loadingCache, clickableTitle: false),
            _radioSection(context, _query),
            _otherUsersSection(context, _query),
          ],
        ),
      ),
    );
  }

  Widget _radioSection(BuildContext context, String query) {
    if (!_isOnline) return const SizedBox.shrink();
    const cardW = 110.0;
    const coverH = 92.0;
    const listH = 144.0;
    var stations = _radioStations;
    if (query.isNotEmpty) {
      stations = stations.where((s) => s['name']!.toLowerCase().contains(query)).toList();
      if (stations.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 8), child: Text('Radio Stations', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('No matches for "$query"', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12))),
          ],
        );
      }
    }
    final display = stations.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 8), child: Text('Radio Stations', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))),
        SizedBox(
          height: listH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: display.length,
            itemBuilder: (_, i) {
              final s = display[i];
              return GestureDetector(
                onTap: () => _playRadioStation(s),
                child: Container(
                  width: cardW,
                  margin: EdgeInsets.only(right: i == display.length - 1 ? 0 : 10),
                  decoration: BoxDecoration(color: SpotterfyTheme.card, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      child: Image.network(s['logo']!, height: coverH, width: cardW, fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(height: coverH, color: SpotterfyTheme.surface, child: const Center(child: Icon(Icons.radio, color: Colors.white70)))),
                    ),
                    Padding(padding: const EdgeInsets.all(7), child: Text(s['name']!, style: TextStyle(color: SpotterfyTheme.text, fontSize: 11, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String title, List<PlaylistModel> data, String query, {bool isLoading = false, bool clickableTitle = true}) {
    // Smaller cards to fit extra Radio row
    const cardW = 110.0;
    const coverH = 92.0;
    const listH = 144.0;
    if (isLoading && data.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(children: [Text(title, style: TextStyle(color: SpotterfyTheme.text, fontSize: 17, fontWeight: FontWeight.w800)), if (clickableTitle) ...[const SizedBox(width: 6), Icon(Icons.chevron_right, color: SpotterfyTheme.muted, size: 18)]]),
          ),
          SizedBox(
            height: listH,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 5,
              itemBuilder: (_, i) => Container(
                width: cardW,
                margin: EdgeInsets.only(right: i == 4 ? 0 : 10),
                decoration: BoxDecoration(color: SpotterfyTheme.card, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(height: coverH, decoration: BoxDecoration(color: SpotterfyTheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(12)))),
                  Padding(padding: const EdgeInsets.all(8), child: Container(height: 10, width: 80, decoration: BoxDecoration(color: SpotterfyTheme.surface, borderRadius: BorderRadius.circular(6)))),
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(children: [Text(title, style: TextStyle(color: SpotterfyTheme.text, fontSize: 17, fontWeight: FontWeight.w800)), if (clickableTitle) ...[const SizedBox(width: 6), Icon(Icons.chevron_right, color: SpotterfyTheme.muted, size: 18)]]),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('No matches for "$query"', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12))),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: clickableTitle
              ? GestureDetector(
                  onTap: () => Navigator.push(context, swipeRoute(_SectionPage(title: title, playlists: filtered, onTap: (p) => _openDiscoverPlaylist(context, p)))),
                  child: Row(children: [Text(title, style: TextStyle(color: SpotterfyTheme.text, fontSize: 17, fontWeight: FontWeight.w800)), const SizedBox(width: 6), Icon(Icons.chevron_right, color: SpotterfyTheme.muted, size: 18)]),
                )
              : Row(children: [Text(title, style: TextStyle(color: SpotterfyTheme.text, fontSize: 17, fontWeight: FontWeight.w800))]),
        ),
        SizedBox(
          height: listH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: display.length,
            itemBuilder: (_, i) {
              final p = display[i];
              final isFetching = _fetching.contains(p.spotifyUrl.split('?').first);
              return GestureDetector(
                onTap: () => _openDiscoverPlaylist(context, p),
                child: Container(
                  width: cardW,
                  margin: EdgeInsets.only(right: i == display.length - 1 ? 0 : 10),
                  decoration: BoxDecoration(color: SpotterfyTheme.card, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      child: Stack(children: [
                        p.coverUrl.isNotEmpty
                            ? Image.network(p.coverUrl, height: coverH, width: cardW, fit: BoxFit.cover)
                            : Container(height: coverH, color: SpotterfyTheme.surface, child: Center(child: Icon(title == 'Radio Stations' ? Icons.radio : Icons.music_note, color: SpotterfyTheme.muted, size: 22))),
                        if (isFetching) Container(height: coverH, width: cardW, color: Colors.black38, child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))),
                      ]),
                    ),
                    Padding(padding: const EdgeInsets.all(7), child: Text(p.name, style: TextStyle(color: SpotterfyTheme.text, fontSize: 11, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis)),
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
    const cardW = 110.0;
    const coverH = 92.0;
    const listH = 144.0;
    final prov = context.watch<PlaylistProvider>();
    final auth = context.watch<AuthProvider>();
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
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: GestureDetector(
              onTap: () {
                final realList = prov.playlists.where((p) => p.creatorUid != auth.user?.uid && p.creatorUid.isNotEmpty).toList();
                final target = realList.isEmpty ? display : realList.where((p) => query.isEmpty || p.name.toLowerCase().contains(query)).toList();
                Navigator.push(context, swipeRoute(_SectionPage(title: "New Playlists", playlists: target, onTap: (p) => Navigator.push(context, swipeRoute(PlaylistDetailScreen(playlist: p))))));
              },
              child: Row(children: [Text("New Playlists", style: TextStyle(color: SpotterfyTheme.text, fontSize: 17, fontWeight: FontWeight.w800)), const SizedBox(width: 6), Icon(Icons.chevron_right, color: SpotterfyTheme.muted, size: 18)]),
            ),
        ),
        if (display.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('No matches for "$query"', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)))
        else
          SizedBox(
            height: listH,
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
                    width: cardW,
                    margin: EdgeInsets.only(right: i == display.length - 1 ? 0 : 10),
                    decoration: BoxDecoration(color: SpotterfyTheme.card, borderRadius: BorderRadius.circular(12)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), child: p.coverUrl.isNotEmpty ? Image.network(p.coverUrl, height: coverH, width: cardW, fit: BoxFit.cover) : Container(height: coverH, color: SpotterfyTheme.surface, child: Center(child: Icon(Icons.music_note, color: SpotterfyTheme.muted)))),
                      Padding(padding: const EdgeInsets.all(7), child: Text(p.name, style: TextStyle(color: SpotterfyTheme.text, fontSize: 11, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis)),
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
  final Future<void> Function(PlaylistModel)? onTap;
  const _SectionPage({required this.title, required this.playlists, this.onTap});

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
            onTap: () async {
              if (onTap != null) {
                await onTap!(p);
              } else {
                Navigator.push(context, swipeRoute(PlaylistDetailScreen(playlist: p)));
              }
            },
            child: Container(decoration: BoxDecoration(color: SpotterfyTheme.card, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), child: p.coverUrl.isNotEmpty ? Image.network(p.coverUrl, fit: BoxFit.cover, width: double.infinity) : Container(color: SpotterfyTheme.surface, child: Center(child: Icon(Icons.music_note, color: SpotterfyTheme.muted))))), Padding(padding: const EdgeInsets.all(8), child: Text(p.name, style: TextStyle(color: SpotterfyTheme.text, fontWeight: FontWeight.w600, fontSize: 12), maxLines: 2))]),
            ),
          );
        },
      ),
    );
  }
}
