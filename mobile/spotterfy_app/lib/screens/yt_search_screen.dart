// ignore_for_file: unnecessary_underscores
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/widgets/track_tile.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/profile_screen.dart';

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

  Future<void> _searchYT(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      setState(() => _results = [
        TrackModel(id: q.hashCode.toString(), title: q, artists: 'YouTube', cover: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg', sourceUrl: 'ytsearch1:$q audio'),
      ]);
      try {
        final url = 'https://www.youtube.com/results?search_query=${Uri.encodeComponent(q)}';
        final p = await ApiService.scrapePlaylist(url, service: 'youtube');
        if (p != null && p.tracks.isNotEmpty) {
          setState(() => _results = p.tracks.take(20).toList());
        }
      } catch (_) {}
    } finally {
      setState(() => _loading = false);
    }
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
            controller: _controller,
            style: TextStyle(color: SpotterfyTheme.text, fontSize: 14),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search, color: SpotterfyTheme.muted, size: 18),
              prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 36),
              hintText: 'Search songs on YouTube',
              hintStyle: TextStyle(color: SpotterfyTheme.muted, fontSize: 13),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              isDense: true,
              suffixIcon: _controller.text.isNotEmpty ? IconButton(icon: Icon(Icons.clear, color: SpotterfyTheme.muted, size: 16), onPressed: () => setState(() => _controller.clear()), padding: EdgeInsets.zero, constraints: const BoxConstraints()) : null,
            ),
            onSubmitted: (v) => _searchYT(v),
            onChanged: (_) => setState(() {}),
          ),
        ),
        actions: const [SizedBox(width: 12)],
      ),
      body: Column(
        children: [
          if (_loading) LinearProgressIndicator(color: SpotterfyTheme.primary, backgroundColor: SpotterfyTheme.surface),
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: TextStyle(color: Colors.redAccent, fontSize: 12))),
          Expanded(
            child: _results.isEmpty && !_loading
                ? Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.search, size: 56, color: SpotterfyTheme.muted),
                      const SizedBox(height: 12),
                      Text('Look for songs on YouTube', style: TextStyle(color: SpotterfyTheme.text, fontWeight: FontWeight.w600, fontSize: 15)),
                      const SizedBox(height: 6),
                      Text('Try "Lo-fi beats" or "Acoustic covers"', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
                      const SizedBox(height: 8),
                      Text('Results will play instantly', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 11)),
                    ]),
                  )
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
}