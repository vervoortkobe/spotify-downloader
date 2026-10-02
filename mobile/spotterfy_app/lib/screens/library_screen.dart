import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/playlist_card.dart';
import 'package:spotterfy_app/widgets/playlist_play_button.dart';
import 'package:spotterfy_app/widgets/storage_cover.dart';
import 'package:spotterfy_app/widgets/track_tile.dart';
import 'playlist_detail_screen.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/widgets/base_page.dart';
import 'package:spotterfy_app/widgets/no_results_view.dart';

/// One row in the storage root list: a folder treated as a playlist, or the
/// loose tracks sitting directly in a scan root.
class _StorageEntry {
  final String name;
  final List<File> songs;

  /// Absolute folder path, or null for loose tracks (not drillable).
  final String? folderPath;

  const _StorageEntry({
    required this.name,
    required this.songs,
    required this.folderPath,
  });
}

/// Thin indeterminate bar shown while a background storage rescan runs. Sits at
/// the very top of the tab so it never covers the list.
class _StorageScanBar extends StatelessWidget {
  const _StorageScanBar();

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      minHeight: 2,
      backgroundColor: Colors.transparent,
      valueColor: AlwaysStoppedAnimation(SpotterfyTheme.primary),
    );
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _query = '';
  final List<String> _folderStack = [];

  /// One sort per tab, each applied only to its own list.
  ///
  /// Kept separate rather than shared: "Recently added" is meaningless for
  /// folders on disk, and switching tabs should not silently reorder the other
  /// one.
  _LibrarySort _importedSort = _LibrarySort.recent;
  _LibrarySort _storageSort = _LibrarySort.name;

  /// Imported-tab orderings. "Recently added" leads because that is how the
  /// list arrives; the rest are explicit re-orders.
  static const List<_LibrarySort> _importedSorts = [
    _LibrarySort.recent,
    _LibrarySort.oldest,
    _LibrarySort.name,
    _LibrarySort.artist,
    _LibrarySort.songs,
    _LibrarySort.length,
  ];

  /// Storage-tab orderings.
  ///
  /// Deliberately narrower than the Imported tab's: folders have no creation
  /// date and no owner, and a total length across a folder tree is not a number
  /// anyone can act on.
  static const List<_LibrarySort> _storageSorts = [
    _LibrarySort.name,
    _LibrarySort.songs,
    _LibrarySort.mostSongs,
  ];

  void _setSort(_LibrarySort s) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_tabController.index == 0) {
        _importedSort = s;
      } else {
        _storageSort = s;
      }
    });
  }

  /// Bottom padding that clears the mini player, which is overlaid on the body
  /// at the bottom. (The 80px nav bar is already inset by the Scaffold's
  /// `bottomNavigationBar`, so it needs no extra room here.)
  static const double _bottomInset = 100;

  /// Last completed storage scan.
  ///
  /// Held in state on purpose: the scan used to be created inline in `build()`,
  /// so the recursive walk restarted on *every* rebuild - and the storage list
  /// contains `context.watch<PlayerProvider>()` calls, meaning each playback
  /// state change kicked off another full walk.
  List<File>? _storageFiles;

  /// True once a scan has completed, so we can tell "first load" apart from
  /// "rescanning with results already on screen".
  bool _storageLoaded = false;

  /// A rescan is in flight. Previous results stay visible, so re-opening the
  /// tab shows the list immediately instead of a blocking spinner.
  bool _storageScanning = false;

  /// Local file path -> real length in ms.
  ///
  /// A storage [TrackModel] is built from a path, so it starts with
  /// `durationMs: 0`. Populated by [_rememberStorageDuration] as tracks are
  /// played - the player writes the real length back once it has loaded the
  /// file. Deliberately *not* pre-measured across the whole library: reading
  /// every file's tags is expensive enough to freeze the UI on large libraries.
  final Map<String, int> _storageDurations = {};

  /// Memo for [_tracksForFiles]. Building a TrackModel per song, for every
  /// folder, on every rebuild is the dominant cost of this tab - and the list
  /// rebuilds on every playback tick. Bumped by [_memoGeneration] whenever the
  /// scan changes so stale entries can never be served.
  final Map<String, List<TrackModel>> _tracksMemo = {};
  int _memoGeneration = 0;

  /// Cached permission probe - re-ran on every rebuild before, which on its own
  /// was slow enough to be visible as a stall.
  bool? _storagePermGranted;
  bool _permPending = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _searchController.addListener(
      () =>
          setState(() => _query = _searchController.text.trim().toLowerCase()),
    );
    // Auto-sync playlists: show cache instantly, then fetch remote.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensurePlaylistsLoaded();
      _checkStoragePerm();
    });
  }

  void _onTabChanged() {
    if (!mounted) return;
    if (_tabController.indexIsChanging ||
        !_tabController.animation!.isCompleted) {
      return;
    }
    setState(() {});
    // Opening the Storage tab refreshes in the background so new/deleted
    // folders are picked up, but the already-loaded list never blanks out.
    if (_tabController.index == 1 && _storagePermGranted == true) {
      _startStorageScan();
    }
  }

  Future<void> _checkStoragePerm() async {
    final granted = await _hasStoragePerm();
    if (!mounted) return;
    setState(() {
      _storagePermGranted = granted;
      _permPending = false;
    });
    if (granted) _startStorageScan();
  }

  /// Rescans storage, keeping the current list on screen the whole time.
  ///
  /// Guarded so rapid tab switching can't start overlapping walks, which is
  /// what made the tab feel like it hung.
  Future<void> _startStorageScan() async {
    if (_storageScanning || !mounted) return;
    setState(() => _storageScanning = true);
    try {
      final files = (await _listMusicFiles()).whereType<File>().toList();
      if (!mounted) return;
      // Invalidate memoised track lists: the folder contents just changed.
      _memoGeneration++;
      setState(() {
        _storageFiles = files;
        _storageLoaded = true;
        _storageScanning = false;
      });
    } catch (_) {
      if (mounted) setState(() => _storageScanning = false);
    }
  }

  Future<void> _ensurePlaylistsLoaded() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final prov = context.read<PlaylistProvider>();
    if (auth.user != null && prov.playlists.isEmpty && !prov.isLoading) {
      await prov.loadPlaylists(auth.user!.uid);
    }
  }

  Future<void> _onRefreshPlaylists() async {
    final auth = context.read<AuthProvider>();
    final prov = context.read<PlaylistProvider>();
    if (auth.user != null) {
      await prov.loadPlaylists(auth.user!.uid, forceRefresh: true);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BasePageScaffold(
      searchController: _searchController,
      searchHint: 'Search playlists or storage',
      query: _query,
      // Extra trailing icon for Library: + to import (visible only on Playlists tab) -> Storage has no icon so search bar uses full width like Discover/Search
      action: _tabController.index == 0
          ? IconButton(
              icon: Icon(Icons.add, color: SpotterfyTheme.muted, size: 20),
              onPressed: () => _showImportSheet(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            )
          : null,
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: SpotterfyTheme.muted,
            indicatorColor: SpotterfyTheme.primary,
            dividerColor: Colors.transparent,
            // Only the label lives in the tab now. The sort control used to sit
            // inside the label next to the text, where it was cramped against the
            // tab edge and easy to miss; it has its own strip below the tabs where
            // it can show *which* order is active, not just that a sort exists.
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            tabs: const [
              Tab(height: 52, child: Text('Imported')),
              Tab(height: 52, child: Text('Storage')),
            ],
          ),
          // Sort strip. Reads the active tab so the pill always describes the
          // list actually on screen.
          Builder(
            builder: (context) => _SortStrip(
              onImported: _tabController.index == 0,
              importedSort: _importedSort,
              importedOptions: _importedSorts,
              storageSort: _storageSort,
              storageOptions: _storageSorts,
              onPicked: _setSort,
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const ClampingScrollPhysics(),
              children: [
                _playlistsTab(context.watch<PlaylistProvider>()),
                _storageTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Applies the Imported tab's sort.
  ///
  /// Takes a copy so the provider's own list order is never mutated - it is the
  /// order tracks were added in, which `recent` relies on and which a
  /// sort must not disturb.
  List<PlaylistModel> _sortImported(List<PlaylistModel> list) {
    final out = List<PlaylistModel>.of(list);
    int byName(PlaylistModel a, PlaylistModel b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    int totalMs(PlaylistModel p) =>
        p.tracks.fold<int>(0, (n, t) => n + t.durationMs);
    switch (_importedSort) {
      case _LibrarySort.recent:
        out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _LibrarySort.oldest:
        out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case _LibrarySort.name:
        out.sort(byName);
      case _LibrarySort.artist:
        out.sort(
          (a, b) => a.owner.toLowerCase().compareTo(b.owner.toLowerCase()),
        );
      case _LibrarySort.songs:
        out.sort((a, b) => a.tracks.length.compareTo(b.tracks.length));
      case _LibrarySort.mostSongs:
        out.sort((a, b) => b.tracks.length.compareTo(a.tracks.length));
      case _LibrarySort.length:
        out.sort((a, b) => totalMs(a).compareTo(totalMs(b)));
    }
    return out;
  }

  Widget _playlistsTab(PlaylistProvider prov) {
    // "My library" is both what you created and what was shared with you, so
    // both lists are shown here. Ownership is what decides what deleting does.
    var list = [...prov.playlists, ...prov.sharedPlaylists];
    if (_query.isNotEmpty) {
      list = list
          .where(
            (p) =>
                p.displayName.toLowerCase().contains(_query) ||
                p.name.toLowerCase().contains(_query) ||
                p.tracks.any((t) => t.title.toLowerCase().contains(_query)),
          )
          .toList();
    }
    list = _sortImported(list);
    // Show loading spinner over cache while first sync runs
    if (prov.isLoading && list.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: SpotterfyTheme.primary),
      );
    }
    if (list.isEmpty) {
      // A search that matched nothing uses the shared panel; a genuinely empty
      // library keeps its own "pull to refresh / import" call to action.
      if (_query.isNotEmpty) {
        return NoResultsView(
          query: _query,
          icon: Icons.library_music_outlined,
          message: 'No playlists in your library match "$_query".',
          actionLabel: 'Clear search',
          onAction: () => _searchController.clear(),
        );
      }
      return RefreshIndicator(
        onRefresh: _onRefreshPlaylists,
        color: SpotterfyTheme.primary,
        backgroundColor: SpotterfyTheme.surface,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 100, top: 32),
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.library_music,
                    size: 48,
                    color: SpotterfyTheme.muted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No playlists yet',
                    style: TextStyle(
                      color: SpotterfyTheme.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pull down to refresh or tap + to import',
                    style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _onRefreshPlaylists,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _onRefreshPlaylists,
      color: SpotterfyTheme.primary,
      backgroundColor: SpotterfyTheme.surface,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        // Bottom inset so the last playlist clears the mini player.
        padding: const EdgeInsets.fromLTRB(16, 8, 16, _bottomInset),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final p = list[i];
          final curTrack = context.watch<PlayerProvider>().currentTrack;
          final isPlayingNow = context.watch<PlayerProvider>().isPlaying;
          final isSource =
              curTrack != null && p.tracks.any((t) => t.id == curTrack.id);
          return PlaylistCard(
            playlist: p,
            isActive: isSource,
            isPlaying: isSource && isPlayingNow,
            onTap: () => Navigator.push(
              context,
              swipeRoute(PlaylistDetailScreen(playlist: p)),
            ),
            onPlay: p.tracks.isEmpty
                ? null
                : () async {
                    final curTrack = context
                        .read<PlayerProvider>()
                        .currentTrack;
                    if (curTrack != null &&
                        p.tracks.any((t) => t.id == curTrack.id)) {
                      // Same playlist -> toggle, which also covers pausing via
                      // the row's own button.
                      await context.read<PlayerProvider>().togglePlayPause();
                      return;
                    }
                    await context.read<PlayerProvider>().play(
                      p.tracks.first,
                      queue: p.tracks,
                    );
                  },
            // Long press for the destructive option. A confirm dialog is
            // required because the consequence differs by ownership: your own
            // playlist disappears for everyone who had it.
            onLongPress: () => _confirmDeletePlaylist(context, p),
          );
        },
      ),
    );
  }

  /// Confirms and performs a library delete, spelling out the difference
  /// between removing your own playlist (which also removes it from other
  /// people's libraries) and dropping someone else's from your own.
  Future<void> _confirmDeletePlaylist(
    BuildContext context,
    PlaylistModel p,
  ) async {
    final auth = context.read<AuthProvider>();
    final prov = context.read<PlaylistProvider>();
    final uid = auth.user?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to manage playlists')),
      );
      return;
    }
    final isOwner = p.creatorUid == uid || p.creatorUid.isEmpty;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotterfyTheme.surface,
        title: Text(
          isOwner ? 'Delete playlist?' : 'Remove from your library?',
          style: TextStyle(
            color: SpotterfyTheme.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          isOwner
              ? '"${p.name}" will be deleted for you and for everyone it was shared with. This cannot be undone.'
              : '"${p.name}" will be removed from your library. The owner keeps it.',
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
            child: Text(
              isOwner ? 'Delete' : 'Remove',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final message = await prov.deletePlaylistFromLibrary(uid, p);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _storageTab() {
    // First visit only: waiting on the permission probe.
    if (_permPending) {
      return Center(
        child: CircularProgressIndicator(color: SpotterfyTheme.primary),
      );
    }
    if (_storagePermGranted != true) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_off, size: 48, color: SpotterfyTheme.muted),
              const SizedBox(height: 12),
              Text(
                'Storage permission needed',
                style: TextStyle(
                  color: SpotterfyTheme.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Allow access to display downloaded songs stored on device.',
                textAlign: TextAlign.center,
                style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  await [
                    Permission.audio,
                    Permission.storage,
                    Permission.manageExternalStorage,
                  ].request();
                  _checkStoragePerm();
                },
                child: const Text('Grant'),
              ),
              TextButton(
                onPressed: openAppSettings,
                child: Text(
                  'Open settings',
                  style: TextStyle(color: SpotterfyTheme.primary),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Nothing scanned yet. Later rescans deliberately fall through to the
    // cached list instead of this spinner.
    if (!_storageLoaded) {
      return Center(
        child: CircularProgressIndicator(color: SpotterfyTheme.primary),
      );
    }
    final content = _storageContent();
    if (!_storageScanning) return content;
    // Rescanning: the list stays exactly where it is, only the progress bar
    // animates, so new/removed folders appear without the tab flashing.
    return Stack(
      children: [
        content,
        const Positioned(top: 0, left: 0, right: 0, child: _StorageScanBar()),
      ],
    );
  }

  Widget _storageContent() {
    {
      // One dependency for the whole tab rather than one per row. Also picks up
      // any length the player has since learned for a local file, so rows show
      // real times without re-reading tags.
      final player = context.watch<PlayerProvider>();
      final cur = player.currentTrack;
      final durMs = player.duration.inMilliseconds;
      if (cur != null && durMs > 0 && cur.sourceUrl.startsWith('/storage/')) {
        _rememberStorageDuration(cur.sourceUrl, durMs);
      }
      final files = _storageFiles ?? const <File>[];
      if (files.isEmpty) {
        if (_query.isNotEmpty) {
          return NoResultsView(
            query: _query,
            icon: Icons.folder_off,
            message: 'No folders on this device match "$_query".',
            actionLabel: 'Clear search',
            onAction: () => _searchController.clear(),
          );
        }
        return RefreshIndicator(
          onRefresh: _startStorageScan,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 80),
              Center(
                child: Text(
                  'No local music found\nTip: check subfolders inside /Music',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SpotterfyTheme.muted),
                ),
              ),
            ],
          ),
        );
      }
      // Group direct files by parent folder
      final Map<String, List<File>> groups = {};
      for (final f in files) {
        final parent = File(f.path).parent.path;
        groups.putIfAbsent(parent, () => []).add(f);
      }
      // Full folder tree: every ancestor dir down to the scan roots, so
      // intermediate folders without direct songs still show up and the
      // app mirrors the on-device hierarchy (Music > Artist > Album...).
      String parentOf(String p) => File(p).parent.path;
      const storageBase = '/storage/emulated/0';
      final scanRoots = <String>{kStorageRoot, ...kExtraScanRoots};
      final Set<String> allDirs = {};
      for (final f in files) {
        var dir = File(f.path).parent.path;
        // Walk up to (but never including) a scan root, so /Music itself
        // is never listed - the explorer already starts inside it.
        while (dir.startsWith('$storageBase/') && !scanRoots.contains(dir)) {
          allDirs.add(dir);
          final parent = parentOf(dir);
          if (parent == dir) break;
          dir = parent;
        }
      }
      List<String> childDirs(String p) {
        final list = allDirs.where((d) => d != p && parentOf(d) == p).toList();
        list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        return list;
      }

      List<File> songsIn(String dir) =>
          files.where((f) => f.path.startsWith('$dir/')).toList()..sort(
            (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
          );

      // Root listing shows EVERY folder that contains songs, at any depth,
      // so playlists nested in subfolders are no longer hidden. Shallowest
      // first so the on-device hierarchy still reads naturally.
      final playlistDirs = allDirs.toList()
        ..sort((a, b) {
          final da = a.split('/').length, db = b.split('/').length;
          if (da != db) return da.compareTo(db);
          return a.toLowerCase().compareTo(b.toLowerCase());
        });

      // Loose tracks sitting directly in a scan root (e.g. /Music/foo.mp3)
      // have no folder of their own. Surface them as one entry per root so
      // those songs aren't invisible now that we start inside /Music.
      final looseByRoot = <String, List<File>>{};
      for (final f in files) {
        final parent = File(f.path).parent.path;
        if (scanRoots.contains(parent)) {
          looseByRoot.putIfAbsent(parent, () => []).add(f);
        }
      }
      for (final e in looseByRoot.entries) {
        e.value.sort(
          (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
        );
      }

      // Unified root entries: real folders (drillable) + loose-track roots.
      final entries = <_StorageEntry>[
        for (final d in playlistDirs)
          _StorageEntry(
            name: d.split('/').last,
            songs: songsIn(d),
            folderPath: d,
          ),
        for (final e in looseByRoot.entries)
          _StorageEntry(
            name: e.key.split('/').last,
            songs: e.value,
            folderPath: null,
          ),
      ];
      entries.sort((a, b) {
        // Loose-root entries always last.
        final an = a.folderPath == null, bn = b.folderPath == null;
        if (an != bn) return an ? 1 : -1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      // Filter by query (folder name or any file beneath it)
      var filteredEntries = entries;
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        filteredEntries = entries.where((e) {
          if (e.name.toLowerCase().contains(q)) return true;
          return e.songs.any((f) => f.path.toLowerCase().contains(q));
        }).toList();
      }
      // Storage tab's own ordering, independent of the Imported tab's.
      if (_storageSort == _LibrarySort.name) {
        filteredEntries = List.of(
          filteredEntries,
        )..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else if (_storageSort == _LibrarySort.songs ||
          _storageSort == _LibrarySort.mostSongs) {
        final asc = _storageSort == _LibrarySort.songs;
        filteredEntries = List.of(filteredEntries)
          ..sort(
            (a, b) => asc
                ? a.songs.length.compareTo(b.songs.length)
                : b.songs.length.compareTo(a.songs.length),
          );
      }
      // Inline folder detail with subfolder drill-down (keeps MiniPlayer visible, not a new route)
      if (_folderStack.isNotEmpty) {
        final folderPath = _folderStack.last;
        final rawSubs = childDirs(folderPath);
        if (allDirs.contains(folderPath)) {
          final folderFilesAll = groups[folderPath] ?? const <File>[];
          final folderName = folderPath.split('/').last.isEmpty
              ? 'Music'
              : folderPath.split('/').last;
          var detailFiles = folderFilesAll;
          var subfolders = rawSubs;
          if (_query.isNotEmpty) {
            final q = _query.toLowerCase();
            detailFiles = folderFilesAll
                .where((f) => f.path.toLowerCase().contains(q))
                .toList();
            subfolders = rawSubs.where((s) {
              if (s.split('/').last.toLowerCase().contains(q)) return true;
              return files.any(
                (f) =>
                    (f.path == s || f.path.startsWith('$s/')) &&
                    f.path.toLowerCase().contains(q),
              );
            }).toList();
          }
          final folderTracks = _tracksForFiles(detailFiles, folderName);
          // Keep sorted files aligned with sorted tracks for cover lookup
          detailFiles = List<File>.from(detailFiles)
            ..sort(
              (a, b) => a.path
                  .split('/')
                  .last
                  .toLowerCase()
                  .compareTo(b.path.split('/').last.toLowerCase()),
            );
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () =>
                          setState(() => _folderStack.removeLast()),
                    ),
                    Expanded(
                      child: Text(
                        folderName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${detailFiles.length} songs',
                      style: TextStyle(
                        color: SpotterfyTheme.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              if (detailFiles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await context.read<PlayerProvider>().play(
                          folderTracks.first,
                          queue: folderTracks,
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Playing $folderName')),
                        );
                      },
                      icon: const Icon(Icons.play_arrow, color: Colors.white),
                      label: Text(
                        'Play • ${detailFiles.length} tracks',
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
                child: (detailFiles.isEmpty && subfolders.isEmpty)
                    ? NoResultsView(
                        query: _query,
                        icon: Icons.folder_off,
                        message: _query.isNotEmpty
                            ? 'Nothing in "$folderName" matches "$_query".'
                            : 'This folder has no playable songs.',
                        actionLabel: _query.isNotEmpty ? 'Clear search' : null,
                        onAction: _query.isNotEmpty
                            ? () => _searchController.clear()
                            : null,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 100),
                        itemCount: subfolders.length + detailFiles.length,
                        itemBuilder: (_, i) {
                          if (i < subfolders.length) {
                            final subPath = subfolders[i];
                            final subName = subPath.split('/').last;
                            final subSongs = songsIn(subPath);
                            final subCount = subSongs.length;
                            final cur = context
                                .watch<PlayerProvider>()
                                .currentTrack;
                            final isActive =
                                cur != null &&
                                cur.id.startsWith('storage_') &&
                                cur.sourceUrl.startsWith('$subPath/');
                            // Subfolders are playlists too: cover = first song's art.
                            final subCover = subSongs.isNotEmpty
                                ? subSongs.first.path
                                : null;
                            return ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: subCover != null
                                    ? StorageCover(
                                        path: subCover,
                                        size: 48,
                                        iconSize: 24,
                                        radius: 8,
                                      )
                                    : Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: SpotterfyTheme.surface,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.folder,
                                          color: isActive
                                              ? SpotterfyTheme.primary
                                              : SpotterfyTheme.muted,
                                        ),
                                      ),
                              ),
                              title: Text(
                                subName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '$subCount ${subCount == 1 ? 'song' : 'songs'}',
                                style: TextStyle(
                                  color: SpotterfyTheme.muted,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: Colors.white,
                                size: 20,
                              ),
                              onTap: () =>
                                  setState(() => _folderStack.add(subPath)),
                            );
                          }
                          final j = i - subfolders.length;
                          final f = detailFiles[j];
                          final t = folderTracks[j];
                          final isSelected = player.currentTrack?.id == t.id;
                          final isPlaying = isSelected && player.isPlaying;
                          return TrackTile(
                            track: t,
                            coverPath: f.path,
                            isSelected: isSelected,
                            isPlaying: isPlaying,
                            onPlay: () async {
                              await context.read<PlayerProvider>().play(
                                t,
                                queue: folderTracks,
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        }
      }

      if (filteredEntries.isEmpty) {
        return NoResultsView(
          query: _query,
          icon: Icons.folder_off,
          message: 'No storage folders match "$_query".',
          actionLabel: 'Clear search',
          onAction: () => _searchController.clear(),
        );
      }
      return RefreshIndicator(
        onRefresh: _startStorageScan,
        color: SpotterfyTheme.primary,
        backgroundColor: SpotterfyTheme.surface,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          // Bottom inset so the last playlist clears the mini player
          // instead of hiding behind it.
          padding: const EdgeInsets.fromLTRB(16, 8, 16, _bottomInset),
          itemCount: filteredEntries.length,
          itemBuilder: (_, idx) {
            final entry = filteredEntries[idx];
            final folderName = entry.name;
            // A folder is a playlist: every song underneath it, recursively.
            final allSongs = entry.songs;
            final count = allSongs.length;
            final folderTracks = _tracksForFiles(allSongs, folderName);
            // The player is watched once for the whole list, not per row: a
            // per-row `context.watch` rebuilt every visible item on every
            // position tick.
            final curTrack = player.currentTrack;
            final prefix = entry.folderPath == null
                ? '$folderName/'
                : '${entry.folderPath}/';
            final isActiveFolder =
                curTrack != null &&
                curTrack.id.startsWith('storage_') &&
                curTrack.sourceUrl.startsWith(prefix);
            final isPlayingFolder = isActiveFolder && player.isPlaying;
            // Cover = embedded art of the first song in the playlist.
            final coverPath = allSongs.isNotEmpty ? allSongs.first.path : null;
            final subPath = entry.folderPath ?? folderName;
            return GestureDetector(
              onTap: entry.folderPath == null
                  ? null
                  : () => setState(() {
                      _folderStack
                        ..clear()
                        ..add(subPath);
                    }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  // Same raised gradient as the Imported cards so both tabs
                  // share one look.
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isActiveFolder
                        ? [
                            SpotterfyTheme.primary.withValues(alpha: 0.16),
                            SpotterfyTheme.card,
                          ]
                        : [SpotterfyTheme.card, SpotterfyTheme.surface],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isActiveFolder
                        ? SpotterfyTheme.primary.withValues(alpha: 0.55)
                        : Colors.white.withValues(alpha: 0.06),
                    width: isActiveFolder ? 1.2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActiveFolder
                              ? SpotterfyTheme.primary.withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: coverPath != null
                            ? StorageCover(
                                path: coverPath,
                                size: 58,
                                iconSize: 28,
                                radius: 11,
                              )
                            : Container(
                                color: SpotterfyTheme.surface,
                                child: Icon(
                                  Icons.folder_rounded,
                                  color: isActiveFolder
                                      ? SpotterfyTheme.primary
                                      : SpotterfyTheme.muted,
                                  size: 28,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (isActiveFolder) ...[
                                Icon(
                                  Icons.graphic_eq_rounded,
                                  color: SpotterfyTheme.primary,
                                  size: 15,
                                ),
                                const SizedBox(width: 5),
                              ],
                              Expanded(
                                child: Text(
                                  folderName,
                                  style: TextStyle(
                                    color: isActiveFolder
                                        ? SpotterfyTheme.primary
                                        : SpotterfyTheme.text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Text(
                                '$count ${count == 1 ? 'song' : 'songs'}',
                                style: TextStyle(
                                  color: SpotterfyTheme.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (entry.folderPath != null) ...[
                                Text(
                                  ' • ',
                                  style: TextStyle(
                                    color: SpotterfyTheme.mutedDark,
                                    fontSize: 12,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    entry.folderPath!.replaceFirst(
                                      '/storage/emulated/0/',
                                      '',
                                    ),
                                    style: TextStyle(
                                      color: SpotterfyTheme.muted,
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ] else
                                Expanded(
                                  child: Text(
                                    'loose tracks',
                                    style: TextStyle(
                                      color: SpotterfyTheme.muted,
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (folderTracks.isNotEmpty) ...[
                      PlaylistPlayButton(
                        isActive: isActiveFolder,
                        isPlaying: isPlayingFolder,
                        tooltip: isPlayingFolder ? 'Pause' : 'Play',
                        onPressed: () async {
                          if (isPlayingFolder) {
                            await context
                                .read<PlayerProvider>()
                                .togglePlayPause();
                            return;
                          }
                          await context.read<PlayerProvider>().play(
                            folderTracks.first,
                            queue: folderTracks,
                          );
                        },
                      ),
                    ],
                    if (entry.folderPath != null) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: SpotterfyTheme.mutedDark,
                        size: 22,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
  }

  /// Records a real length for a local file so later builds show it.
  void _rememberStorageDuration(String path, int ms) {
    if (ms <= 0 || _storageDurations[path] == ms) return;
    _storageDurations[path] = ms;
  }

  List<TrackModel> _tracksForFiles(List<File> files, String folderName) {
    // Keyed on the generation plus the set's shape: within one scan a folder
    // always yields the same list, so this is safe to reuse across rebuilds.
    final key =
        '$_memoGeneration|$folderName|${files.length}|'
        '${files.isEmpty ? '' : files.first.path}|'
        '${files.isEmpty ? '' : files.last.path}';
    final hit = _tracksMemo[key];
    if (hit != null) return hit;

    final out =
        files.map((f) {
          final path = f.path;
          final name = path
              .split('/')
              .last
              .replaceAll(
                RegExp(
                  r'\.(mp3|m4a|opus|flac|wav|ogg|aac)$',
                  caseSensitive: false,
                ),
                '',
              );
          return TrackModel(
            id: 'storage_${path.hashCode}',
            title: name.isEmpty ? 'Unknown' : name,
            artists: folderName,
            album: 'Local',
            cover: '',
            sourceUrl: path,
            // Real length, once the file has been loaded and reported one.
            durationMs: _storageDurations[path] ?? 0,
          );
        }).toList()..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );

    // Keep the cache bounded; a stale entry is cheap, a leak is not.
    if (_tracksMemo.length > 300) _tracksMemo.clear();
    _tracksMemo[key] = out;
    return out;
  }

  Future<bool> _hasStoragePerm() async {
    // Android 13+ needs audio, 11+ may need manageExternalStorage for full scan
    try {
      if (await Permission.audio.isGranted) return true;
      if (await Permission.storage.isGranted) return true;
      if (await Permission.manageExternalStorage.isGranted) return true;
    } catch (_) {}
    return false;
  }

  /// Root the storage explorer browses from. We start *inside* /Music so the
  /// Music folder itself is never listed as a playlist.
  static const String kStorageRoot = '/storage/emulated/0/Music';

  /// Extra roots scanned (but not shown as folders themselves) so music in
  /// Download/Documents still shows up as a top-level playlist entry.
  static const List<String> kExtraScanRoots = [
    '/storage/emulated/0/Download',
    '/storage/emulated/0/Documents',
  ];

  Future<List<FileSystemEntity>> _listMusicFiles() async {
    final exts = ['.mp3', '.m4a', '.opus', '.flac', '.wav', '.ogg', '.aac'];
    bool isAudio(String p) => exts.any((e) => p.toLowerCase().endsWith(e));

    // Primary root first; fall back to the wider set only if Music is absent
    // (so the explorer is never completely empty on odd devices).
    var candidates = <String>[kStorageRoot];
    final musicDir = Directory(kStorageRoot);
    if (!await musicDir.exists()) {
      candidates = <String>[...kExtraScanRoots];
    } else {
      candidates = <String>[kStorageRoot, ...kExtraScanRoots];
    }

    final all = <FileSystemEntity>[];
    for (final p in candidates) {
      final d = Directory(p);
      if (!await d.exists()) continue;
      try {
        // Recursive so nested playlist folders are discovered too. No hard cap
        // here: truncating the walk was what made deep subfolders disappear.
        await for (final e in d.list(recursive: true, followLinks: false)) {
          if (e is File && isAudio(e.path)) all.add(e);
        }
      } catch (_) {}
    }

    all.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    return all;
  }

  void _showImportSheet(BuildContext context) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      // Above the mini player, for the same reason as the sort sheet: the mini
      // player is drawn by MainScreen, outside this tab's navigator, so a sheet
      // opened on the tab navigator lands underneath it and the confirm button
      // is covered.
      useRootNavigator: true,
      backgroundColor: const Color(0xFF0f1d17),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3f3f46),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Import playlist',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Paste Spotify / YouTube / SoundCloud URL',
                  hintStyle: TextStyle(
                    color: const Color(0xFFa1a1aa),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF0a1410),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: const Color(0xFF1a3a2a)),
                  ),
                  prefixIcon: Icon(
                    Icons.link,
                    color: SpotterfyTheme.primary,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final url = controller.text.trim();
                    if (url.isEmpty) return;
                    Navigator.pop(ctx);
                    final auth = context.read<AuthProvider>();
                    final prov = context.read<PlaylistProvider>();
                    final existing = prov.getPlaylistByUrl(url);
                    if (existing != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Already in library: ${existing.name}'),
                        ),
                      );
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Importing...')),
                    );
                    final playlist = await prov.importFromUrl(url);
                    if (playlist != null && auth.user != null) {
                      await prov.savePlaylist(auth.user!.uid, playlist);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Imported "${playlist.name}"')),
                      );
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(prov.error ?? 'Import failed')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SpotterfyTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Import',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Orderings offered by the library's sort buttons.
enum _LibrarySort {
  recent('Recently added'),
  oldest('Oldest first'),
  name('Name (A-Z)'),
  artist('Artist'),
  songs('Fewest songs'),
  mostSongs('Most songs'),
  length('Length');

  const _LibrarySort(this.label);
  final String label;
}

/// Thin strip under the tabs carrying the sort control for whichever list is
/// showing.
///
/// Replaces the bare icon that used to sit inside the tab label. Two problems it
/// fixed: the icon was wedged against the tab text with no room, and it showed
/// nothing about the *current* order, so "is this list sorted by name or by date?"
/// was unanswerable without opening the sheet and reading it.
class _SortStrip extends StatelessWidget {
  final bool onImported;
  final _LibrarySort importedSort;
  final List<_LibrarySort> importedOptions;
  final _LibrarySort storageSort;
  final List<_LibrarySort> storageOptions;
  final ValueChanged<_LibrarySort> onPicked;

  const _SortStrip({
    required this.onImported,
    required this.importedSort,
    required this.importedOptions,
    required this.storageSort,
    required this.storageOptions,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    final current = onImported ? importedSort : storageSort;
    final options = onImported ? importedOptions : storageOptions;
    // "Recently added" / "Name" are the orders each tab opens on, so those are
    // not worth calling out as a change.
    final isDefault = onImported
        ? current == _LibrarySort.recent
        : current == _LibrarySort.name;

    return Container(
      height: 40,
      padding: const EdgeInsets.only(right: 12, left: 16),
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!isDefault) ...[
            Text(
              current.label,
              style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12),
            ),
            const SizedBox(width: 8),
          ],
          _SortPill(
            current: current,
            options: options,
            onPicked: onPicked,
            highlighted: !isDefault,
          ),
        ],
      ),
    );
  }
}

/// Pill showing the active ordering. Tinted only when the order is not the
/// tab's default, so it reads as a live control rather than a permanent badge.
class _SortPill extends StatelessWidget {
  final _LibrarySort current;
  final List<_LibrarySort> options;
  final ValueChanged<_LibrarySort> onPicked;
  final bool highlighted;

  const _SortPill({
    required this.current,
    required this.options,
    required this.onPicked,
    required this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    final accent = highlighted
        ? SpotterfyTheme.primary
        : const Color(0xFFa1a1aa);
    return Tooltip(
      message: 'Sort',
      child: Material(
        color: highlighted
            ? SpotterfyTheme.primary.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showSheet(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_vert_rounded, size: 17, color: accent),
                const SizedBox(width: 6),
                Text(
                  'Sort',
                  style: TextStyle(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.expand_more_rounded, size: 16, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSheet(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      // useRootNavigator pushes the sheet above the *root* navigator, which is
      // what puts it over the mini player: the mini player is a sibling of the
      // tab navigators inside MainScreen's Stack, so a sheet opened on a tab's
      // own navigator renders underneath it and its lowest options are simply
      // not tappable.
      useRootNavigator: true,
      backgroundColor: SpotterfyTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Sort by',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              for (final s in options)
                ListTile(
                  dense: true,
                  // `s` is the loop variable, so this correctly reports which
                  // option was tapped.
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    onPicked(s);
                  },
                  title: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: s == current
                            ? const Icon(
                                Icons.check,
                                size: 18,
                                color: Color(0xFF10b981),
                              )
                            : null,
                      ),
                      Text(
                        s.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
