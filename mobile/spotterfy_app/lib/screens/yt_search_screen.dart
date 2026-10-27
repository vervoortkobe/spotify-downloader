import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/providers/download_provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/widgets/track_tile.dart';
import 'package:spotterfy_app/widgets/base_page.dart';
import 'package:spotterfy_app/widgets/no_results_view.dart';
import 'package:spotterfy_app/widgets/round_icon_button.dart';

class YtSearchScreen extends StatefulWidget {
  const YtSearchScreen({super.key});

  @override
  State<YtSearchScreen> createState() => _YtSearchScreenState();
}

class _YtSearchScreenState extends State<YtSearchScreen> {
  final _controller = TextEditingController();
  List<TrackModel> _results = [];
  bool _loading = false;
  String? _error;
  List<String> _history = [];
  bool _searchSubmitted = false;
  int _requestSequence = 0;
  static const _historyKey = 'youtube_search_history_v1';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() => _history = prefs.getStringList(_historyKey) ?? []);
      }
    });
  }

  bool _isYoutubeUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null && (uri.host == 'youtu.be' || uri.host.endsWith('youtube.com'));
  }

  Future<void> _saveSearch(String query) async {
    if (_isYoutubeUrl(query)) return;
    final normalized = query.trim();
    _history = [normalized, ..._history.where((item) => item.toLowerCase() != normalized.toLowerCase())].take(12).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, _history);
    if (mounted) setState(() {});
  }

  Future<void> _searchYT(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    final request = ++_requestSequence;
    setState(() {
      _loading = true;
      _error = null;
      _results = [];
      _searchSubmitted = true;
    });
    try {
      if (_isYoutubeUrl(q)) {
        final track = await ApiService.resolveYoutubeTrack(q);
        if (mounted && request == _requestSequence && _controller.text.trim() == q) {
          setState(() {
            if (track != null) {
              _results = [track];
            } else {
              _error = 'Could not load that YouTube video.';
            }
          });
          if (track != null) {
            context.read<PlayerProvider>().prefetchTrack(track);
          }
        }
      } else {
        final tracks = await ApiService.searchTracks(q);
        if (mounted && request == _requestSequence && _controller.text.trim() == q) {
          setState(() {
            if (tracks != null) {
              _results = tracks.take(20).toList();
            } else {
              _error = 'Could not load YouTube results. Try again.';
            }
          });
          if (tracks != null) {
            for (final track in tracks.take(4)) {
              context.read<PlayerProvider>().prefetchTrack(track);
            }
          }
        }
        if (request == _requestSequence) await _saveSearch(q);
      }
    } finally {
      if (mounted && request == _requestSequence) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Shuffles whatever the page currently offers and starts playback.
  ///
  /// Search results are the obvious pool; before a query is submitted the
  /// recently-played list is shuffled instead, so the button is never dead on
  /// the landing state.
  void _shufflePlay() {
    final player = context.read<PlayerProvider>();
    final pool = _results.isNotEmpty ? _results : player.recentlyPlayed;
    if (pool.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Search for songs, then shuffle')),
      );
      return;
    }
    final shuffled = [...pool]..shuffle();
    player.setQueue(shuffled, startIndex: 0);
    player.play(shuffled.first, queue: shuffled);
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _controller.text.trim().isNotEmpty;
    return BasePageScaffold(
      searchController: _controller,
      searchHint: 'Search songs on YouTube',
      query: _controller.text.trim().toLowerCase(),
      onSearchChanged: (v) => setState(() {
        _requestSequence++;
        _searchSubmitted = false;
        _loading = false;
        _error = null;
        _results = [];
      }),
      onSearchSubmitted: _searchYT,
      // Shuffle sits beside the search bar, so a query can be turned into
      // playback without scrolling into the results.
      action: RoundIconButton(
        icon: Icons.shuffle_rounded,
        tooltip: 'Shuffle play',
        size: 34,
        onTap: _shufflePlay,
      ),
      body: Column(
        children: [
          if (_loading)
            LinearProgressIndicator(
              color: SpotterfyTheme.primary,
              backgroundColor: SpotterfyTheme.surface,
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: SpotterfyTheme.primary,
              backgroundColor: SpotterfyTheme.surface,
              child: _resultsBody(hasQuery),
            ),
          ),
        ],
      ),
    );
  }

  /// Everything under the search bar, one scrollable per branch so the
  /// pull-to-refresh gesture works from the empty states too.
  Widget _resultsBody(bool hasQuery) {
    if (_results.isNotEmpty || _loading) {
      return ListView.builder(
        // Explicitly scrollable: a two-result list would otherwise be too short
        // to pull.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: _results.length,
        itemBuilder: (_, i) {
          final t = _results[i];
          final player = context.watch<PlayerProvider>();
          final isPlaying = player.currentTrack?.id == t.id && player.isPlaying;
          return TrackTile(
            track: t,
            isSelected: player.currentTrack?.id == t.id,
            isPlaying: isPlaying,
            // Queue and play live on the swipe (right = play now, left = add to
            // queue), so the row carries no inline transport buttons.
            emphasizeActions: true,
            // Play just this result. Queueing every result turned tapping one
            // song into "play this Search playlist", which made next skip into
            // unrelated results the user never chose.
            onPlay: () => context.read<PlayerProvider>().play(t, queue: [t]),
          );
        },
      );
    }
    if (!hasQuery) return _suggestionsView();
    if (_searchSubmitted) {
      return _pullable(
        NoResultsView(
          query: _controller.text,
          message: 'No YouTube results. Try a different search.',
          actionLabel: 'Clear search',
          onAction: _controller.clear,
          // The pull wrapper below is the scrollable here.
          scrollable: false,
        ),
      );
    }
    return _searchHistoryView();
  }

  /// Makes a non-scrolling state pullable: the content keeps its centring while
  /// the wrapper always reports a viewport-tall, scrollable extent.
  Widget _pullable(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }

  /// Pull-to-refresh: re-runs the submitted search, otherwise re-reads the
  /// landing state (recently played from disk plus the local search history).
  Future<void> _refresh() async {
    final query = _controller.text.trim();
    if (_searchSubmitted && query.isNotEmpty) {
      await _searchYT(query);
      return;
    }
    // Deliberately not awaited: it only notifies, and the indicator should stay
    // up for the disk reads below.
    context.read<PlayerProvider>().reloadRecentlyPlayed();
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? const <String>[];
    // Small floor so the indicator is visible instead of blinking away on an
    // instant local read.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _history = history);
  }

  /// Local file to read cover art from when the track has no remote artwork:
  /// an on-device source file, or this app's own download of it.
  String? _localCover(TrackModel track) {
    if (track.cover.isNotEmpty) return null;
    final source = track.sourceUrl;
    if (source.isNotEmpty && !source.startsWith('http')) {
      if (File(source).existsSync()) return source;
    }
    final downloads = context.read<DownloadProvider>();
    return downloads.localPathFor(track.id) ??
        (source.isNotEmpty ? downloads.localPathFor(source) : null);
  }

  Widget _suggestionsView() {
    final player = context.watch<PlayerProvider>();
    // Watched so a row's cover appears once the on-disk download index has
    // finished loading, instead of staying on the placeholder.
    context.watch<DownloadProvider>();
    final recentTracks = player.recentlyPlayed;
    if (recentTracks.isEmpty) {
      return _pullable(
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.music_note, size: 56, color: SpotterfyTheme.muted),
              const SizedBox(height: 12),
              Text(
                'No recently played songs',
                style: TextStyle(
                  color: SpotterfyTheme.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Songs you play will appear here.',
                style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: recentTracks.length,
      itemBuilder: (context, index) {
        final track = recentTracks[index];
        final isPlaying = player.currentTrack?.id == track.id && player.isPlaying;
        return TrackTile(
          track: track,
          // Downloaded and on-device songs carry their artwork inside the file
          // itself, which is why some of these rows had no cover: the tile
          // needs the path to read it.
          coverPath: _localCover(track),
          isSelected: player.currentTrack?.id == track.id,
          isPlaying: isPlaying,
          emphasizeActions: true,
          onPlay: () => context.read<PlayerProvider>().play(track),
        );
      },
    );
  }

  Widget _searchHistoryView() {
    final query = _controller.text.trim().toLowerCase();
    final matches = _history
        .where((term) => term.toLowerCase().contains(query))
        .toList();
    if (matches.isEmpty) {
      return _pullable(
        Center(
          child: Text(
            'Search YouTube for “${_controller.text.trim()}”',
            style: TextStyle(color: SpotterfyTheme.muted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Search history', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
        ),
        for (final term in matches)
          ListTile(
            leading: Icon(Icons.history, color: SpotterfyTheme.muted),
            title: Text(term, style: TextStyle(color: SpotterfyTheme.text)),
            onTap: () { _controller.text = term; _searchYT(term); },
          ),
      ],
    );
  }
}
