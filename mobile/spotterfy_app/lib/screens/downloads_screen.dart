import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/providers/download_provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/services/download_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/playlist_play_button.dart';
import 'package:spotterfy_app/widgets/round_icon_button.dart';
import 'package:spotterfy_app/widgets/sort_sheet.dart';
import 'package:spotterfy_app/widgets/storage_cover.dart';
import 'package:spotterfy_app/widgets/track_tile.dart';

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

  /// Paths whose file-tag read (for the length) has already been kicked off, so
  /// a build that doesn't yet have a value asks at most once per path.
  final Set<String> _durationRequests = {};

  final TextEditingController _searchController = TextEditingController();

  /// Lower-cased search term; empty means "show everything".
  String _query = '';

  _DownloadSort _sort = _DownloadSort.recent;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

  /// Every download, ordered by the current sort.
  List<DownloadEntry> get _sortedEntries {
    final all = context.read<DownloadProvider>().entries.values.toList()
      ..sort(_compare);
    return all;
  }

  int _compare(DownloadEntry a, DownloadEntry b) {
    switch (_sort) {
      case _DownloadSort.recent:
        // Newest first, which is the order people expect to see.
        return b.downloadedAt.compareTo(a.downloadedAt);
      case _DownloadSort.oldest:
        return a.downloadedAt.compareTo(b.downloadedAt);
      case _DownloadSort.title:
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case _DownloadSort.artist:
        final byArtist = a.artists.toLowerCase().compareTo(
          b.artists.toLowerCase(),
        );
        return byArtist != 0
            ? byArtist
            : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case _DownloadSort.size:
        // Largest first: what "sort by size" is normally asked for.
        return b.sizeBytes.compareTo(a.sizeBytes);
    }
  }

  bool _matches(DownloadEntry e) {
    if (_query.isEmpty) return true;
    return e.title.toLowerCase().contains(_query) ||
        e.artists.toLowerCase().contains(_query);
  }

  /// Sorted and search-filtered, but ignoring the selection filter - so the
  /// count/size line reflects what is on screen without selection-mode noise.
  List<DownloadEntry> get _searchedEntries =>
      _sortedEntries.where(_matches).toList();

  int get _searchedBytes =>
      _searchedEntries.fold(0, (sum, e) => sum + e.sizeBytes);

  /// The list actually rendered: search filter first, then (while selecting)
  /// narrowed to the checked rows.
  List<DownloadEntry> get _entries {
    final list = _searchedEntries;
    if (!_selecting || _selected.isEmpty) return list;
    return list.where((e) => _selected.contains(e.trackId)).toList();
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

  /// Builds playable tracks for [entries], pointing at the stored files so
  /// playback uses the download directly and carrying each file's real length.
  List<TrackModel> _tracksFromEntries(List<DownloadEntry> entries) {
    final prov = context.read<DownloadProvider>();
    return entries.map((e) {
      final path = prov.localPathFor(e.trackId) ?? '';
      return TrackModel(
        id: e.trackId,
        title: e.title,
        artists: e.artists,
        sourceUrl: path,
        durationMs: _durationMsFor(path),
      );
    }).toList();
  }

  /// Length of a downloaded file, read from its embedded tags.
  ///
  /// Reuses [StorageCover]'s read - the artwork every row already loads - so a
  /// row can show a real time without a second file read. The first build for a
  /// path starts the read and rebuilds once the value lands.
  int _durationMsFor(String path) {
    if (path.isEmpty) return 0;
    if (!StorageCoverCache.contains(path)) {
      if (_durationRequests.add(path)) {
        StorageCoverCache.load(path).then((_) {
          if (mounted) setState(() {});
        });
      }
      return 0;
    }
    return StorageCoverCache.durationMsFor(path);
  }

  void _playAll() {
    final player = context.read<PlayerProvider>();
    final entries = _entries;
    if (entries.isEmpty) return;
    final tracks = _tracksFromEntries(entries);
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

  /// Filter field for the download list. Same styling as the playlist screen's
  /// in-list search so the two read as the same control.
  Widget _searchField() {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: SpotterfyTheme.text, fontSize: 14),
        cursorColor: SpotterfyTheme.primary,
        textInputAction: TextInputAction.search,
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Search downloads',
          hintStyle: TextStyle(
            color: SpotterfyTheme.overlay(0.35),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search,
            size: 19,
            color: SpotterfyTheme.mutedDark,
          ),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 17,
                    color: SpotterfyTheme.mutedDark,
                  ),
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: SpotterfyTheme.overlay(0.05),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _noMatches() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          'No downloads match "${_searchController.text.trim()}".',
          textAlign: TextAlign.center,
          style: TextStyle(color: SpotterfyTheme.muted, fontSize: 13),
        ),
      ),
    );
  }

  Future<void> _showSortSheet() async {
    final picked = await showAppSortSheet<_DownloadSort>(
      context: context,
      scope: 'Downloaded tracks',
      current: _sort,
      options: [
        for (final option in _DownloadSort.values)
          SortSheetOption(
            value: option,
            label: option.label,
            icon: option.icon,
          ),
      ],
    );
    if (picked != null && picked != _sort && mounted) {
      setState(() => _sort = picked);
    }
  }

  /// The download rows. Pulled out of [build] so the empty/no-match branch stays
  /// readable.
  Widget _downloadsList(
    List<DownloadEntry> entries,
    DownloadProvider prov,
    bool selecting,
  ) {
    final player = context.watch<PlayerProvider>();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final e = entries[i];
        final path = prov.localPathFor(e.trackId) ?? '';
        final isActive = player.currentTrack?.id == e.trackId;
        final isPlaying = isActive && player.isPlaying;
        return TrackTile(
          track: TrackModel(
            id: e.trackId,
            title: e.title,
            artists: e.artists,
            sourceUrl: path,
            durationMs: _durationMsFor(path),
          ),
          coverPath: path.isEmpty ? null : path,
          isDownloaded: true,
          subtitleMeta: _fmtBytes(e.sizeBytes),
          // Only the downloaded check stays inline: queue and play live on the
          // row tap / swipe, so the row reads as a download list rather than a
          // player.
          emphasizeActions: true,
          isSelected: isActive,
          isPlaying: isPlaying,
          selectionMode: selecting,
          selected: _selected.contains(e.trackId),
          onLongPress: () {
            setState(() => _selecting = true);
            _toggle(e.trackId);
          },
          onPlay: selecting
              ? () => _toggle(e.trackId)
              : () {
                  final p = context.read<PlayerProvider>();
                  // The list is a player too: tapping the row that is already
                  // playing pauses instead of restarting the track.
                  if (p.currentTrack?.id == e.trackId && p.isPlaying) {
                    p.pause();
                    return;
                  }
                  final list = _tracksFromEntries(entries);
                  final idx = list.indexWhere((t) => t.id == e.trackId);
                  final start = idx < 0 ? 0 : idx;
                  p.setQueue(list, startIndex: start);
                  p.play(list[start], queue: list);
                },
          onDownload: selecting ? null : () => _confirmOne(context, e),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<DownloadProvider>();
    final entries = _entries;
    final selecting = _selecting || _selected.isNotEmpty;

    return AppGradientScaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 52,
        // An actual back button. This used to be the profile avatar, which read
        // as a decorative header control rather than "leave this page" - and it
        // *pushed* a second ProfileScreen instead of popping, so leaving here
        // stacked up profile pages you then had to back out of twice.
        leading: IconButton(
          onPressed: selecting
              ? _clear
              : () => Navigator.of(context).maybePop(),
          icon: Icon(
            selecting ? Icons.close : Icons.arrow_back,
            color: SpotterfyTheme.text,
            size: 22,
          ),
        ),
        titleSpacing: 8,
        title: Text(
          selecting ? '${_selected.length} selected' : 'Downloads',
          style: TextStyle(
            color: SpotterfyTheme.text,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        actions: selecting
            ? [
                if (_selected.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: SpotterfyTheme.text,
                    ),
                    tooltip: 'Delete selected downloads',
                    onPressed: _deleteSelected,
                  ),
                const SizedBox(width: 4),
              ]
            : [
                if (entries.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PlaylistPlayButton(
                      size: 36,
                      alwaysGreen: true,
                      tooltip: 'Play all downloads',
                      onPressed: _playAll,
                    ),
                  ),
              ],
      ),
      body: prov.entries.isEmpty
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
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Row(
                    children: [
                      Expanded(child: _searchField()),
                      const SizedBox(width: 8),
                      RoundIconButton(
                        icon: Icons.sort_rounded,
                        tooltip: 'Sort downloads',
                        size: 42,
                        active: _sort != _DownloadSort.recent,
                        onTap: _showSortSheet,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${_searchedEntries.length} '
                          '${_searchedEntries.length == 1 ? 'song' : 'songs'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: SpotterfyTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '• ${_fmtBytes(_searchedBytes)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: SpotterfyTheme.mutedDark,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (_sort != _DownloadSort.recent) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '• ${_sort.label}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: SpotterfyTheme.mutedDark,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: entries.isEmpty
                      ? _noMatches()
                      : _downloadsList(entries, prov, selecting),
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

/// Order the downloads list can be shown in.
enum _DownloadSort {
  recent('Recently added', Icons.schedule_rounded),
  oldest('Oldest first', Icons.history_rounded),
  title('Title', Icons.sort_by_alpha_rounded),
  artist('Artist', Icons.person_outline_rounded),
  size('Size', Icons.sd_storage_rounded);

  const _DownloadSort(this.label, this.icon);
  final String label;
  final IconData icon;
}
