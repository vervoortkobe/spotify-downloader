import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/widgets/track_tile.dart';
import 'package:spotterfy_app/widgets/base_page.dart';
import 'package:spotterfy_app/widgets/no_results_view.dart';

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
      if (mounted) setState(() => _history = prefs.getStringList(_historyKey) ?? []);
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
      if (mounted && request == _requestSequence) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
            child: _results.isEmpty && !_loading
                ? hasQuery
                      ? _searchSubmitted
                            ? NoResultsView(
                                query: _controller.text,
                                message: 'No YouTube results. Try a different search.',
                                actionLabel: 'Clear search',
                                onAction: _controller.clear,
                              )
                            : _searchHistoryView()
                      : _suggestionsView()
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final t = _results[i];
                      final player = context.watch<PlayerProvider>();
                      final isPlaying =
                          player.currentTrack?.id == t.id && player.isPlaying;
                      return TrackTile(
                        track: t,
                        isSelected: player.currentTrack?.id == t.id,
                        isPlaying: isPlaying,
                        onPlay: () {
                          final p = context.read<PlayerProvider>();
                          p.setQueue(_results, startIndex: i);
                          p.play(t, queue: _results);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionsView() {
    final player = context.watch<PlayerProvider>();
    final recentTracks = player.recentlyPlayed;
    if (recentTracks.isEmpty) {
      return Center(
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
            Text('Songs you play will appear here.',
                style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: recentTracks.length,
      itemBuilder: (context, index) {
        final track = recentTracks[index];
        final isPlaying = player.currentTrack?.id == track.id && player.isPlaying;
        return TrackTile(
          track: track,
          isSelected: player.currentTrack?.id == track.id,
          isPlaying: isPlaying,
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
      return Center(
        child: Text(
          'Search YouTube for “${_controller.text.trim()}”',
          style: TextStyle(color: SpotterfyTheme.muted, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView(
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
