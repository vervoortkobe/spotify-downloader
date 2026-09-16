// ignore_for_file: unnecessary_underscores
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/widgets/track_tile.dart';
import 'package:spotterfy_app/widgets/base_page.dart';

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

  // Pool of distinct YouTube thumbnails so fallback covers are varied,
  // not always the same Rickroll image.
  static const _ytThumbIds = [
    'dQw4w9WgXcQ', // Rick Astley
    '9bZkp7q19f0', // PSY
    'kJQP7kiw5Fk', // Despacito
    'OPf0YbXqDmQ', // Uptown Funk
    'fRh_vgS2dFE', // Sorting
    'JGwWNGJdvx8', // Shape of You
    'hT_nvWreIhg', // Counting Stars
    'CevxZvSJLk8', // Roar
  ];

  String _thumbFor(String seed, int index) {
    // Deterministic but varied: rotate through pool based on hash + index.
    final id = _ytThumbIds[(seed.hashCode + index).abs() % _ytThumbIds.length];
    return 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
  }

  List<TrackModel> _fallbackResults(String query) {
    final q = query.trim();
    if (q.isEmpty) return [];
    // Generate 6 distinct options so user has choices instead of a single row.
    final variants = [
      q,
      '$q (Acoustic)',
      '$q - Live',
      '$q - Remix',
      '$q - Cover',
      '$q • Radio Edit',
    ];
    final artists = ['YouTube', 'YouTube Mix', 'YouTube • Live', 'YouTube • Remix', 'YouTube • Cover', 'YouTube'];
    return List.generate(6, (i) {
      return TrackModel(
        id: '${q.hashCode}_$i',
        title: variants[i],
        artists: artists[i],
        cover: _thumbFor(q, i),
        sourceUrl: 'ytsearch:$q:${variants[i]} audio',
      );
    });
  }

  Future<void> _searchYT(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() { _loading = true; _error = null; _results = _fallbackResults(q); });
    try {
      try {
        final url = 'https://www.youtube.com/results?search_query=${Uri.encodeComponent(q)}';
        final p = await ApiService.scrapePlaylist(url, service: 'youtube');
        if (p != null && p.tracks.isNotEmpty) {
          // Ensure even server results have non-empty varied covers (fix legacy single-cover bug).
          final fixed = p.tracks.take(20).toList();
          for (int i = 0; i < fixed.length; i++) {
            final t = fixed[i];
            if (t.cover.isEmpty || t.cover.contains('dQw4w9WgXcQ') && fixed.length == 1) {
              fixed[i] = TrackModel(
                id: t.id,
                title: t.title,
                artists: t.artists,
                album: t.album,
                cover: _thumbFor(t.title.isNotEmpty ? t.title : q, i),
                releaseDate: t.releaseDate,
                sourceUrl: t.sourceUrl,
                durationMs: t.durationMs,
              );
            }
          }
          if (mounted) setState(() => _results = fixed);
        }
        // if scrape returned nothing, keep varied fallback already shown
      } catch (e) {
        // keep fallback, surface non-fatal error silently
        debugPrint('yt scrape fallback kept: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<TrackModel> _playlistSuggestions(PlaylistProvider prov) {
    // Flatten all tracks from user's playlists, dedupe by id, take up to 12.
    final seen = <String>{};
    final out = <TrackModel>[];
    for (final pl in prov.playlists) {
      for (final t in pl.tracks) {
        if (seen.add(t.id)) {
          // Fix any legacy Rickroll covers that were cached with single cover.
          final needsFix = t.cover.isEmpty || t.cover.contains('dQw4w9WgXcQ');
          if (needsFix) {
            out.add(TrackModel(
              id: t.id,
              title: t.title,
              artists: t.artists,
              album: t.album,
              cover: _thumbFor(t.title, out.length),
              releaseDate: t.releaseDate,
              sourceUrl: t.sourceUrl,
              durationMs: t.durationMs,
            ));
          } else {
            out.add(t);
          }
        }
        if (out.length >= 12) break;
      }
      if (out.length >= 12) break;
    }
    if (out.length < 6) {
      // Not enough playlist tracks – fill with curated examples with varied covers.
      final curated = [
        TrackModel(id: 'curated_1', title: 'Blinding Lights', artists: 'The Weeknd', cover: _thumbFor('Blinding Lights', 0), sourceUrl: 'ytsearch:Blinding Lights audio'),
        TrackModel(id: 'curated_2', title: 'As It Was', artists: 'Harry Styles', cover: _thumbFor('As It Was', 1), sourceUrl: 'ytsearch:As It Was audio'),
        TrackModel(id: 'curated_3', title: 'Levitating', artists: 'Dua Lipa', cover: _thumbFor('Levitating', 2), sourceUrl: 'ytsearch:Levitating audio'),
        TrackModel(id: 'curated_4', title: 'About Damn Time', artists: 'Lizzo', cover: _thumbFor('About Damn Time', 3), sourceUrl: 'ytsearch:About Damn Time audio'),
        TrackModel(id: 'curated_5', title: 'Heat Waves', artists: 'Glass Animals', cover: _thumbFor('Heat Waves', 4), sourceUrl: 'ytsearch:Heat Waves audio'),
        TrackModel(id: 'curated_6', title: 'Stay', artists: 'The Kid LAROI & Justin Bieber', cover: _thumbFor('Stay', 5), sourceUrl: 'ytsearch:Stay audio'),
      ];
      for (final c in curated) {
        if (out.length >= 12) break;
        if (seen.add(c.id)) out.add(c);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _controller.text.trim().isNotEmpty;
    return BasePageScaffold(
      searchController: _controller,
      searchHint: 'Search songs on YouTube',
      query: _controller.text.trim().toLowerCase(),
      onSearchChanged: (v) => setState(() {
        if (v.trim().isEmpty) _results = [];
      }),
      onSearchSubmitted: _searchYT,
      body: Column(
        children: [
          if (_loading) LinearProgressIndicator(color: SpotterfyTheme.primary, backgroundColor: SpotterfyTheme.surface),
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: TextStyle(color: Colors.redAccent, fontSize: 12))),
          Expanded(
            child: _results.isEmpty && !_loading
                ? hasQuery
                    ? Center(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.search_off, size: 56, color: SpotterfyTheme.muted),
                          const SizedBox(height: 12),
                          Text('No results for "${_controller.text.trim()}"', style: TextStyle(color: SpotterfyTheme.text, fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(height: 6),
                          Text('Try a different search', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
                        ]),
                      )
                    : _suggestionsView()
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final t = _results[i];
                      final player = context.watch<PlayerProvider>();
                      final isPlaying = player.currentTrack?.id == t.id && player.isPlaying;
                      return TrackTile(track: t, isSelected: player.currentTrack?.id == t.id, isPlaying: isPlaying, onPlay: () {
                        final p = context.read<PlayerProvider>();
                        p.setQueue(_results, startIndex: i);
                        p.play(t, queue: _results);
                      });
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionsView() {
    final prov = context.watch<PlaylistProvider>();
    final suggestions = _playlistSuggestions(prov);
    if (suggestions.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.search, size: 56, color: SpotterfyTheme.muted),
          const SizedBox(height: 12),
          Text('Look for songs on YouTube', style: TextStyle(color: SpotterfyTheme.text, fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 6),
          Text('Try "Lo-fi beats" or "Acoustic covers"', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
          const SizedBox(height: 8),
          Text('Results will play instantly', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 11)),
        ]),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Based on your playlists', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        ),
        ...suggestions.asMap().entries.map((e) {
          final i = e.key;
          final t = e.value;
          final player = context.watch<PlayerProvider>();
          final isPlaying = player.currentTrack?.id == t.id && player.isPlaying;
          return TrackTile(
            track: t,
            isSelected: player.currentTrack?.id == t.id,
            isPlaying: isPlaying,
            onPlay: () {
              final p = context.read<PlayerProvider>();
              // play from suggestions queue so next/prev work
              p.setQueue(suggestions, startIndex: i);
              p.play(t, queue: suggestions);
            },
          );
        }),
      ],
    );
  }
}
