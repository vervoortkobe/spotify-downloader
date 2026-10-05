import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the song-transition (crossfade) duration and repaints listeners when
/// it changes.
///
/// Persisted in SharedPreferences so the choice survives restarts. The value
/// is read by PlayerProvider at the moment a crossfade is scheduled, so a
/// change takes effect on the next track transition.
class PlaybackSettingsController extends ChangeNotifier {
  PlaybackSettingsController._();

  static final PlaybackSettingsController instance =
      PlaybackSettingsController._();

  static const _key = 'crossfade_seconds';

  /// Crossfade length used when nothing has been stored yet.
  static const int defaultSeconds = 3;

  /// Longest crossfade the slider offers.
  static const int maxSeconds = 5;

  int _crossfadeSeconds = defaultSeconds;

  /// Crossfade length in seconds; 0 disables crossfading.
  int get crossfadeSeconds => _crossfadeSeconds;

  bool _loaded = false;

  /// Whether the stored value has been read back yet.
  bool get isLoaded => _loaded;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _crossfadeSeconds = prefs.getInt(_key) ?? defaultSeconds;
    } catch (_) {
      // Preferences unavailable: keep the default rather than failing startup.
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
      await prefs.setInt(_key, clamped);
    } catch (_) {
      // Not being able to remember the choice must not break switching it.
    }
  }
}
