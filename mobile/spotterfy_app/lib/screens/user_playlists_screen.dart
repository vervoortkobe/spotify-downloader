import 'package:flutter/material.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/screens/playlist_detail_screen.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/no_results_view.dart';
import 'package:spotterfy_app/widgets/profile_playlist_tile.dart';
import 'package:spotterfy_app/widgets/sort_sheet.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';

/// Every playlist a profile owns, with its own search and sort controls.
///
/// The profile page deliberately previews only the first few, so this is the
/// place to browse the full set without turning the profile into an endless
/// list.
class UserPlaylistsScreen extends StatefulWidget {
  final String title;
  final List<PlaylistModel> playlists;

  const UserPlaylistsScreen({
    super.key,
    required this.title,
    required this.playlists,
  });

  @override
  State<UserPlaylistsScreen> createState() => _UserPlaylistsScreenState();
}

class _UserPlaylistsScreenState extends State<UserPlaylistsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _PlaylistSort _sort = _PlaylistSort.recent;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PlaylistModel> get _visiblePlaylists {
    final q = _query.trim().toLowerCase();
    final list = widget.playlists.where((p) {
      if (q.isEmpty) return true;
      return p.displayName.toLowerCase().contains(q) ||
          p.name.toLowerCase().contains(q) ||
          p.owner.toLowerCase().contains(q) ||
          p.sourceLabel.toLowerCase().contains(q) ||
          p.tracks.any((t) => t.title.toLowerCase().contains(q));
    }).toList();

    int totalMs(PlaylistModel p) =>
        p.tracks.fold<int>(0, (sum, t) => sum + t.durationMs);

    switch (_sort) {
      case _PlaylistSort.recent:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _PlaylistSort.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case _PlaylistSort.name:
        list.sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
      case _PlaylistSort.mostTracks:
        list.sort((a, b) => b.tracks.length.compareTo(a.tracks.length));
      case _PlaylistSort.fewestTracks:
        list.sort((a, b) => a.tracks.length.compareTo(b.tracks.length));
      case _PlaylistSort.length:
        list.sort((a, b) => totalMs(b).compareTo(totalMs(a)));
    }
    return list;
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  Future<void> _showSortSheet() async {
    final picked = await showAppSortSheet<_PlaylistSort>(
      context: context,
      scope: widget.title,
      current: _sort,
      options: [
        for (final option in _PlaylistSort.values)
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

  @override
  Widget build(BuildContext context) {
    final visible = _visiblePlaylists;
    return AppGradientScaffold(
      title: widget.title,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: SpotterfyTheme.card,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      style: TextStyle(
                        color: SpotterfyTheme.text,
                        fontSize: 14,
                      ),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        prefixIcon: Icon(
                          Icons.search,
                          color: SpotterfyTheme.muted,
                          size: 19,
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 42,
                          minHeight: 44,
                        ),
                        hintText: 'Search playlists',
                        hintStyle: TextStyle(
                          color: SpotterfyTheme.muted,
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        isDense: true,
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                onPressed: _clearSearch,
                                icon: Icon(
                                  Icons.clear,
                                  color: SpotterfyTheme.muted,
                                  size: 19,
                                ),
                                tooltip: 'Clear search',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: 'Sort',
                  child: Material(
                    color: _sort == _PlaylistSort.recent
                        ? SpotterfyTheme.card
                        : SpotterfyTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _showSortSheet,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.sort_rounded,
                          color: _sort == _PlaylistSort.recent
                              ? SpotterfyTheme.muted
                              : SpotterfyTheme.primary,
                          size: 21,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? NoResultsView(
                    query: _query,
                    icon: Icons.queue_music_rounded,
                    message: 'No playlists match "$_query".',
                    actionLabel: 'Clear search',
                    onAction: _clearSearch,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final playlist = visible[i];
                      return ProfilePlaylistTile(
                        playlist: playlist,
                        onTap: () => Navigator.push(
                          context,
                          swipeRoute(PlaylistDetailScreen(playlist: playlist)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Orderings offered by the profile's all-playlists page.
enum _PlaylistSort {
  recent('Recently added', Icons.schedule_rounded),
  oldest('Oldest first', Icons.history_rounded),
  name('Name (A-Z)', Icons.sort_by_alpha_rounded),
  mostTracks('Most tracks', Icons.trending_up_rounded),
  fewestTracks('Fewest tracks', Icons.trending_down_rounded),
  length('Longest first', Icons.timer_outlined);

  const _PlaylistSort(this.label, this.icon);
  final String label;
  final IconData icon;
}
