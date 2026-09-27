import 'package:flutter/foundation.dart';
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
class DownloadProvider extends ChangeNotifier {
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

  bool isDownloaded(String trackId) => _entries.containsKey(trackId);

  /// Absolute path of the downloaded file, or null.
  String? localPathFor(String trackId) {
    final cached = _entries[trackId];
    if (cached == null) return null;
    return _service.localPathFor(trackId);
  }

  /// Downloads [track] unless it is already on disk. Returns true on success.
  ///
  /// Safe to call while another track is downloading: the call returns false
  /// rather than interleaving two server round-trips.
  Future<bool> download(TrackModel track) async {
    if (isDownloaded(track.id)) return true;
    if (isBusy) return false;

    _states[track.id] = DownloadState.downloading;
    _activeTrackId = track.id;
    _lastError = null;
    notifyListeners();

    try {
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
