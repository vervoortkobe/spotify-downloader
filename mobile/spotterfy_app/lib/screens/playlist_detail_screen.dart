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
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/player_screen.dart';
import 'package:spotterfy_app/screens/profile_screen.dart';

/// App-bar button identifying who owns a shared playlist. Shows the owner's
/// avatar when it is known, otherwise a generic person icon, and always opens
/// their profile.
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
            color: const Color(0xFF282828),
            border: Border.all(
              color: const Color(0xFF10b981).withValues(alpha: 0.35),
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _maybeSyncTracks();
        _loadOwnerProfile();
      }
    });
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

  @override
  Widget build(BuildContext context) {
    return SwipeBackWrapper(
      child: Scaffold(
        backgroundColor: const Color(0xFF07110b),
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
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Clear selection',
                  onPressed: _clearSelection,
                ),
                title: Text(
                  '${_selectedIds.length} selected',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(
                      Icons.playlist_add_check,
                      color: Colors.white,
                    ),
                    tooltip: 'Select all',
                    onPressed: _selectAll,
                  ),
                  IconButton(
                    icon: const Icon(Icons.play_arrow, color: Colors.white),
                    tooltip: 'Play selection',
                    onPressed: () => _playSelection(context),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.download_outlined,
                      color: Colors.white,
                    ),
                    tooltip: 'Download selection',
                    onPressed: () =>
                        _downloadSelectedOrAll(context, wholeList: false),
                  ),
                  IconButton(
                    icon: const Icon(Icons.queue_music, color: Colors.white),
                    tooltip: 'Add selection to queue',
                    onPressed: () => _queueSelection(context),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white),
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
                  _playlist.name,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
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
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF10b981),
                              ),
                            )
                          : const Icon(Icons.sync, color: Color(0xFFa1a1aa)),
                      tooltip: 'Check for updates',
                      onPressed: _syncing
                          ? null
                          : () => _forceSyncTracks(showFeedback: true),
                    ),
                  if (_playlist.isCustom)
                    IconButton(
                      icon: const Icon(Icons.share, color: Color(0xFFa1a1aa)),
                      onPressed: () => _sharePlaylist(context),
                    ),
                  // Whole-playlist download / delete, for when you don't want to
                  // pick songs one by one.
                  if (_playlist.tracks.isNotEmpty) ...[
                    IconButton(
                      icon: const Icon(
                        Icons.download_outlined,
                        color: Color(0xFFa1a1aa),
                      ),
                      tooltip: 'Download whole playlist',
                      onPressed: () =>
                          _downloadSelectedOrAll(context, wholeList: true),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.download_done,
                        color: Color(0xFFa1a1aa),
                      ),
                      tooltip: 'Delete downloaded songs',
                      onPressed: () =>
                          _deleteDownloadsOfSelection(context, wholeList: true),
                    ),
                  ],
                ],
              ),
        body: Column(
          children: [
            if (_playlist.tracks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final player = context.read<PlayerProvider>();
                      player.setQueue(_playlist.tracks, startIndex: 0);
                      player.play(
                        _playlist.tracks.first,
                        queue: _playlist.tracks,
                      );
                    },
                    icon: const Icon(Icons.play_arrow, color: Colors.white),
                    label: Text(
                      'Play • ${_playlist.tracks.length} tracks',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10b981),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _forceSyncTracks(showFeedback: true),
                color: const Color(0xFF10b981),
                backgroundColor: const Color(0xFF0f1d17),
                child: _playlist.tracks.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.7,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.music_note_outlined,
                                    color: Color(0xFFa1a1aa),
                                    size: 64,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'No tracks found',
                                    style: TextStyle(
                                      color: Colors.white,
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
                                      icon: const Icon(
                                        Icons.refresh,
                                        color: Color(0xFF10b981),
                                      ),
                                      label: const Text(
                                        'Fetch Tracks',
                                        style: TextStyle(
                                          color: Color(0xFF10b981),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : RawScrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        trackVisibility: false,
                        thickness: 4,
                        radius: const Radius.circular(8),
                        thumbColor: const Color(
                          0xFF10b981,
                        ).withValues(alpha: 0.5),
                        child: ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          // Clears the shared mini player that MainScreen
                          // overlays at the bottom of this tab's stack. There is
                          // no Scaffold bottomNavigationBar inset here, so the
                          // room has to be added to the list itself.
                          padding: const EdgeInsets.only(bottom: 92),
                          itemCount: _playlist.tracks.length,
                          itemBuilder: (_, i) {
                            final track = _playlist.tracks[i];
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
                                  : () => _playTrack(context, track, i),
                            );
                          },
                        ),
                      ),
              ),
            ),
          ],
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
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          'Download ${missing.length} ${missing.length == 1 ? 'song' : 'songs'}?',
          style: const TextStyle(
            color: Colors.white,
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
            child: const Text(
              'Download',
              style: TextStyle(color: Color(0xFF10b981)),
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
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Delete downloads?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
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
    final player = context.read<PlayerProvider>();
    player.setQueue(_playlist.tracks, startIndex: index);
    player.play(track, queue: _playlist.tracks);
    // Same rise/fall animation as opening from the mini player, but on the ROOT
    // navigator: the player is full-screen, so it must cover the bottom nav
    // rather than sit above it inside this tab's stack.
    Navigator.of(
      context,
      rootNavigator: true,
    ).push(nowPlayingRoute(const PlayerScreen()));
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
