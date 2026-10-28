import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the playback preferences that are not tied to an account: the
/// song-transition (crossfade) duration, whether the queue is restored on the
/// next launch, and whether playback continues after the queue ends.
///
/// Persisted in SharedPreferences so the choices survive restarts. When a user
/// is signed in, settings are also synced to and from Firestore so they roam
/// across devices. The transition value is read by PlayerProvider at the moment
/// a crossfade is scheduled, so a change takes effect on the next track
/// transition.
class PlaybackSettingsController extends ChangeNotifier {
  PlaybackSettingsController._();

  static final PlaybackSettingsController instance =
      PlaybackSettingsController._();

  static const _crossfadeKey = 'crossfade_seconds';
  static const _rememberQueueKey = 'remember_queue';
  static const _resumeLastPositionKey = 'resume_last_position';
  static const _continuePlayingKey = 'continue_playing';
  static const _startOnStartupKey = 'start_on_startup';

  /// Crossfade length used when nothing has been stored yet.
  static const int defaultSeconds = 3;

  /// Longest crossfade the slider offers.
  static const int maxSeconds = 5;

  /// Restore the queue on launch unless the user turned it off. Defaulting on
  /// preserves the behaviour the app had before the switch existed.
  static const bool defaultRememberQueue = true;

  /// Resume the most recently selected song from its saved timestamp by default.
  static const bool defaultResumeLastPosition = true;

  /// Keep playing after the last queued track. Defaulting off preserves the
  /// app's existing stop-at-the-end behaviour until the user opts in.
  static const bool defaultContinuePlaying = false;

  /// Automatically start playing when opening the app. Off by default.
  static const bool defaultStartOnStartup = false;

  int _crossfadeSeconds = defaultSeconds;
  bool _rememberQueue = defaultRememberQueue;
  bool _resumeLastPosition = defaultResumeLastPosition;
  bool _continuePlaying = defaultContinuePlaying;
  bool _startOnStartup = defaultStartOnStartup;

  /// The uid of the signed-in user, used to sync settings to/from Firestore.
  String? _syncUid;

  /// Crossfade length in seconds; 0 disables crossfading.
  int get crossfadeSeconds => _crossfadeSeconds;

  /// Whether the queue (and its position) is restored when the app reopens.
  bool get rememberQueue => _rememberQueue;

  /// Whether to remember the last selected song and its playback timestamp.
  bool get resumeLastPosition => _resumeLastPosition;

  /// Whether reaching the end of the queue should keep music going.
  bool get continuePlaying => _continuePlaying;

  /// Whether to automatically start playing when opening the app.
  bool get startOnStartup => _startOnStartup;

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
      _resumeLastPosition =
          prefs.getBool(_resumeLastPositionKey) ?? defaultResumeLastPosition;
      _continuePlaying =
          prefs.getBool(_continuePlayingKey) ?? defaultContinuePlaying;
      _startOnStartup =
          prefs.getBool(_startOnStartupKey) ?? defaultStartOnStartup;
    } catch (_) {
      // Preferences unavailable: keep the defaults rather than failing startup.
    }
    _loaded = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Firebase sync
  // ---------------------------------------------------------------------------

  /// Binds (or unbinds) the signed-in user's uid for Firestore sync.
  ///
  /// Called by [AuthProvider] when the user signs in or signs out. On sign-in
  /// the current Firestore values are fetched once so settings roam across
  /// devices; on sign-out the link is severed.
  void bindUid(String? uid) {
    _syncUid = uid;
    if (uid != null) {
      unawaited(loadFromFirebase(uid));
    }
  }

  /// Writes all settings to `users/{uid}/settings/playback` in Firestore.
  Future<void> syncToFirebase(String uid) async {
    try {
      await FirebaseFirestore.instance
          .doc('users/$uid/settings/playback')
          .set({
            'crossfadeSeconds': _crossfadeSeconds,
            'continuePlaying': _continuePlaying,
            'rememberQueue': _rememberQueue,
            'resumeLastPosition': _resumeLastPosition,
            'startOnStartup': _startOnStartup,
          });
    } catch (e) {
      debugPrint('[PlaybackSettings] syncToFirebase failed: $e');
    }
  }

  /// Reads `users/{uid}/settings/playback` from Firestore, applies any
  /// non-null values (overwriting SharedPreferences), and notifies listeners.
  Future<void> loadFromFirebase(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .doc('users/$uid/settings/playback')
          .get();
      if (!snap.exists) return;
      final data = snap.data();
      if (data == null) return;

      final prefs = await SharedPreferences.getInstance();

      if (data['crossfadeSeconds'] is int) {
        _crossfadeSeconds =
            (data['crossfadeSeconds'] as int).clamp(0, maxSeconds);
        await prefs.setInt(_crossfadeKey, _crossfadeSeconds);
      }
      if (data['continuePlaying'] is bool) {
        _continuePlaying = data['continuePlaying'] as bool;
        await prefs.setBool(_continuePlayingKey, _continuePlaying);
      }
      if (data['rememberQueue'] is bool) {
        _rememberQueue = data['rememberQueue'] as bool;
        await prefs.setBool(_rememberQueueKey, _rememberQueue);
      }
      if (data['resumeLastPosition'] is bool) {
        _resumeLastPosition = data['resumeLastPosition'] as bool;
        await prefs.setBool(_resumeLastPositionKey, _resumeLastPosition);
      }
      if (data['startOnStartup'] is bool) {
        _startOnStartup = data['startOnStartup'] as bool;
        await prefs.setBool(_startOnStartupKey, _startOnStartup);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[PlaybackSettings] loadFromFirebase failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Setters
  // ---------------------------------------------------------------------------

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
    if (_syncUid != null) unawaited(syncToFirebase(_syncUid!));
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
    if (_syncUid != null) unawaited(syncToFirebase(_syncUid!));
  }

  Future<void> setResumeLastPosition(bool resume) async {
    if (_resumeLastPosition == resume) return;
    _resumeLastPosition = resume;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_resumeLastPositionKey, resume);
    } catch (_) {
      // The switch still applies to the current session.
    }
    if (_syncUid != null) unawaited(syncToFirebase(_syncUid!));
  }

  Future<void> setContinuePlaying(bool continuePlaying) async {
    if (_continuePlaying == continuePlaying) return;
    _continuePlaying = continuePlaying;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_continuePlayingKey, continuePlaying);
    } catch (_) {
      // Same as above: the switch still applies for this session.
    }
    if (_syncUid != null) unawaited(syncToFirebase(_syncUid!));
  }

  Future<void> setStartOnStartup(bool value) async {
    if (_startOnStartup == value) return;
    _startOnStartup = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_startOnStartupKey, value);
    } catch (_) {
      // The switch still applies to the current session.
    }
    if (_syncUid != null) unawaited(syncToFirebase(_syncUid!));
  }
}
