import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/services/download_service.dart';
import 'package:spotterfy_app/services/notification_service.dart';

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

  /// Set while [downloadMany] is running so the progress notification can show
  /// "song 3 of 12" instead of jumping between per-track titles. Null means a
  /// one-off download, which owns its own notification lifecycle.
  String? _batchLabel;
  int _batchTotal = 0;
  int _batchDone = 0;

  /// Last percentage painted on the notification, or -1 when nothing has been
  /// shown yet. Guards against rebuilding the notification on every chunk.
  int _lastNotifiedPct = -1;

  /// Title of the track currently transferring, for the notification subtitle.
  TrackModel? get _currentActiveTrack {
    final id = _activeTrackId;
    if (id == null) return null;
    return _activeTrackTitles[id];
  }

  /// Titles by id, populated by the screens that kick off a transfer so the
  /// notification can name the song without the provider re-resolving it.
  final Map<String, TrackModel> _activeTrackTitles = {};

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
    _activeTrackTitles[track.id] = track;
    _lastError = null;
    notifyListeners();
    _lastNotifiedPct = -1;

    try {
      if (!await canWritePublicStorage()) {
        // Ask in place: the user is mid-download, so the prompt makes sense
        // here rather than on first launch.
        final granted = await requestPublicStorageAccess();
        if (!granted) {
          _states[track.id] = DownloadState.failed;
          _lastError = 'File access is needed to download songs';
          _finishNotification(track, ok: false);
          return false;
        }
      }
      final bytes = await ApiService.downloadTrack(track, onProgress: _onBytes);
      if (bytes == null || bytes.isEmpty) {
        _states[track.id] = DownloadState.failed;
        _lastError = 'Could not download "${track.title}"';
        _finishNotification(track, ok: false);
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
        _finishNotification(track, ok: false);
        return false;
      }
      _entries[track.id] = _service.entries[track.id]!;
      _states[track.id] = DownloadState.done;
      // In a batch the summary notification belongs to downloadMany, which
      // knows how many tracks are left; finishing per track here would replace
      // the bar with "done" after the first song.
      if (_batchTotal == 0) _finishNotification(track, ok: true);
      return true;
    } catch (e) {
      debugPrint('[Downloads] ${track.id} failed: $e');
      _states[track.id] = DownloadState.failed;
      _lastError = 'Download failed for "${track.title}"';
      _finishNotification(track, ok: false);
      return false;
    } finally {
      _activeTrackId = null;
      _activeTrackTitles.remove(track.id);
      notifyListeners();
    }
  }

  /// Byte-level progress callback handed to [ApiService.downloadTrack].
  void _onBytes(int received, int total) {
    final track = _activeTrackId == null ? null : _currentActiveTrack;
    final label = track?.title ?? 'Download';
    final inBatch = _batchTotal > 0;
    // Repainting the notification on every callback is wasteful; only move the
    // bar when the visible percentage actually changes.
    final pct = total > 0 ? ((received / total) * 100).floor() : -1;
    if (pct == _lastNotifiedPct) return;
    _lastNotifiedPct = pct;

    final songNo = inBatch ? _batchDone + 1 : null;
    unawaited(
      NotificationService().showDownloadProgress(
        title: _batchLabel ?? label,
        subtitle: total > 0
            ? (inBatch ? 'Song $songNo of $_batchTotal · $pct%' : '$pct%')
            : (inBatch ? 'Song $songNo of $_batchTotal' : 'Downloading...'),
        // total <= 0 means no Content-Length, so the bar can only spin.
        progress: total > 0 ? received / total : null,
        maxProgress: total > 0 ? total : null,
        progressValue: total > 0 ? received : null,
      ),
    );
  }

  /// Marks a one-off (non-batch) transfer finished, successfully or not.
  void _finishNotification(TrackModel track, {required bool ok}) {
    if (_batchTotal > 0) return;
    unawaited(
      NotificationService().showDownloadProgress(
        title: track.title,
        subtitle: ok ? 'Saved to your device' : 'Download failed',
        isComplete: ok,
        isError: !ok,
      ),
    );
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
    _batchLabel = tracks.length == 1 ? tracks.first.title : 'Playlist';
    _batchTotal = tracks.length;
    _batchDone = 0;
    unawaited(
      NotificationService().showDownloadProgress(
        title: _batchLabel!,
        subtitle: 'Starting...',
        progress: 0,
      ),
    );
    try {
      for (final t in tracks) {
        if (isDownloaded(t.id)) {
          ok++;
          _batchDone++;
          continue;
        }
        if (await download(t)) ok++;
        _batchDone++;
      }
    } finally {
      final total = _batchTotal;
      final label = _batchLabel;
      _batchLabel = null;
      _batchTotal = 0;
      _batchDone = 0;
      _lastNotifiedPct = -1;
      if (label != null) {
        unawaited(
          NotificationService().showDownloadProgress(
            title: label,
            subtitle: ok == total
                ? (total == 1 ? 'Downloaded' : 'Downloaded $total songs')
                : 'Downloaded $ok of $total',
            isComplete: ok == total,
            isError: ok != total,
          ),
        );
      }
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
