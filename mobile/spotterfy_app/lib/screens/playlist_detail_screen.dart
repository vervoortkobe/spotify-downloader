import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/providers/download_provider.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/services/playlist_service.dart';
import 'package:spotterfy_app/widgets/track_tile.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/player_screen.dart';
import 'package:spotterfy_app/screens/profile_screen.dart';

/// App-bar button identifying who owns a shared playlist. Shows the owner's
/// Playlist summary: artwork, name, and the stats worth knowing before hitting
/// play - song count, total running time, source, and how many tracks are
/// already downloaded for offline listening.
class _PlaylistHeader extends StatelessWidget {
  final PlaylistModel playlist;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  /// Whether [playlist] belongs to the signed-in user.
  ///
  /// Passed in rather than inferred from an empty [PlaylistModel.owner], because
  /// "no owner" now covers two different things: a playlist that is genuinely
  /// yours, and a curated Discover playlist that has no author at all. Only the
  /// former may claim "Created by you".
  final bool isMine;

  const _PlaylistHeader({
    required this.playlist,
    required this.onPlay,
    required this.onShuffle,
    required this.isMine,
  });

  static String _formatTotal(int ms) {
    final total = (ms / 1000).round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    if (h > 0) return '$h hr ${m.toString().padLeft(2, '0')} min';
    return '$m min';
  }

  @override
  Widget build(BuildContext context) {
    final tracks = playlist.tracks;
    // Only tracks with a known duration contribute, otherwise the total reads
    // low on playlists whose durations haven't been fetched yet.
    final known = tracks.where((t) => t.durationMs > 0).length;
    final totalMs = tracks.fold<int>(0, (sum, t) => sum + t.durationMs);
    final cover = tracks.isNotEmpty ? tracks.first.cover : '';
    final downloaded = context.select<DownloadProvider, int>(
      (d) => tracks.where((t) => d.isDownloaded(t.id)).length,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _artwork(cover),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      // "By <owner>" sits directly underneath, so the title
                      // drops the " - Owner" suffix the scraper adds.
                      playlist.displayName,
                      style: TextStyle(
                        color: SpotterfyTheme.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        height: 1.15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    // No owner line at all for a playlist with no author - the
                    // curated Discover shelves. "Created by you" would be a lie
                    // there, and it was the only thing that used to stand in for
                    // the missing name.
                    if (playlist.owner.isNotEmpty || isMine)
                      Text(
                        playlist.owner.isEmpty
                            ? 'Created by you'
                            : 'By ${playlist.owner}',
                        style: TextStyle(
                          color: SpotterfyTheme.mutedDark,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 8),
                    _statRow(tracks.length, totalMs, known, downloaded),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _PrimaryButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Play',
                  onTap: onPlay,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _SecondaryButton(
                  icon: Icons.shuffle_rounded,
                  label: 'Shuffle',
                  onTap: onShuffle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Sends "N songs · 1h 24 min · Spotify · 12 downloaded" as separate chips
  /// so each fact can drop out independently on narrow screens.
  Widget _statRow(int count, int totalMs, int known, int downloaded) {
    final bits = <String>[
      '$count ${count == 1 ? 'song' : 'songs'}',
      if (totalMs > 0) _formatTotal(totalMs),
      playlist.sourceLabel,
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final b in bits)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: SpotterfyTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              b,
              style: TextStyle(
                color: SpotterfyTheme.primary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
        if (downloaded > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: SpotterfyTheme.overlay(0.07),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$downloaded downloaded',
              style: TextStyle(
                color: SpotterfyTheme.mutedDark,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (known < count && count > 0)
          Tooltip(
            message: known == 0
                ? 'No track durations known yet - total length appears after the first few play'
                : '$known of $count durations known',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: SpotterfyTheme.overlay(0.05),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Icons.help_outline,
                size: 11,
                color: SpotterfyTheme.mutedDark,
              ),
            ),
          ),
      ],
    );
  }

  Widget _artwork(String cover) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 104,
        height: 104,
        child: cover.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: cover,
                fit: BoxFit.cover,
                placeholder: (_, _) => _artworkFallback(),
                errorWidget: (_, _, _) => _artworkFallback(),
              )
            : _artworkFallback(),
      ),
    );
  }

  Widget _artworkFallback() => Container(
    color: SpotterfyTheme.card,
    child: const Icon(Icons.queue_music, color: Color(0xFF4a4a4a), size: 40),
  );
}

/// Green filled call to action.
class _PrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SpotterfyTheme.primary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF06120d), size: 24),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF06120d),
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Outlined secondary action.
class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SpotterfyTheme.overlay(0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SpotterfyTheme.overlay(0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: SpotterfyTheme.text, size: 19),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: SpotterfyTheme.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How the track list is ordered.
enum _PlaylistSort {
  custom('Custom order'),
  title('Title'),
  artist('Artist'),
  duration('Length');

  const _PlaylistSort(this.label);
  final String label;
}

/// Search / sort / shuffle for one playlist, kept across visits.
class _PlaylistViewState {
  String query = '';
  _PlaylistSort sort = _PlaylistSort.custom;
  bool shuffle = false;
}

/// Square icon button used by the view controls, with a tinted active state.
class _SquareButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onPressed;

  const _SquareButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? SpotterfyTheme.primary.withValues(alpha: 0.18)
            : SpotterfyTheme.overlay(0.06),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active
                    ? SpotterfyTheme.primary.withValues(alpha: 0.5)
                    : SpotterfyTheme.overlay(0.1),
              ),
            ),
            child: Icon(
              icon,
              size: 19,
              color: active ? SpotterfyTheme.primary : SpotterfyTheme.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar for the playlist owner: their photo when it is known, otherwise a
/// generic person icon, and always opens their profile.
class _OwnerProfileButton extends StatelessWidget {
  final String photoUrl;
  final String displayName;
  final VoidCallback onTap;

  const _OwnerProfileButton({
    required this.photoUrl,
    required this.displayName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: displayName.isEmpty ? 'View profile' : 'View $displayName',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SpotterfyTheme.card,
            border: Border.all(
              color: SpotterfyTheme.primary.withValues(alpha: 0.35),
            ),
            image: photoUrl.isNotEmpty
                ? DecorationImage(
                    image: NetworkImage(photoUrl),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: photoUrl.isEmpty
              ? const Icon(Icons.person, size: 18, color: Color(0xFFB3B3B3))
              : null,
        ),
      ),
    );
  }
}

class PlaylistDetailScreen extends StatefulWidget {
  final PlaylistModel playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  late PlaylistModel _playlist;

  /// Per-playlist view state, so leaving a playlist and coming back lands you
  /// on the same filter, sort and shuffle you left it with.
  ///
  /// Held by MainScreen's library tab rather than this screen's State, which is
  /// disposed on pop. Scroll offset and selection are not preserved - those are
  /// tied to a live [State] - but the view controls are what users actually
  /// expect to stick.
  static final Map<String, _PlaylistViewState> _viewStates = {};

  static _PlaylistViewState _stateFor(String playlistId) =>
      _viewStates.putIfAbsent(playlistId, _PlaylistViewState.new);

  final ScrollController _scrollController = ScrollController();
  bool _syncing = false;

  /// Owner of the playlist, when it came from another user.
  String? get _ownerUid {
    final uid = _playlist.creatorUid;
    return uid.isEmpty ? null : uid;
  }

  String? get _myUid => context.read<AuthProvider>().user?.uid;

  /// Resolved lazily for the profile button in the app bar.
  Map<String, String>? _ownerProfile;
  bool _loadingOwner = false;

  /// Ids of the tracks the user has selected via long-press.
  final Set<String> _selectedIds = {};

  // --- Search / sort / shuffle --------------------------------------------
  //
  // These survive leaving the page. The playlist detail screen is a State
  // object that is disposed when popped, and users flip back to a playlist,
  // filter it, and come back constantly - losing the filter each time is the
  // kind of thing that makes a playlist feel like it forgot what you wanted.

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  /// Live view settings, restored on entry and written back on exit.
  late _PlaylistViewState _view;

  String get _query => _view.query;
  _PlaylistSort get _sort => _view.sort;
  bool get _shuffleOn => _view.shuffle;

  /// Stable order of the playlist's tracks, decided once per build of the
  /// visible list. Sorted views keep a reference to the original position so
  /// "play" still queues the whole playlist in playlist order.
  List<TrackModel> get _visibleTracks {
    final q = _query.trim().toLowerCase();
    var out = _playlist.tracks;
    if (q.isNotEmpty) {
      out = out
          .where(
            (t) =>
                t.title.toLowerCase().contains(q) ||
                t.artists.toLowerCase().contains(q) ||
                t.album.toLowerCase().contains(q),
          )
          .toList();
    }
    switch (_sort) {
      case _PlaylistSort.custom:
        break;
      case _PlaylistSort.title:
        out = [...out]
          ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );
      case _PlaylistSort.artist:
        out = [...out]
          ..sort(
            (a, b) =>
                a.artists.toLowerCase().compareTo(b.artists.toLowerCase()),
          );
      case _PlaylistSort.duration:
        out = [...out]..sort((a, b) => a.durationMs.compareTo(b.durationMs));
    }
    return out;
  }

  /// The order playback should use: the whole playlist in its original order,
  /// which is what a listener expects even when the list is sorted or filtered.
  List<TrackModel> get _playbackOrder => _playlist.tracks;

  void _setSort(_PlaylistSort s) {
    HapticFeedback.selectionClick();
    setState(() => _view.sort = s);
  }

  void _toggleShuffle() {
    HapticFeedback.selectionClick();
    setState(() => _view.shuffle = !_view.shuffle);
  }

  void _setQuery(String value) => setState(() => _view.query = value);

  /// Resets the filter/sort to how the playlist was saved.
  void _resetView() {
    _searchController.clear();
    setState(() {
      _view.query = '';
      _view.sort = _PlaylistSort.custom;
      _view.shuffle = false;
    });
  }

  bool get _selecting => _selectedIds.isNotEmpty;

  List<TrackModel> get _selectedTracks =>
      _playlist.tracks.where((t) => _selectedIds.contains(t.id)).toList();

  void _toggleSelection(TrackModel track) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selectedIds.remove(track.id)) _selectedIds.add(track.id);
    });
  }

  void _clearSelection() => setState(_selectedIds.clear);

  void _selectAll() => setState(() {
    _selectedIds
      ..clear()
      ..addAll(_playlist.tracks.map((t) => t.id));
  });

  @override
  void initState() {
    super.initState();
    _playlist = widget.playlist;
    _view = _stateFor(_playlist.id);
    // Put the restored query in the field before the first build so the text and
    // the filter can never disagree.
    if (_view.query.isNotEmpty) {
      _searchController.text = _view.query;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _maybeSyncTracks();
        _loadOwnerProfile();
      }
    });
  }

  @override
  void didUpdateWidget(covariant PlaylistDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlist.id == widget.playlist.id) return;
    // Switched to a different playlist via the same route; the saved view
    // belongs to the old one, so adopt the new playlist's.
    _view = _stateFor(widget.playlist.id);
    _playlist = widget.playlist;
    _searchController.text = _view.query;
    setState(() {});
  }

  /// Fetches the owner's public profile so the app-bar button can show their
  /// name/avatar. Failures are silent - the button still works, it just shows
  /// the generic avatar.
  Future<void> _loadOwnerProfile() async {
    final uid = _ownerUid;
    if (uid == null || uid == _myUid || _ownerProfile != null) return;
    setState(() => _loadingOwner = true);
    final profile = await PlaylistService().getUserProfile(uid);
    if (!mounted || uid != _ownerUid) return;
    setState(() {
      _ownerProfile = profile;
      _loadingOwner = false;
    });
  }

  @override
  void dispose() {
    // The view settings live in the per-playlist map rather than in this State,
    // so they outlive the screen; only the controllers are ours to release.
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _maybeSyncTracks() async {
    if (_playlist.isCustom) return;

    final needsSync =
        _playlist.lastTrackSync == null ||
        _playlist.tracks.isEmpty ||
        DateTime.now().difference(_playlist.lastTrackSync!).inMinutes >= 5;

    if (!needsSync) return;
    await _forceSyncTracks(showFeedback: false);
  }

  Future<void> _forceSyncTracks({bool showFeedback = true}) async {
    if (_playlist.isCustom) return;

    setState(() => _syncing = true);

    final playlistUrl = _playlist.spotifyUrl.isNotEmpty
        ? _playlist.spotifyUrl
        : 'https://open.spotify.com/playlist/${_playlist.id}';

    final scraped = await ApiService.scrapePlaylist(
      playlistUrl,
      service: _playlist.source,
    );

    if (!mounted) return;

    if (scraped != null) {
      final int previousCount = _playlist.tracks.length;
      final bool hasChanged =
          previousCount != scraped.tracks.length ||
          _playlist.name != scraped.name ||
          (scraped.tracks.isNotEmpty &&
              previousCount > 0 &&
              scraped.tracks.first.id != _playlist.tracks.first.id);

      setState(() {
        _playlist.name = scraped.name.isNotEmpty
            ? scraped.name
            : _playlist.name;
        _playlist.tracks = scraped.tracks;
        if (scraped.tracks.isNotEmpty) {
          _playlist.coverUrl = scraped.tracks.first.cover;
        }
        _playlist.lastTrackSync = DateTime.now();
        _syncing = false;
      });

      final auth = context.read<AuthProvider>();
      if (auth.user != null) {
        try {
          await context.read<PlaylistProvider>().syncPlaylistTracks(
            auth.user!.uid,
            _playlist.id,
            scraped.tracks,
          );
        } catch (e) {
          // Cloud sync is best-effort (e.g. legacy doc without creatorUid) —
          // local tracks are already updated above, so don't crash.
          debugPrint('syncPlaylistTracks failed (non-fatal): $e');
        }
      }

      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hasChanged
                  ? 'Playlist updated (${scraped.tracks.length} tracks)'
                  : 'Playlist is up to date (${scraped.tracks.length} tracks)',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      setState(() => _syncing = false);
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to check for playlist updates')),
        );
      }
    }
  }

  /// Search field, sort picker and shuffle toggle.
  ///
  /// Sits between the header and the list so the sort and filter state stays
  /// visible while scrolling, which is what makes it obvious why a list is
  /// currently short.
  Widget _viewControls() {
    final visible = _visibleTracks;
    final filtering = _query.trim().isNotEmpty;
    final viewIsDefault = !filtering && _sort == _PlaylistSort.custom;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    style: TextStyle(color: SpotterfyTheme.text, fontSize: 14),
                    cursorColor: SpotterfyTheme.primary,
                    textInputAction: TextInputAction.search,
                    onChanged: _setQuery,
                    decoration: InputDecoration(
                      hintText: 'Search in playlist',
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
                                _setQuery('');
                              },
                            ),
                      isDense: true,
                      filled: true,
                      fillColor: SpotterfyTheme.overlay(0.05),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
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
                ),
              ),
              const SizedBox(width: 8),
              _SquareButton(
                icon: Icons.sort_rounded,
                tooltip: 'Sort',
                active: !viewIsDefault,
                onPressed: _showSortSheet,
              ),
              const SizedBox(width: 8),
              _SquareButton(
                icon: Icons.shuffle_rounded,
                tooltip: 'Shuffle',
                active: _shuffleOn,
                onPressed: _toggleShuffle,
              ),
            ],
          ),
          if (filtering || _sort != _PlaylistSort.custom) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${visible.length} of ${_playlist.tracks.length} '
                  '${_playlist.tracks.length == 1 ? 'song' : 'songs'}'
                  '${_sort == _PlaylistSort.custom ? '' : ' • ${_sort.label}'}',
                  style: TextStyle(
                    color: SpotterfyTheme.mutedDark,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _resetView,
                  icon: Icon(
                    Icons.restart_alt,
                    size: 14,
                    color: SpotterfyTheme.primary,
                  ),
                  label: Text(
                    'Reset',
                    style: TextStyle(
                      color: SpotterfyTheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: SpotterfyTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: SpotterfyTheme.overlay(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Sort by',
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            for (final s in _PlaylistSort.values)
              RadioListTile<_PlaylistSort>(
                value: s,
                // ignore: deprecated_member_use
                groupValue: _sort,
                // ignore: deprecated_member_use
                onChanged: (v) {
                  if (v == null) return;
                  Navigator.pop(sheetCtx);
                  _setSort(v);
                },
                dense: true,
                activeColor: SpotterfyTheme.primary,
                title: Text(
                  s.label,
                  style: TextStyle(color: SpotterfyTheme.text, fontSize: 14),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SwipeBackWrapper(
      child: Scaffold(
        backgroundColor: SpotterfyTheme.pageBackground,
        // No footer of its own. This screen lives on its tab's navigation stack
        // inside MainScreen, so MainScreen's navbar + mini player are already
        // visible underneath and stay tappable from here. Rendering a second
        // copy (as this used to) drew the mini player and nav bar twice.
        //
        // Because of that, the track list carries bottom padding to clear the
        // shared mini player rather than relying on a Scaffold inset.
        appBar: _selecting
            ? AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(Icons.close, color: SpotterfyTheme.text),
                  tooltip: 'Clear selection',
                  onPressed: _clearSelection,
                ),
                title: Text(
                  '${_selectedIds.length} selected',
                  style: TextStyle(
                    color: SpotterfyTheme.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: Icon(
                      Icons.playlist_add_check,
                      color: SpotterfyTheme.text,
                    ),
                    tooltip: 'Select all',
                    onPressed: _selectAll,
                  ),
                  IconButton(
                    icon: Icon(Icons.play_arrow, color: SpotterfyTheme.text),
                    tooltip: 'Play selection',
                    onPressed: () => _playSelection(context),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.download_outlined,
                      color: SpotterfyTheme.text,
                    ),
                    tooltip: 'Download selection',
                    onPressed: () =>
                        _downloadSelectedOrAll(context, wholeList: false),
                  ),
                  IconButton(
                    icon: Icon(Icons.queue_music, color: SpotterfyTheme.text),
                    tooltip: 'Add selection to queue',
                    onPressed: () => _queueSelection(context),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: SpotterfyTheme.text,
                    ),
                    tooltip: 'Delete downloads of selection',
                    onPressed: () =>
                        _deleteDownloadsOfSelection(context, wholeList: false),
                  ),
                  const SizedBox(width: 4),
                ],
              )
            : AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                title: Text(
                  _playlist.displayName,
                  style: TextStyle(color: SpotterfyTheme.text, fontSize: 18),
                ),
                actions: [
                  // Profile button for a playlist someone else created, so you can see
                  // who owns it and browse everything else they have shared.
                  if (_ownerUid != null &&
                      _ownerUid != _myUid &&
                      !_loadingOwner)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _OwnerProfileButton(
                        photoUrl: _ownerProfile?['photoUrl'] ?? '',
                        displayName: _ownerProfile?['displayName'] ?? '',
                        onTap: () => Navigator.push(
                          context,
                          swipeRoute(ProfileScreen(uid: _ownerUid)),
                        ),
                      ),
                    ),
                  if (!_playlist.isCustom)
                    IconButton(
                      icon: _syncing
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
                      onPressed: _syncing
                          ? null
                          : () => _forceSyncTracks(showFeedback: true),
                    ),
                  if (_playlist.isCustom)
                    IconButton(
                      icon: Icon(Icons.share, color: SpotterfyTheme.mutedDark),
                      onPressed: () => _sharePlaylist(context),
                    ),
                  // Whole-playlist download / delete, for when you don't want to
                  // pick songs one by one.
                  if (_playlist.tracks.isNotEmpty) ...[
                    IconButton(
                      icon: Icon(
                        Icons.download_outlined,
                        color: SpotterfyTheme.mutedDark,
                      ),
                      tooltip: 'Download whole playlist',
                      onPressed: () =>
                          _downloadSelectedOrAll(context, wholeList: true),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.download_done,
                        color: SpotterfyTheme.mutedDark,
                      ),
                      tooltip: 'Delete downloaded songs',
                      onPressed: () =>
                          _deleteDownloadsOfSelection(context, wholeList: true),
                    ),
                  ],
                ],
              ),
        body: _playlist.tracks.isEmpty
            ? RefreshIndicator(
                onRefresh: () => _forceSyncTracks(showFeedback: true),
                color: SpotterfyTheme.primary,
                backgroundColor: SpotterfyTheme.surface,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.7,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.music_note_outlined,
                              color: SpotterfyTheme.mutedDark,
                              size: 64,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No tracks found',
                              style: TextStyle(
                                color: SpotterfyTheme.text,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_playlist.isCustom)
                              ElevatedButton(
                                onPressed: () => _addTrack(context),
                                child: const Text(
                                  'Add tracks from your library',
                                ),
                              )
                            else
                              TextButton.icon(
                                onPressed: () =>
                                    _forceSyncTracks(showFeedback: true),
                                icon: Icon(
                                  Icons.refresh,
                                  color: SpotterfyTheme.primary,
                                ),
                                label: Text(
                                  'Fetch Tracks',
                                  style: TextStyle(
                                    color: SpotterfyTheme.primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () => _forceSyncTracks(showFeedback: true),
                color: SpotterfyTheme.primary,
                backgroundColor: SpotterfyTheme.surface,
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: _PlaylistHeader(
                        playlist: _playlist,
                        onPlay: _playAll,
                        onShuffle: _shuffleAll,
                        isMine:
                            _playlist.isUsersOwn ||
                            (_playlist.creatorUid.isNotEmpty &&
                                _playlist.creatorUid == _myUid),
                      ),
                    ),
                    SliverToBoxAdapter(child: _viewControls()),
                    if (_visibleTracks.isEmpty)
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 320,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  color: SpotterfyTheme.mutedDark,
                                  size: 44,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No matching songs',
                                  style: TextStyle(
                                    color: SpotterfyTheme.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Nothing in this playlist matches '
                                  '"${_query.trim()}"',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: SpotterfyTheme.mutedDark,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                TextButton(
                                  onPressed: _resetView,
                                  child: Text(
                                    'Clear search and sort',
                                    style: TextStyle(
                                      color: SpotterfyTheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) {
                            final track = _visibleTracks[i];
                            final player = context.watch<PlayerProvider>();
                            final downloads = context.watch<DownloadProvider>();
                            final isPlaying =
                                player.currentTrack?.id == track.id &&
                                player.isPlaying;
                            return TrackTile(
                              track: track,
                              isSelected: player.currentTrack?.id == track.id,
                              isPlaying: isPlaying,
                              // Long press opens multi-select; in selection mode
                              // a tap toggles instead of playing.
                              onLongPress: () => _toggleSelection(track),
                              selectionMode: _selecting,
                              selected: _selectedIds.contains(track.id),
                              isDownloaded: downloads.isDownloaded(track.id),
                              isDownloading:
                                  downloads.states[track.id] ==
                                  DownloadState.downloading,
                              onDownload: () => _toggleDownload(context, track),
                              onPlay: _selecting
                                  ? () => _toggleSelection(track)
                                  // The row index is into the *visible* list, so
                                  // the real position in playlist order is
                                  // resolved from the track itself. Otherwise
                                  // tapping row 2 of a sorted list would start
                                  // playback from whichever song happens to sit
                                  // second in the original order.
                                  : () => _playTrack(
                                      context,
                                      track,
                                      _playbackOrder.indexWhere(
                                        (t) => t.id == track.id,
                                      ),
                                    ),
                            );
                          },
                          childCount: _visibleTracks.length,
                        ),
                      ),
                    SliverToBoxAdapter(child: SizedBox(height: 92)),
                  ],
                ),
              ),
      ),
    );
  }

  /// Downloads a track, or removes the local copy when it already has one.
  Future<void> _toggleDownload(BuildContext context, TrackModel track) async {
    final prov = context.read<DownloadProvider>();
    final messenger = ScaffoldMessenger.of(context);
    if (prov.isDownloaded(track.id)) {
      await prov.remove(track.id);
      messenger.showSnackBar(
        SnackBar(content: Text('Removed download of "${track.title}"')),
      );
      return;
    }
    final ok = await prov.download(track);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Downloaded "${track.title}"'
              : (prov.lastError ?? 'Download failed'),
        ),
      ),
    );
  }

  /// Downloads the current selection (or every track when nothing is selected).
  Future<void> _downloadSelectedOrAll(
    BuildContext context, {
    required bool wholeList,
  }) async {
    final tracks = wholeList ? _playlist.tracks : _selectedTracks;
    if (tracks.isEmpty) return;
    final prov = context.read<DownloadProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final missing = tracks.where((t) => !prov.isDownloaded(t.id)).toList();
    if (missing.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Already downloaded')),
      );
      return;
    }

    // Long jobs need to be cancellable, and one tap shouldn't fire 30 server
    // requests by surprise.
    final start = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotterfyTheme.surface,
        title: Text(
          'Download ${missing.length} ${missing.length == 1 ? 'song' : 'songs'}?',
          style: TextStyle(
            color: SpotterfyTheme.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'This downloads them for offline listening. They will play from your '
          'device instead of streaming.',
          style: TextStyle(color: Color(0xFFB3B3B3), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFFB3B3B3)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Download',
              style: TextStyle(color: SpotterfyTheme.primary),
            ),
          ),
        ],
      ),
    );
    if (start != true) return;

    final ok = await prov.downloadMany(missing);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok == missing.length
              ? 'Downloaded $ok ${ok == 1 ? 'song' : 'songs'}'
              : 'Downloaded $ok of ${missing.length}',
        ),
      ),
    );
  }

  /// Deletes the local copies of the selected songs.
  Future<void> _deleteDownloadsOfSelection(
    BuildContext context, {
    required bool wholeList,
  }) async {
    final prov = context.read<DownloadProvider>();
    final ids = (wholeList ? _playlist.tracks : _selectedTracks)
        .map((t) => t.id)
        .where(prov.isDownloaded)
        .toList();
    if (ids.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nothing downloaded here')));
      return;
    }
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
          'Removes the downloaded files for ${ids.length} '
          '${ids.length == 1 ? 'song' : 'songs'} from this device. The playlist '
          'is not affected.',
          style: const TextStyle(color: Color(0xFFB3B3B3), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFFB3B3B3)),
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
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Removed ${ids.length} ${ids.length == 1 ? 'download' : 'downloads'}',
        ),
      ),
    );
  }

  /// Plays the selection, or the whole playlist when nothing is selected.
  void _playSelection(BuildContext context) {
    final tracks = _selecting ? _selectedTracks : _playlist.tracks;
    if (tracks.isEmpty) return;
    final player = context.read<PlayerProvider>();
    player.setQueue(tracks, startIndex: 0);
    player.play(tracks.first, queue: tracks);
    _clearSelection();
  }

  /// Appends the selection (or the whole playlist) to the queue.
  void _queueSelection(BuildContext context) {
    final tracks = _selecting ? _selectedTracks : _playlist.tracks;
    if (tracks.isEmpty) return;
    final player = context.read<PlayerProvider>();
    final q = [...player.queue];
    final start = q.length;
    q.addAll(tracks);
    player.setQueue(q, startIndex: start == 0 ? 0 : player.currentIndex);
    final n = tracks.length;
    _clearSelection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${n == 1 ? '1 song' : '$n songs'} to queue'),
      ),
    );
  }

  void _playTrack(BuildContext context, TrackModel track, int index) {
    // Queues playlist order, not the on-screen order: sorting and searching are
    // ways of finding a song, not a claim that the playlist is now ordered that
    // way. So "next" keeps following the playlist as saved.
    final order = _playbackOrder;
    if (order.isEmpty) return;
    final safeIndex = index < 0 ? 0 : index.clamp(0, order.length - 1);
    final player = context.read<PlayerProvider>();
    player.setQueue(order, startIndex: safeIndex);
    player.play(track, queue: order);
    // Same rise/fall animation as opening from the mini player, but on the ROOT
    // navigator: the player is full-screen, so it must cover the bottom nav
    // rather than sit above it inside this tab's stack.
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(nowPlayingRoute(const PlayerScreen()));
  }

  void _playAll() {
    final tracks = _playbackOrder;
    if (tracks.isEmpty) return;
    // With shuffle armed, Play starts somewhere random rather than at the top.
    if (_shuffleOn) {
      _shuffleAll();
      return;
    }
    _playTrack(context, tracks.first, 0);
  }

  /// Plays the playlist from a random track, but keeps the original order.
  ///
  /// Shuffling the queue itself would leave the track list scrambled once the
  /// user hit "next", which is rarely what "shuffle" is meant to mean.
  void _shuffleAll() {
    final tracks = _playbackOrder;
    if (tracks.isEmpty) return;
    // The index has to match the track, or playback would start on the first
    // song while the queue claims it's somewhere else.
    final start = Random().nextInt(tracks.length);
    _playTrack(context, tracks[start], start);
  }

  void _sharePlaylist(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Share feature coming soon')));
  }

  void _addTrack(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add track feature coming soon')),
    );
  }
}
