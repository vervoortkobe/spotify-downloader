import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/download_provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/services/download_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/track_tile.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/profile_screen.dart';

/// Songs downloaded from inside Spotterfy, stored in the app's own folder so
/// they never appear in the Library > Storage tab.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final Set<String> _selected = {};
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final prov = context.read<DownloadProvider>();
      // This page lists files by path and plays them directly, so re-check
      // liveness on open - otherwise an externally deleted file would show up
      // here and fail to play.
      prov.verify();
    });
  }

  List<DownloadEntry> get _entries {
    final all = context.read<DownloadProvider>().entries.values.toList()
      // Newest first, which is the order people expect to see.
      ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    if (!_selecting || _selected.isEmpty) return all;
    return all.where((e) => _selected.contains(e.trackId)).toList();
  }

  void _toggle(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  void _clear() => setState(() {
    _selected.clear();
    _selecting = false;
  });

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final prov = context.read<DownloadProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotterfyTheme.surface,
        title: Text(
          'Delete downloads?',
          style: TextStyle(
            color: SpotterfyTheme.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Removes ${ids.length} ${ids.length == 1 ? 'file' : 'files'} from this device. '
          'The songs stay in your library and will stream again.',
          style: TextStyle(color: SpotterfyTheme.muted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: SpotterfyTheme.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await prov.removeMany(ids);
    _clear();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Removed ${ids.length} ${ids.length == 1 ? 'file' : 'files'}',
        ),
      ),
    );
  }

  void _playAll() {
    final prov = context.read<DownloadProvider>();
    final player = context.read<PlayerProvider>();
    final entries = _entries;
    if (entries.isEmpty) return;
    final tracks = entries
        .map(
          (e) => TrackModel(
            id: e.trackId,
            title: e.title,
            artists: e.artists,
            // The stored file, so playback uses the download directly.
            sourceUrl: prov.localPathFor(e.trackId) ?? '',
          ),
        )
        .toList();
    player.setQueue(tracks, startIndex: 0);
    player.play(tracks.first, queue: tracks);
  }

  String _fmtBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb < 1) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<DownloadProvider>();
    final auth = context.watch<AuthProvider>();
    final entries = _entries;
    final selecting = _selecting || _selected.isNotEmpty;

    return AppGradientScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 52,
        leading: GestureDetector(
          onTap: selecting
              ? _clear
              : () =>
                    Navigator.push(context, swipeRoute(const ProfileScreen())),
          child: Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Center(
              child: selecting
                  ? const Icon(Icons.close, color: Colors.white, size: 22)
                  : Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: SpotterfyTheme.card,
                          width: 1.6,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: SpotterfyTheme.surface,
                        backgroundImage:
                            (auth.user?.photoUrl.isNotEmpty ?? false)
                            ? NetworkImage(auth.user!.photoUrl)
                            : null,
                        child: (auth.user?.photoUrl.isEmpty ?? true)
                            ? Icon(
                                Icons.person,
                                color: SpotterfyTheme.muted,
                                size: 18,
                              )
                            : null,
                      ),
                    ),
            ),
          ),
        ),
        titleSpacing: 8,
        title: Text(
          selecting ? '${_selected.length} selected' : 'Downloads',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        actions: selecting
            ? [
                if (_selected.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white),
                    tooltip: 'Delete selected downloads',
                    onPressed: _deleteSelected,
                  ),
                const SizedBox(width: 4),
              ]
            : [
                if (entries.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.play_arrow, color: Colors.white),
                    tooltip: 'Play all downloads',
                    onPressed: _playAll,
                  ),
                const SizedBox(width: 4),
              ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.download_done,
                    color: SpotterfyTheme.muted,
                    size: 56,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _selecting ? 'Nothing selected' : 'No downloads yet',
                    style: TextStyle(
                      color: SpotterfyTheme.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'Long-press a song in a playlist to download it.\n'
                      'Downloaded songs play from your device.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: SpotterfyTheme.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        '${prov.count} ${prov.count == 1 ? 'song' : 'songs'}',
                        style: TextStyle(
                          color: SpotterfyTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '• ${_fmtBytes(prov.totalBytes)}',
                        style: TextStyle(
                          color: SpotterfyTheme.mutedDark,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      final path = prov.localPathFor(e.trackId) ?? '';
                      return TrackTile(
                        track: TrackModel(
                          id: e.trackId,
                          title: e.title,
                          artists: e.artists,
                          sourceUrl: path,
                        ),
                        coverPath: path.isEmpty ? null : path,
                        isDownloaded: true,
                        selectionMode: selecting,
                        selected: _selected.contains(e.trackId),
                        onLongPress: () {
                          setState(() => _selecting = true);
                          _toggle(e.trackId);
                        },
                        onPlay: selecting
                            ? () => _toggle(e.trackId)
                            : () {
                                final player = context.read<PlayerProvider>();
                                final list = entries
                                    .map(
                                      (x) => TrackModel(
                                        id: x.trackId,
                                        title: x.title,
                                        artists: x.artists,
                                        sourceUrl:
                                            prov.localPathFor(x.trackId) ?? '',
                                      ),
                                    )
                                    .toList();
                                player.setQueue(list, startIndex: i);
                                player.play(list[i], queue: list);
                              },
                        onDownload: selecting
                            ? null
                            : () => _confirmOne(context, e),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _confirmOne(BuildContext context, DownloadEntry e) async {
    final prov = context.read<DownloadProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotterfyTheme.surface,
        title: Text(
          'Delete download?',
          style: TextStyle(
            color: SpotterfyTheme.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '"${e.title}" will stream from the server again.',
          style: TextStyle(color: SpotterfyTheme.muted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: SpotterfyTheme.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await prov.remove(e.trackId);
    messenger.showSnackBar(SnackBar(content: Text('Removed "${e.title}"')));
  }
}
