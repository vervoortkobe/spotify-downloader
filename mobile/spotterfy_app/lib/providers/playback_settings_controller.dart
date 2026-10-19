import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the playback preferences that are not tied to an account: the
/// song-transition (crossfade) duration and whether the queue is restored on
/// the next launch.
///
/// Persisted in SharedPreferences so the choices survive restarts. The
/// transition value is read by PlayerProvider at the moment a crossfade is
/// scheduled, so a change takes effect on the next track transition.
class PlaybackSettingsController extends ChangeNotifier {
  PlaybackSettingsController._();

  static final PlaybackSettingsController instance =
      PlaybackSettingsController._();

  static const _crossfadeKey = 'crossfade_seconds';
  static const _rememberQueueKey = 'remember_queue';

  /// Crossfade length used when nothing has been stored yet.
  static const int defaultSeconds = 3;

  /// Longest crossfade the slider offers.
  static const int maxSeconds = 5;

  /// Restore the queue on launch unless the user turned it off. Defaulting on
  /// preserves the behaviour the app had before the switch existed.
  static const bool defaultRememberQueue = true;

  int _crossfadeSeconds = defaultSeconds;
  bool _rememberQueue = defaultRememberQueue;

  /// Crossfade length in seconds; 0 disables crossfading.
  int get crossfadeSeconds => _crossfadeSeconds;

  /// Whether the queue (and its position) is restored when the app reopens.
  bool get rememberQueue => _rememberQueue;

  bool _loaded = false;

  /// Whether the stored values have been read back yet.
  bool get isLoaded => _loaded;

  Future<void>? _loading;

  /// Reads the stored settings.
  ///
  /// Safe to call more than once: the first call owns the read and later ones
  /// await the same future. PlayerProvider awaits this before restoring the
  /// queue, so a restart with "remember queue" off can never race the switch
  /// being loaded and restore it anyway.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _crossfadeSeconds = prefs.getInt(_crossfadeKey) ?? defaultSeconds;
      _rememberQueue = prefs.getBool(_rememberQueueKey) ?? defaultRememberQueue;
    } catch (_) {
      // Preferences unavailable: keep the defaults rather than failing startup.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setCrossfadeSeconds(int seconds) async {
    final clamped = seconds.clamp(0, maxSeconds);
    if (_crossfadeSeconds == clamped) return;
    _crossfadeSeconds = clamped;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_crossfadeKey, clamped);
    } catch (_) {
      // Not being able to remember the choice must not break switching it.
    }
  }

  Future<void> setRememberQueue(bool remember) async {
    if (_rememberQueue == remember) return;
    _rememberQueue = remember;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_rememberQueueKey, remember);
    } catch (_) {
      // Same as above: the switch still applies for this session.
    }
  }
}
