import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/services/download_service.dart';

/// State machine for one track's download.
enum DownloadState { idle, downloading, done, failed }

/// Bridges the UI to [DownloadService] and the backend download endpoint.
///
/// Downloads run one at a time on purpose: the endpoint is CPU-heavy on the
/// server (a yt-dlp resolve plus a fetch per track), and firing a whole
/// playlist at it concurrently would slow every track down and make failures
/// much harder to attribute.
class DownloadProvider extends ChangeNotifier with WidgetsBindingObserver {
  final _service = DownloadService.instance;

  /// trackId -> state, for the rows currently doing something.
  final Map<String, DownloadState> _states = {};
  String? _activeTrackId;

  /// Loaded index of what's already on disk.
  final Map<String, DownloadEntry> _entries = {};

  String? _lastError;

  Map<String, DownloadState> get states => Map.unmodifiable(_states);
  Map<String, DownloadEntry> get entries => Map.unmodifiable(_entries);
  String? get lastError => _lastError;
  String? get activeTrackId => _activeTrackId;
  bool get isBusy => _activeTrackId != null;

  int get totalBytes => _service.totalBytes;
  int get count => _entries.length;

  /// Reads the on-disk index. Safe to await more than once.
  Future<void> load() async {
    await _service.ensureLoaded();
    _entries
      ..clear()
      ..addAll(_service.entries);
    notifyListeners();
  }

  /// Drops downloads whose files have disappeared since the index was read -
  /// deleted in a file manager, or cleared to free space.
  ///
  /// Called when the app returns to the foreground, which is exactly when a
  /// user is likely to have been in a file manager.
  Future<void> verify() async {
    final gone = await _service.pruneMissingFiles();
    if (gone.isEmpty) return;
    for (final id in gone) {
      _entries.remove(id);
    }
    _entries.addAll(_service.entries);
    notifyListeners();
  }

  DownloadProvider() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      verify();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool isDownloaded(String trackId) => _entries.containsKey(trackId);

  /// Absolute path of the downloaded file, or null.
  String? localPathFor(String trackId) {
    final cached = _entries[trackId];
    if (cached == null) return null;
    return _service.localPathFor(trackId);
  }

  /// Whether the app may write to public storage.
  ///
  /// Downloads live in `/storage/emulated/0/Spotterfy/Music` so other music apps
  /// can see them, which needs all-files access on Android 11+. Older releases
  /// only need the legacy write permission, which is granted at install time, so
  /// this only gates the modern case.
  static Future<bool> canWritePublicStorage() async {
    try {
      return await perm.Permission.manageExternalStorage.isGranted;
    } catch (_) {
      // If the platform can't answer, let the write attempt decide rather than
      // blocking the user up front.
      return true;
    }
  }

  /// Asks for the permission, then re-checks. Called when a download is first
  /// attempted without it, so the prompt appears where the user is trying to do
  /// something rather than on first launch.
  static Future<bool> requestPublicStorageAccess() async {
    try {
      final status = await perm.Permission.manageExternalStorage.request();
      return status.isGranted || status.isLimited;
    } catch (_) {
      return false;
    }
  }

  /// Downloads [track] unless it is already on disk. Returns true on success.
  ///
  /// Safe to call while another track is downloading: the call returns false
  /// rather than interleaving two server round-trips.
  Future<bool> download(TrackModel track) async {
    if (isDownloaded(track.id)) {
      // The index can go stale if the file was deleted outside the app. Only
      // short-circuit when the file is genuinely still there, otherwise fall
      // through and fetch it again.
      if (await _service.isDownloadedAndPresent(track.id)) return true;
      _entries.remove(track.id);
    }
    if (isBusy) return false;

    _states[track.id] = DownloadState.downloading;
    _activeTrackId = track.id;
    _lastError = null;
    notifyListeners();

    try {
      if (!await canWritePublicStorage()) {
        // Ask in place: the user is mid-download, so the prompt makes sense
        // here rather than on first launch.
        final granted = await requestPublicStorageAccess();
        if (!granted) {
          _states[track.id] = DownloadState.failed;
          _lastError = 'File access is needed to download songs';
          return false;
        }
      }
      final bytes = await ApiService.downloadTrack(track);
      if (bytes == null || bytes.isEmpty) {
        _states[track.id] = DownloadState.failed;
        _lastError = 'Could not download "${track.title}"';
        return false;
      }
      final path = await _service.save(
        trackId: track.id,
        bytes: bytes,
        title: track.title,
        artists: track.artists,
      );
      if (path == null) {
        _states[track.id] = DownloadState.failed;
        _lastError = 'Could not save "${track.title}"';
        return false;
      }
      _entries[track.id] = _service.entries[track.id]!;
      _states[track.id] = DownloadState.done;
      return true;
    } catch (e) {
      debugPrint('[Downloads] ${track.id} failed: $e');
      _states[track.id] = DownloadState.failed;
      _lastError = 'Download failed for "${track.title}"';
      return false;
    } finally {
      _activeTrackId = null;
      notifyListeners();
    }
  }

  /// Downloads a list in order, skipping anything already on disk.
  ///
  /// Returns the number that succeeded. Failures don't abort the rest - a bad
  /// track shouldn't stop you getting the other 29.
  Future<int> downloadMany(List<TrackModel> tracks) async {
    var ok = 0;
    // Re-check up front: a batch where every file vanished externally should
    // re-download, not be skipped as "already have it".
    await verify();
    for (final t in tracks) {
      if (isDownloaded(t.id)) {
        ok++;
        continue;
      }
      if (await download(t)) ok++;
    }
    return ok;
  }

  /// Removes one downloaded file.
  Future<void> remove(String trackId) async {
    await _service.remove(trackId);
    _entries.remove(trackId);
    _states.remove(trackId);
    notifyListeners();
  }

  /// Removes several downloaded files.
  Future<void> removeMany(Iterable<String> trackIds) async {
    for (final id in trackIds.toList()) {
      await _service.remove(id);
      _entries.remove(id);
      _states.remove(id);
    }
    notifyListeners();
  }
}
