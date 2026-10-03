import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/playlist_detail_screen.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/services/firebase_service.dart';
import 'package:spotterfy_app/services/playlist_service.dart';
import 'package:spotterfy_app/widgets/base_page.dart';
import 'package:spotterfy_app/widgets/no_results_view.dart';
import 'package:spotterfy_app/widgets/track_tile.dart';

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
    "https://open.spotify.com/playlist/37i9dQZF1EIdSOY5WzY0Ah",
    "https://open.spotify.com/playlist/37i9dQZF1EIghNBbh3wJEC",
  ];

  /// Artist playlists featured on the Discover page, in display order.
  ///
  /// Order is the on-screen order, so entries are moved by editing this list
  /// rather than by any sort. Names come from the backend's discover scrape;
  /// `_artistFallbackNames` only fills in before that data lands, which is why
  /// they stay generic.
  static const _artistUrls = [
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO37wTNS?si=d30ba68980f8411d", // This Is Stromae
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO0PRpBu?si=c4dc443bd3b14107", // This Is Avicii
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO0lhGr6?si=c2960a61f7134cb2", // This Is GIMS
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO2O09Hg?si=7056b2b4c9a44633", // This Is Juice WRLD
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO3tjkZi?si=6bdf9e673dfb4f3c", // This Is Netsky
    "https://open.spotify.com/playlist/37i9dQZF1DWZUozJiHy44Y?si=68e8f43b4b3f4fb3", // This Is Adele
    "https://open.spotify.com/playlist/37i9dQZF1DX3D78h6FPBPC?si=668fb476846d4ff9", // This Is ABBA
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO1SVXaM?si=61d06e90cfef4173", // This Is Michael Jackson
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO0ENBD2?si=b8835c3da8784dfe", // This Is Queen
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO3154GY?si=81ca769127ae4000", // This Is Bon Jovi
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO3GSvAY?si=b22ab600db044f58", // This Is NF
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO0rer1m?si=0f83f0c724374979", // This Is DJ Khaled
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO3262Tm?si=c76cd2e9119e499d", // This Is Prince
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO4gTUOY?si=324e042bf1804ea5", // This Is Eminem
    "https://open.spotify.com/playlist/37i9dQZF1DX6p4TJxzMRDe?si=85f8b85180e040cc", // This Is One Direction
    // --- New additions, between One Direction and Studio 100 Tophits ---
    "https://open.spotify.com/playlist/37i9dQZF1DXaQm3ZVg9Z2X", // This Is Coldplay
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO0sQwP6", // This Is Pitbull
    "https://open.spotify.com/playlist/37i9dQZF1DX6bnzK9KPvrz", // This Is The Weeknd
    // Grouped with the electronic artists, between Coldplay and Dua Lipa.
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO4vD8f6", // This Is Calvin Harris
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO20Wzv2", // This Is Robin Schulz
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evNZY5NHq", // This Is Maroon 5
    "https://open.spotify.com/playlist/37i9dQZF1DX3fRquEp6m8D", // This Is Dua Lipa
    "https://open.spotify.com/playlist/37i9dQZF1DXc2aPBXGmXrt", // This Is Justin Bieber
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO2yPKNc", // This Is Ava Max
    "https://open.spotify.com/playlist/37i9dQZF1DX5KpP2LN299J", // This Is Taylor Swift
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO3Jefw4", // This Is Katy Perry
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO40D0nC", // This Is Clean Bandit
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO0SmMeI", // This Is Anne-Marie
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO2yXXGB", // This Is Camila Cabello
    "https://open.spotify.com/playlist/37i9dQZF1DWWxPM4nWdhyI", // This Is Ed Sheeran
    // --- End new additions ---
    "https://open.spotify.com/playlist/66U9yz0mUOyY1fd40d2iMA?si=d30ba68980f8411d", // Studio 100 Tophits
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO0FQNnk?si=XWSHlTf_RkiboFOpz0pXiQ", // This Is K3
    "https://open.spotify.com/playlist/37i9dQZF1DZ06evO1VAWw8?si=3489cec8913640f4", // This Is Bazart (moved here, between K3 and BLACKPINK)
    "https://open.spotify.com/playlist/37i9dQZF1DX8kP0ioXjxIA?si=668fb476846d4ff9", // This Is BLACKPINK
  ];
  static const _radioStations = [
    {
      "logo":
          "https://play-lh.googleusercontent.com/0IsJvPieGJZ6gvvUMWTuU-46gIPJATFX6mirRyS8YxRMFd5bR6COv7pD853HtN_bWBfOaBsn6nkenmQ_qUlViw",
      "name": "Radio 2",
      "streaming_url":
          "https://icecast.vrtcdn.be/ra2ant-high.mp3?dist=belgiefm",
    },
    {
      "logo":
          "https://play-lh.googleusercontent.com/3xmVTnZ39XVejn53qNev0BODoBS-WX6yLdkcI220QCFYLxblGAHjdtlAFzTPhkfkYipQwRZP4WwFvhL_ae2cLQ",
      "name": "MNM",
      "streaming_url": "https://icecast.vrtcdn.be/mnm-high.mp3?dist=belgiefm",
    },
    {
      "logo":
          "https://play-lh.googleusercontent.com/pqPqoFgR_HJkb5BFw87xpDn6E174M0eQaouclw1B-JiVwDBs6I1Y_YW4a3UJ-kTWnN7rAjNkMHxwCZc06PaN",
      "name": "Qmusic",
      "streaming_url":
          "https://audio-streaming.qmusic.be/qmusic.mp3?aw_0_req.userConsentV2=&dist=belgiefm&gdpr=1&pname=redirect-service",
    },
    {
      "logo":
          "https://play-lh.googleusercontent.com/r-P2EpdnaY4rOPtGlRn8h-SGiQWhQkzX3fha5ETTT5XTrr7JXd9gk4HXz4WrFxAbfjqYX6W0V2hVEXpso7Oz=s0-br30",
      "name": "Studio Brussel",
      "streaming_url":
          "https://icecast.vrtcdn.be/stubru-high.mp3?dist=belgiefm",
    },
    {
      "logo":
          "https://play-lh.googleusercontent.com/mH1dOcR6icJHvMYumxc9vEKKtG42baoHjQ9N1-rAvElp5qQluweafMe1U9OjP8CXihwTZiFQVqA-FMJlRNErWQ",
      "name": "JOE",
      "streaming_url":
          "https://audio-streaming.joe.be/joe.mp3?aw_0_req.userConsentV2=&dist=belgiefm&gdpr=1&pname=redirect-service",
    },
    {
      "logo":
          "https://play-lh.googleusercontent.com/9uazPQF3S9NogGkV3VVJhiABPjJsHO6krSMvwf5pU9f1C4ZecYiEGnbEhspFZleZikc1uvnQPOj7TE4ovYX7",
      "name": "Nostalgie",
      "streaming_url":
          "https://29073.live.streamtheworld.com/NOSTALGIEWHATAFEELINGAAC.aac?dist=radioplayer&rp_source=1&__cb=45378569020822&___cb=425693790515817",
    },
    {
      "logo":
          "https://play-lh.googleusercontent.com/MAbkJdmPo-MnwdC_f_aXlW95BhgKumRBvjxX8jJxY_Lb0kbLv6uP4BxX7208rcbxwiAb56DxPP0hofRXf1ggBQ=w240-h480-rw",
      "name": "Klara",
      "streaming_url":
          "https://vrt.streamabc.net/vrt-klara-mp3-128-1558567?sABC=6noro1o4%230%2313pnn95on49471p04q5209rqo9rp297p%23&aw_0_1st.playerid=&amsparams=playerid:;skey:1790882228",
    },
  ];

  static const _genreFallbackNames = [
    'Top Hits',
    'Mood Booster',
    'All Out 80s',
    'Rock Classics',
    'Pop Rising',
  ];

  /// Generic placeholders for artist rows whose real title has not arrived from
  /// the backend yet.
  ///
  /// The real names are known per playlist id (each entry in `_artistUrls` is a
  /// "This Is ..." editorial playlist), but this list is *positional* - it is
  /// indexed in lockstep with `_artistUrls`. Keeping one entry per url means
  /// inserting an artist cannot shift every later placeholder onto the wrong
  /// playlist, which is the failure mode a shorter modulo-cycled list would hit.
  static const _artistFallbackNames = [
    'This Is Artist Mix 1',
    'This Is Artist Mix 2',
    'This Is Artist Mix 3',
    'This Is Artist Mix 4',
    'This Is Artist Mix 5',
    'This Is Artist Mix 6',
    'This Is Artist Mix 7',
    'This Is Artist Mix 8',
    'This Is Artist Mix 9',
    'This Is Artist Mix 10',
    'This Is Artist Mix 11',
    'This Is Artist Mix 12',
    'This Is Artist Mix 13',
    'This Is Artist Mix 14',
    'This Is Artist Mix 15',
    'This Is Artist Mix 16',
    'This Is Artist Mix 17',
    'This Is Artist Mix 18',
    'This Is Artist Mix 19',
    'This Is Artist Mix 20',
    'This Is Artist Mix 20',
    'This Is Artist Mix 21',
    'This Is Artist Mix 22',
    'This Is Artist Mix 23',
    'This Is Artist Mix 24',
    'This Is Artist Mix 24',
    'This Is Artist Mix 25',
    'This Is Artist Mix 26',
    'This Is Artist Mix 27',
    'This Is Artist Mix 28',
    'This Is Artist Mix 29',
    'This Is Artist Mix 30',
    'This Is Artist Mix 31',
    'This Is Artist Mix 32',
  ];

  final PlaylistService _discoverService = PlaylistService();
  List<PlaylistModel> _genrePlaylists = [];
  List<PlaylistModel> _artistPlaylists = [];
  bool _loadingCache = true;
  final Set<String> _fetching = {};
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  List<Map<String, String>> _profiles = [];
  List<PlaylistModel> _searchPlaylistResults = [];
  List<PlaylistModel> _communityPlaylists = [];
  bool _communityLoading = false;
  bool _communityLoaded = false;
  bool _communityReloadQueued = false;
  String? _communityError;
  bool _refetching = false;
  Timer? _profileSearchTimer;
  Timer? _searchPlaylistTimer;
  Timer? _trackSearchTimer;
  String? _myUid;

  /// Song results for the current query.
  List<TrackModel> _trackResults = [];

  /// Ids of search results already saved to the library, so the bookmark icon
  /// reflects the real state rather than always looking unsaved.
  final Set<String> _savedTrackIds = {};

  /// Lets a searched song be filed into the library: either "Liked songs" or any
  /// existing playlist.
  Future<void> _showSaveSheet(BuildContext context, TrackModel track) async {
    final auth = context.read<AuthProvider>();
    final prov = context.read<PlaylistProvider>();
    final uid = auth.user?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sign in to save songs')));
      return;
    }

    // Reflect the real library state when the sheet opens.
    final liked = prov.playlists.where(
      (p) => p.id == PlaylistProvider.likedSongsId,
    );
    if (liked.isNotEmpty) {
      for (final t in liked.first.tracks) {
        _savedTrackIds.add(t.id);
      }
    }
    for (final p in prov.playlists) {
      for (final t in p.tracks) {
        _savedTrackIds.add(t.id);
      }
    }
    if (mounted) setState(() {});

    final target = await showModalBottomSheet<String?>(
      context: context,
      // Above the mini player. Sheets opened on a tab's own navigator render
      // under it, because the mini player is drawn by MainScreen outside every
      // tab navigator.
      useRootNavigator: true,
      backgroundColor: SpotterfyTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                'Save "${track.title}"',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: SpotterfyTheme.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.favorite_rounded,
                color: SpotterfyTheme.primary,
              ),
              title: const Text('Liked songs'),
              subtitle: Text(
                'Your saved songs',
                style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12),
              ),
              onTap: () =>
                  Navigator.pop(sheetCtx, PlaylistProvider.likedSongsId),
            ),
            if (prov.playlists.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 4),
                child: Text(
                  'Add to a playlist',
                  style: TextStyle(
                    color: SpotterfyTheme.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: prov.playlists.length,
                  itemBuilder: (_, i) {
                    final p = prov.playlists[i];
                    return ListTile(
                      leading: Icon(
                        Icons.queue_music_rounded,
                        color: SpotterfyTheme.muted,
                      ),
                      title: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: SpotterfyTheme.text,
                          fontSize: 14,
                        ),
                      ),
                      onTap: () => Navigator.pop(sheetCtx, p.id),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;

    final message = await prov.saveTrackToLibrary(
      uid,
      track,
      playlistId: target,
    );
    if (!mounted) return;
    setState(() {
      if (message != null) _savedTrackIds.add(track.id);
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message ?? 'Already in your library'),
        backgroundColor: SpotterfyTheme.surface,
      ),
    );
  }

  /// A search is in flight. Until it settles the page must NOT claim there is
  /// nothing found - previously the panel flashed on the very first keystroke,
  /// because the results are debounced and had not arrived yet.
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _myUid = context.read<AuthProvider>().user?.uid;
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
      _profileSearchTimer?.cancel();
      _searchPlaylistTimer?.cancel();
      _trackSearchTimer?.cancel();
      if (_query.length >= 2) {
        // Mark as searching immediately so the "nothing found" panel is
        // suppressed while the debounced lookups are still pending.
        setState(() => _searching = true);
        _profileSearchTimer = Timer(
          const Duration(milliseconds: 400),
          () async {
            final results = await FirebaseService.searchUsers(
              _query,
              excludeUid: _myUid,
            );
            if (!mounted) return;
            setState(() => _profiles = results);
          },
        );
        _searchPlaylistTimer = Timer(
          const Duration(milliseconds: 400),
          () async {
            final results = await _discoverService.searchOtherUsersPlaylists(
              _query,
              excludeUid: _myUid,
            );
            if (!mounted) return;
            setState(() => _searchPlaylistResults = results);
          },
        );
        _trackSearchTimer = Timer(const Duration(milliseconds: 400), () async {
          final wanted = _query;
          final results = _isOnline
              ? await ApiService.searchTracks(_query)
              : null;
          if (!mounted) return;
          // Discard a response for a query the user has already moved on
          // from, otherwise results flash in for the wrong text.
          if (wanted != _query) return;
          setState(() {
            _trackResults = results ?? const [];
            _searching = false;
          });
        });
      } else {
        _profiles = [];
        _searchPlaylistResults = [];
        _trackResults = [];
        _searching = false;
      }
    });
    _initConnectivity();
    _loadDiscoverFromCache();
    _loadCommunityPlaylists();
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

  static const _discoverFetchInterval = Duration(hours: 24);

  /// Loads Discover lists: on-device snapshot if fetched <24h ago, else a
  /// single Firestore read (persisted afterwards). Never refetches just from
  /// visiting the page — use [force] (refetch button) to refresh on demand.
  Future<void> _loadDiscoverFromCache({bool force = false}) async {
    setState(() => _loadingCache = true);
    try {
      if (!force && await _usePersistedDiscover()) {
        if (!mounted) return;
        setState(() => _loadingCache = false);
        return;
      }
      final genres = await _discoverService.getDiscoverPlaylists(_genreUrls);
      final artists = await _discoverService.getDiscoverPlaylists(_artistUrls);
      if (!mounted) return;
      setState(() {
        _genrePlaylists = _mergeWithPlaceholders(
          _genreUrls,
          genres,
          _genreFallbackNames,
          isGenre: true,
        );
        _artistPlaylists = _mergeWithPlaceholders(
          _artistUrls,
          artists,
          _artistFallbackNames,
          isGenre: false,
        );
        _loadingCache = false;
      });
      await _persistDiscover();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _genrePlaylists = _placeholders(_genreUrls, _genreFallbackNames);
        _artistPlaylists = _placeholders(_artistUrls, _artistFallbackNames);
        _loadingCache = false;
      });
    }
  }

  /// Returns true when a fresh (<24h) on-device snapshot was applied.
  Future<bool> _usePersistedDiscover() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt('discover_last_fetch_ms') ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - last >
          _discoverFetchInterval.inMilliseconds) {
        return false;
      }
      final raw = prefs.getString('discover_snapshot_v1');
      if (raw == null) return false;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final genres = ((data['genres'] as List<dynamic>?) ?? [])
          .map((e) => PlaylistModel.fromCache(e as Map<String, dynamic>))
          .toList();
      final artists = ((data['artists'] as List<dynamic>?) ?? [])
          .map((e) => PlaylistModel.fromCache(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return false;
      setState(() {
        _genrePlaylists = _mergeWithPlaceholders(
          _genreUrls,
          genres,
          _genreFallbackNames,
          isGenre: true,
        );
        _artistPlaylists = _mergeWithPlaceholders(
          _artistUrls,
          artists,
          _artistFallbackNames,
          isGenre: false,
        );
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persistDiscover() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode({
        'genres': _genrePlaylists.map((p) => p.toCache()).toList(),
        'artists': _artistPlaylists.map((p) => p.toCache()).toList(),
      });
      await prefs.setString('discover_snapshot_v1', raw);
      await prefs.setInt(
        'discover_last_fetch_ms',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  Future<void> _refetchDiscover() async {
    if (_refetching) return;
    setState(() => _refetching = true);
    try {
      await _loadDiscoverFromCache(force: true);
      // Also refresh the community row so "Refresh" really updates the page.
      await _loadCommunityPlaylists(force: true);
    } finally {
      if (mounted) setState(() => _refetching = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Discover updated'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  List<PlaylistModel> _placeholders(
    List<String> urls,
    List<String> fallbackNames,
  ) {
    return List.generate(urls.length, (i) {
      final url = urls[i].split('?').first;
      return PlaylistModel(
        id: url.hashCode.toString(),
        name: fallbackNames[i % fallbackNames.length],
        // Matches the real discover docs so "By Spotify" does not blink out and
        // back in once the cache resolves.
        owner: _discoverOwner,
        coverUrl: '',
        tracks: [],
        // No creator account behind a discover shelf - see
        // [PlaylistModel.withoutCreator].
        creatorUid: '',
        source: 'spotify',
        spotifyUrl: url,
      );
    });
  }

  /// Author shown for the curated Discover shelves while they have no backend
  /// data. These are all Spotify editorial playlists, so it is the same name the
  /// fetched docs carry.
  static const String _discoverOwner = 'Spotify';

  List<PlaylistModel> _mergeWithPlaceholders(
    List<String> urls,
    List<PlaylistModel> cached,
    List<String> fallbackNames, {
    required bool isGenre,
  }) {
    final byUrl = {for (final p in cached) p.spotifyUrl.split('?').first: p};
    return List.generate(urls.length, (i) {
      final clean = urls[i].split('?').first;
      final hit = byUrl[clean];
      // The backend publishes these under a `system_discover` uid, which is not
      // a real user, so drop the profile button while keeping the "By Spotify"
      // author line. Community playlists are not built here, so they keep their
      // real creator and their profile button.
      if (hit != null) return hit.withoutCreator();
      return PlaylistModel(
        id: clean.hashCode.toString(),
        name: fallbackNames[i % fallbackNames.length],
        owner: _discoverOwner,
        coverUrl: '',
        tracks: [],
        creatorUid: '',
        source: 'spotify',
        spotifyUrl: clean,
      );
    });
  }

  Future<void> _playRadioStation(Map<String, dynamic> station) async {
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Radio requires internet connection')),
      );
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Playing ${station['name']}')));
  }

  Future<void> _openDiscoverPlaylist(
    BuildContext context,
    PlaylistModel p,
  ) async {
    if (p.tracks.isNotEmpty) {
      if (!context.mounted) return;
      Navigator.push(context, swipeRoute(PlaylistDetailScreen(playlist: p)));
      return;
    }
    final url = p.spotifyUrl.split('?').first;
    if (url.isEmpty) {
      // Suggestion placeholder with nothing behind it - say so instead of
      // silently doing nothing when tapped.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No community playlists yet - be the first to share!'),
        ),
      );
      return;
    }
    if (_fetching.contains(url)) return;
    setState(() => _fetching.add(url));
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      const SnackBar(
        content: Text('Loading playlist…'),
        duration: Duration(seconds: 2),
      ),
    );
    try {
      final fresh = await _discoverService.fetchDiscoverPlaylistWithCache(
        url,
        fetcher: () => ApiService.scrapePlaylist(url),
      );
      if (!mounted) return;
      setState(() => _fetching.remove(url));
      if (fresh == null) {
        scaffold.showSnackBar(
          const SnackBar(
            content: Text('Failed to load playlist. Try again later.'),
          ),
        );
        return;
      }
      setState(() {
        final gIdx = _genrePlaylists.indexWhere(
          (e) => e.spotifyUrl.split('?').first == url,
        );
        if (gIdx >= 0) _genrePlaylists[gIdx] = fresh;
        final aIdx = _artistPlaylists.indexWhere(
          (e) => e.spotifyUrl.split('?').first == url,
        );
        if (aIdx >= 0) _artistPlaylists[aIdx] = fresh;
      });
      if (!context.mounted) return;
      Navigator.push(
        context,
        swipeRoute(PlaylistDetailScreen(playlist: fresh)),
      );
    } catch (e) {
      if (mounted) setState(() => _fetching.remove(url));
      scaffold.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _profileSearchTimer?.cancel();
    _searchPlaylistTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // AuthProvider resolves the signed-in user asynchronously, so the uid read
    // in initState is usually still null there. Re-sync it here and reload the
    // community row once it arrives, otherwise our own playlists would show up
    // under "Community Playlists" and the user couldn't be excluded from search.
    final uid = context.watch<AuthProvider>().user?.uid;
    final uidChanged = uid != _myUid;
    if (uidChanged) _myUid = uid;
    // Kick the fetch off from build as well as initState. initState does not
    // re-run on hot reload/restart-of-frame, which could otherwise leave the row
    // permanently showing placeholders; this makes the load self-healing.
    if (uidChanged || !_communityLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (uidChanged) _communityLoaded = false;
        _loadCommunityPlaylists(force: uidChanged);
      });
    }

    return BasePageScaffold(
      searchController: _searchController,
      searchHint: 'Search the community',
      query: _query,
      // Same "Check for updates" refetch icon button the Library playlist
      // detail screen uses (Icons.sync + spinner while working).
      action: IconButton(
        icon: _refetching
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: SpotterfyTheme.primary,
                ),
              )
            : Icon(Icons.sync, color: SpotterfyTheme.mutedDark),
        tooltip: 'Check for updates',
        onPressed: (_refetching || _loadingCache) ? null : _refetchDiscover,
      ),
      // The "nothing found" panel is returned as the body directly (not inside
      // the scroll view) so it can expand to the full viewport height and truly
      // centre itself.
      body: _showNoResults
          ? NoResultsView(
              query: _query,
              message:
                  'No playlists or profiles include "$_query".\nCheck the spelling or try a different search.',
              onAction: () => _searchController.clear(),
              actionLabel: 'Clear search',
            )
          : SingleChildScrollView(
              // Clears the mini player + navbar without leaving a big gap.
              padding: const EdgeInsets.only(bottom: 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section(
                    context,
                    'Top Genres',
                    _genrePlaylists,
                    _query,
                    isLoading: _loadingCache,
                    clickableTitle: _query.isEmpty,
                  ),
                  _section(
                    context,
                    'Top Artists',
                    _artistPlaylists,
                    _query,
                    isLoading: _loadingCache,
                    clickableTitle: _query.isEmpty,
                  ),
                  _radioSection(context, _query),
                  _songsSection(context, _query),
                  if (_searchPlaylistResults.isNotEmpty && _query.isNotEmpty)
                    _searchResultsSection(),
                  if (_profiles.isNotEmpty) _profilesSection(),
                  _otherUsersSection(context, _query),
                ],
              ),
            ),
    );
  }

  /// True only once the search for the current query has actually finished and
  /// nothing matched. While a lookup is in flight the page shows progress
  /// instead, which is what stopped "nothing found" flashing on the first
  /// keystroke.
  bool get _showNoResults {
    if (_query.isEmpty) return false;
    if (_searching) return false;
    if (_trackResults.isNotEmpty) return false;
    if (_profiles.isNotEmpty) return false;
    if (_searchPlaylistResults.isNotEmpty) return false;
    bool nameHit(List<PlaylistModel> list) =>
        list.any((p) => p.name.toLowerCase().contains(_query));
    if (nameHit(_genrePlaylists)) return false;
    if (nameHit(_artistPlaylists)) return false;
    if (_radioStations.any((s) => s['name']!.toLowerCase().contains(_query))) {
      return false;
    }
    return true;
  }

  /// Song results, shown as a list of playable rows. This is what makes the
  /// search bar find individual songs (with artwork and length) instead of only
  /// matching cached playlist names.
  Widget _songsSection(BuildContext context, String query) {
    if (query.isEmpty) return const SizedBox.shrink();
    if (_searching && _trackResults.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: SpotterfyTheme.primary,
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Searching songs...',
              style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12),
            ),
          ],
        ),
      );
    }
    if (_trackResults.isEmpty) return const SizedBox.shrink();

    final player = context.watch<PlayerProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                'Songs',
                style: TextStyle(
                  color: SpotterfyTheme.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: SpotterfyTheme.overlay(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_trackResults.length}',
                  style: TextStyle(
                    color: SpotterfyTheme.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        ..._trackResults.map((t) {
          final isSelected = player.currentTrack?.id == t.id;
          return TrackTile(
            track: t,
            isSelected: isSelected,
            isPlaying: isSelected && player.isPlaying,
            onPlay: () {
              // Play the whole result set so the queue is browsable, starting
              // from the row that was tapped.
              player.setQueue(
                _trackResults,
                startIndex: _trackResults.indexOf(t),
              );
              player.play(t, queue: _trackResults);
            },
            onSave: () => _showSaveSheet(context, t),
            isSaved: _savedTrackIds.contains(t.id),
          );
        }),
      ],
    );
  }

  Widget _radioSection(BuildContext context, String query) {
    if (!_isOnline) return const SizedBox.shrink();
    var stations = _radioStations;
    if (query.isNotEmpty) {
      stations = stations
          .where((s) => s['name']!.toLowerCase().contains(query))
          .toList();
      // No station matched: hide the whole category (same rule as the other
      // sections) instead of leaving a lone "No matches" header behind.
      if (stations.isEmpty) return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              swipeRoute(
                _RadioStationsPage(
                  stations: _radioStations,
                  onTap: (s) => _playRadioStation(s),
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Radio Stations',
                  style: TextStyle(
                    color: SpotterfyTheme.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right,
                  color: SpotterfyTheme.muted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        // Every station is in the carousel, not just the first handful - the
        // chevron sub-page stays as a full-height list for scanning, but it is
        // no longer the only way to reach the less common stations.
        _cardRow(
          count: stations.length,
          item: (i) {
            final s = stations[i];
            return _DiscoverCard(
              width: 110,
              coverUrl: s['logo']!,
              title: s['name']!,
              margin: EdgeInsets.only(right: i == stations.length - 1 ? 0 : 10),
              onTap: () => _playRadioStation(s),
            );
          },
        ),
      ],
    );
  }

  /// Playlists from other users matched in Firestore (name search).
  Widget _searchResultsSection() {
    const cardW = 110.0;
    const listH = 110.0;
    final list = _searchPlaylistResults;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            'Community Playlists',
            style: TextStyle(
              color: SpotterfyTheme.text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(
          height: listH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final p = list[i];
              return _DiscoverCard(
                width: cardW,
                coverUrl: p.coverUrl,
                title: p.name,
                margin: EdgeInsets.only(right: i == list.length - 1 ? 0 : 10),
                onTap: () => Navigator.push(
                  context,
                  swipeRoute(PlaylistDetailScreen(playlist: p)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _profilesSection() {
    const cardW = 110.0;
    const listH = 110.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            'Profiles',
            style: TextStyle(
              color: SpotterfyTheme.text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(
          height: listH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _profiles.length,
            itemBuilder: (_, i) {
              final p = _profiles[i];
              final name = (p['displayName'] ?? '').trim().isNotEmpty
                  ? p['displayName']!
                  : (p['email'] ?? p['uid'] ?? '');
              final photo = p['photoUrl'] ?? '';
              return GestureDetector(
                onTap: () => _openUserProfile(p),
                child: Container(
                  width: cardW,
                  margin: EdgeInsets.only(
                    right: i == _profiles.length - 1 ? 0 : 10,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        color: SpotterfyTheme.card,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: SpotterfyTheme.surface,
                              backgroundImage: photo.isNotEmpty
                                  ? NetworkImage(photo)
                                  : null,
                              child: photo.isNotEmpty
                                  ? null
                                  : Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: SpotterfyTheme.muted,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Text(
                                name,
                                style: TextStyle(
                                  color: SpotterfyTheme.text,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Opens a sheet for a found (other) user with their public playlists.
  Future<void> _openUserProfile(Map<String, String> user) async {
    final uid = user['uid'] ?? '';
    if (uid.isEmpty) return;
    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: SpotterfyTheme.surface,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: SpotterfyTheme.card,
                    backgroundImage: (user['photoUrl'] ?? '').isNotEmpty
                        ? NetworkImage(user['photoUrl']!)
                        : null,
                    child: (user['photoUrl'] ?? '').isEmpty
                        ? Text(
                            (user['displayName'] ?? '?').isNotEmpty
                                ? user['displayName']![0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: SpotterfyTheme.muted,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user['displayName'] ?? 'Unknown user',
                          style: TextStyle(
                            color: SpotterfyTheme.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if ((user['email'] ?? '').isNotEmpty)
                          Text(
                            user['email']!,
                            style: TextStyle(
                              color: SpotterfyTheme.muted,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 18),
              Text(
                'Public playlists',
                style: TextStyle(
                  color: SpotterfyTheme.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 10),
              Flexible(
                child: FutureBuilder<List<PlaylistModel>>(
                  future: _discoverService.getPlaylistsByCreator(uid),
                  builder: (_, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return SizedBox(
                        height: 90,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: SpotterfyTheme.primary,
                          ),
                        ),
                      );
                    }
                    final items = snap.data ?? const <PlaylistModel>[];
                    if (items.isEmpty) {
                      return SizedBox(
                        height: 70,
                        child: Center(
                          child: Text(
                            'No public playlists',
                            style: TextStyle(
                              color: SpotterfyTheme.muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final pl = items[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: pl.coverUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: pl.coverUrl,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 120,
                                      errorWidget: (_, _, _) => Container(
                                        color: SpotterfyTheme.card,
                                        child: Icon(
                                          Icons.music_note,
                                          color: SpotterfyTheme.muted,
                                          size: 18,
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color: SpotterfyTheme.card,
                                      child: Icon(
                                        Icons.music_note,
                                        color: SpotterfyTheme.muted,
                                        size: 18,
                                      ),
                                    ),
                            ),
                          ),
                          title: Text(
                            pl.name,
                            style: TextStyle(
                              color: SpotterfyTheme.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${pl.tracks.length} tracks',
                            style: TextStyle(
                              color: SpotterfyTheme.muted,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(sheetCtx);
                            Navigator.push(
                              context,
                              swipeRoute(PlaylistDetailScreen(playlist: pl)),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Horizontal carousel of a discover section's cards.
  ///
  /// The front page deliberately stays a single swipeable row - the grid/vertical
  /// layout is the sub-page's job. What changed is the *count*: this used to
  /// clip the row to five cards (six for radio), so the rest of the catalogue
  /// was only reachable through the header's chevron. Every item is in the
  /// carousel now, so the front page is browsable on its own and the chevron is
  /// a shortcut to the same set laid out vertically rather than the only door to
  /// it.
  Widget _cardRow({
    required int count,
    required Widget Function(int) item,
    double cardW = 110.0,
  }) {
    if (count == 0) return const SizedBox.shrink();
    return SizedBox(
      height: cardW,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: count,
        itemBuilder: (_, i) => item(i),
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    List<PlaylistModel> data,
    String query, {
    bool isLoading = false,
    bool clickableTitle = true,
  }) {
    // Square cards; title overlays the cover bottom on a blur
    const cardW = 110.0;
    if (isLoading && data.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: SpotterfyTheme.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (clickableTitle) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right,
                    color: SpotterfyTheme.muted,
                    size: 18,
                  ),
                ],
              ],
            ),
          ),
          _cardRow(
            count: 5,
            item: (_) => Container(
              width: cardW,
              decoration: BoxDecoration(
                color: SpotterfyTheme.card,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      );
    }
    var filtered = data;
    if (query.isNotEmpty) {
      filtered = data
          .where((p) => p.name.toLowerCase().contains(query))
          .toList();
    }
    if (filtered.isEmpty && query.isNotEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: clickableTitle
              ? GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    swipeRoute(
                      _SectionPage(
                        title: title,
                        playlists: filtered,
                        onTap: (p) => _openDiscoverPlaylist(context, p),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: SpotterfyTheme.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right,
                        color: SpotterfyTheme.muted,
                        size: 18,
                      ),
                    ],
                  ),
                )
              : Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: SpotterfyTheme.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
        ),
        _cardRow(
          count: filtered.length,
          item: (i) {
            final p = filtered[i];
            return _DiscoverCard(
              width: cardW,
              coverUrl: p.coverUrl,
              spotifyUrl: p.spotifyUrl,
              title: p.name,
              // Same 10px gap the other sections use - without it the covers
              // sit flush against each other.
              margin: EdgeInsets.only(right: i == filtered.length - 1 ? 0 : 10),
              onTap: () => _openDiscoverPlaylist(context, p),
            );
          },
        ),
      ],
    );
  }

  // Placeholders for "Community Playlists" only when the community catalogue is
  // genuinely empty. Never used while a real fetch is in flight or failed.
  List<PlaylistModel> get _otherUsersPlaceholders => List.generate(
    5,
    (i) => PlaylistModel(
      id: 'other_placeholder_$i',
      name: [
        'Community Picks',
        'Late Night Mix',
        'Chill Discovery',
        'Viral Vault',
        'Fresh Finds',
      ][i % 5],
      coverUrl: '',
      tracks: [],
      creatorUid: 'placeholder_other',
      source: 'spotify',
    ),
  );

  /// Community playlists always come straight from Firestore.
  /// [PlaylistProvider.playlists] only ever holds the signed-in user's own
  /// playlists, so filtering it by `creatorUid != myUid` was always empty.
  Widget _otherUsersSection(BuildContext context, String query) {
    // While searching, the dedicated "Community Playlists" row already shows hits.
    if (query.isNotEmpty) return const SizedBox.shrink();

    if (_communityLoading) {
      return _section(
        context,
        'Community Playlists',
        const [],
        '',
        isLoading: true,
        clickableTitle: true,
      );
    }
    if (_communityPlaylists.isEmpty) {
      // Distinguish "genuinely no community playlists yet" from "the fetch
      // failed" - a silent placeholder row hid permission-denied errors.
      if (_communityError != null) {
        return _CommunityError(
          message: _communityError!,
          onRetry: () => _loadCommunityPlaylists(force: true),
        );
      }
      // No community content yet: keep the suggestion placeholders so the row
      // isn't just a dead header. The arrow still leads to the full list page.
      return _section(
        context,
        'Community Playlists',
        _otherUsersPlaceholders,
        '',
        isLoading: false,
        clickableTitle: true,
      );
    }
    return _section(
      context,
      'Community Playlists',
      _communityPlaylists,
      '',
      isLoading: false,
      clickableTitle: true,
    );
  }

  /// Fetches the community catalogue. Safe to call repeatedly: a request that
  /// arrives while another is in flight is remembered and run right after, so a
  /// forced reload (e.g. when the signed-in uid finally resolves) is never
  /// silently dropped.
  Future<void> _loadCommunityPlaylists({bool force = false}) async {
    if (_communityLoading) {
      if (force) _communityReloadQueued = true;
      return;
    }
    if (!force && _communityLoaded) return;
    setState(() {
      _communityLoading = true;
      _communityError = null;
    });
    do {
      _communityReloadQueued = false;
      try {
        final list = await _discoverService.getCommunityPlaylists(
          excludeUid: _myUid,
          limit: 30,
        );
        if (!mounted) return;
        setState(() {
          _communityPlaylists = list;
          _communityLoaded = true;
        });
      } catch (e) {
        debugPrint('loadCommunityPlaylists failed: $e');
        if (mounted) {
          setState(() {
            _communityLoaded = true;
            _communityError = '$e';
          });
        }
      }
    } while (_communityReloadQueued && mounted);
    if (mounted) setState(() => _communityLoading = false);
  }
}

/// Square playlist cover with the title overlaid on a blurred strip at the
/// bottom, covering part of the cover.
/// Artwork for a discover card.
///
/// Discover playlists that are not in the local cache arrive as placeholders
/// with no cover, so every one of them used to render the same music-note icon.
/// When that happens the real artwork is fetched once from Spotify's oEmbed
/// endpoint and faded in; the result is cached process-wide.
class _DiscoverCover extends StatefulWidget {
  final String coverUrl;
  final String spotifyUrl;

  const _DiscoverCover({required this.coverUrl, required this.spotifyUrl});

  @override
  State<_DiscoverCover> createState() => _DiscoverCoverState();
}

class _DiscoverCoverState extends State<_DiscoverCover> {
  String? _resolved;

  @override
  void initState() {
    super.initState();
    if (widget.coverUrl.isEmpty && widget.spotifyUrl.isNotEmpty) {
      _resolve();
    }
  }

  @override
  void didUpdateWidget(covariant _DiscoverCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.coverUrl.isEmpty && widget.spotifyUrl.isNotEmpty) _resolve();
  }

  Future<void> _resolve() async {
    final url = await PlaylistService.resolveSpotifyCover(widget.spotifyUrl);
    if (!mounted || url.isEmpty || widget.coverUrl.isNotEmpty) return;
    setState(() => _resolved = url);
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.coverUrl.isNotEmpty
        ? widget.coverUrl
        : (_resolved ?? '');
    if (url.isEmpty) return _placeholder();
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: 220,
      placeholder: (_, _) => _placeholder(),
      errorWidget: (_, _, _) => _placeholder(),
    );
  }

  Widget _placeholder() => Container(
    color: SpotterfyTheme.surface,
    child: Center(
      child: Icon(Icons.music_note, color: SpotterfyTheme.muted, size: 28),
    ),
  );
}

class _DiscoverCard extends StatelessWidget {
  final double width;
  final String coverUrl;

  /// Used to resolve artwork on demand when [coverUrl] is empty.
  final String spotifyUrl;
  final String title;
  final EdgeInsets margin;
  final VoidCallback onTap;

  const _DiscoverCard({
    required this.width,
    required this.coverUrl,
    this.spotifyUrl = '',
    required this.title,
    this.margin = EdgeInsets.zero,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: width,
          margin: margin,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _DiscoverCover(
                      coverUrl: coverUrl,
                      spotifyUrl: spotifyUrl,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.45),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 6,
                          ),
                          child: Text(
                            title,
                            style: TextStyle(
                              color: SpotterfyTheme.text,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Surfaced when the community fetch fails, so a rules/permission problem is
/// visible instead of being masked by the placeholder row.
class _CommunityError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _CommunityError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Community Playlists',
            style: TextStyle(
              color: SpotterfyTheme.text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6),
          Text(
            "Couldn't load community playlists",
            style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12),
          ),
          SizedBox(height: 2),
          Text(
            message,
            style: TextStyle(color: SpotterfyTheme.muted, fontSize: 11),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 6),
          TextButton.icon(
            onPressed: onRetry,
            icon: Icon(Icons.refresh, color: SpotterfyTheme.primary, size: 18),
            label: Text(
              'Retry',
              style: TextStyle(color: SpotterfyTheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when a search matches nothing in any category. Every section hides
/// itself on a miss, so this is the only feedback the user would otherwise get.
/// Radio stations list page
class _RadioStationsPage extends StatelessWidget {
  final List<Map<String, dynamic>> stations;
  final Function(Map<String, dynamic>) onTap;
  const _RadioStationsPage({required this.stations, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SwipeBackWrapper(
      child: Scaffold(
        backgroundColor: SpotterfyTheme.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Radio Stations',
            style: TextStyle(
              color: SpotterfyTheme.text,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: ListView.builder(
          padding: const EdgeInsets.only(bottom: 110),
          itemCount: stations.length,
          itemBuilder: (_, i) {
            final s = stations[i];
            return GestureDetector(
              onTap: () => onTap(s),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SpotterfyTheme.card,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: s['logo']!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        placeholder: (context, _) =>
                            Container(color: SpotterfyTheme.surface),
                        errorWidget: (context, _, _) =>
                            Icon(Icons.radio, color: SpotterfyTheme.muted),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        s['name']!,
                        style: TextStyle(
                          color: SpotterfyTheme.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.play_arrow,
                      color: SpotterfyTheme.primary,
                      size: 24,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionPage extends StatefulWidget {
  final String title;
  final List<PlaylistModel> playlists;
  final Future<void> Function(PlaylistModel)? onTap;
  const _SectionPage({
    required this.title,
    required this.playlists,
    this.onTap,
  });

  @override
  State<_SectionPage> createState() => _SectionPageState();
}

class _SectionPageState extends State<_SectionPage> {
  static const int _pageSize = 10;
  late List<PlaylistModel> _displayed;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _displayed = widget.playlists.take(_pageSize).toList();
    _scrollController = ScrollController()
      ..addListener(() {
        if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300) {
          if (_displayed.length < widget.playlists.length) {
            setState(() {
              _displayed = widget.playlists
                  .take(_displayed.length + _pageSize)
                  .toList();
            });
          }
        }
      });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SwipeBackWrapper(
      child: Scaffold(
        backgroundColor: SpotterfyTheme.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            widget.title,
            style: TextStyle(
              color: SpotterfyTheme.text,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: GridView.builder(
          controller: _scrollController,
          // Clears the shared mini player, which is drawn by MainScreen and
          // sits on top of this tab's own layers.
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.0,
          ),
          itemCount:
              _displayed.length +
              (_displayed.length < widget.playlists.length ? 1 : 0),
          itemBuilder: (_, i) {
            if (i >= _displayed.length) {
              return Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: SpotterfyTheme.primary,
                ),
              );
            }
            final p = _displayed[i];
            return _DiscoverCard(
              width: 110,
              coverUrl: p.coverUrl,
              spotifyUrl: p.spotifyUrl,
              title: p.name,
              onTap: () async {
                if (widget.onTap != null) {
                  await widget.onTap!(p);
                } else {
                  Navigator.push(
                    context,
                    swipeRoute(PlaylistDetailScreen(playlist: p)),
                  );
                }
              },
            );
          },
        ),
      ),
    );
  }
}
