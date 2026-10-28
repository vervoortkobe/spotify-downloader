import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotterfy_app/models/user_model.dart';
import 'package:spotterfy_app/services/auth_service.dart';
import 'package:spotterfy_app/services/avatar_cache.dart';
import 'package:spotterfy_app/services/firebase_service.dart';
import 'package:spotterfy_app/providers/equalizer_provider.dart';
import 'package:spotterfy_app/providers/playback_settings_controller.dart';
import 'package:spotterfy_app/providers/theme_controller.dart';
import 'package:spotterfy_app/services/playback_access.dart';

// Top-level for compute() - must not be inside class
UserModel? _parseUserIsolate(String cached) {
  try {
    final data = jsonDecode(cached) as Map<String, dynamic>;
    return UserModel(
      uid: data['uid'] as String? ?? '',
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      photoUrl: data['photoUrl'] as String? ?? '',
      spotifyProfileUrl: data['spotifyProfileUrl'] as String? ?? '',
      isAdmin: data['isAdmin'] as bool? ?? false,
      isSuspended: data['isSuspended'] as bool? ?? false,
      suspendedAt: data['suspendedAt'] != null
          ? DateTime.parse(data['suspendedAt'] as String)
          : null,
      suspendedReason: data['suspendedReason'] as String? ?? '',
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'] as String)
          : DateTime.now(),
    );
  } catch (_) {
    return null;
  }
}

class AuthProvider extends ChangeNotifier with WidgetsBindingObserver {
  /// Created on first use: [AuthService] touches `FirebaseAuth.instance` and
  /// `FirebaseFirestore.instance` in its field initializers, both of which
  /// throw before `Firebase.initializeApp()` has run.
  AuthService? _service;
  AuthService get _authService => _service ??= AuthService();

  UserModel? _user;
  bool _isLoading = true;
  bool _isSigningIn = false;
  int _authEventGeneration = 0;
  StreamSubscription? _authSubscription;
  StreamSubscription<UserModel?>? _userProfileSubscription;
  Timer? _presenceHeartbeat;
  String? _presenceUid;
  bool _presenceOnline = false;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isSigningIn => _isSigningIn;
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get isProfileCompleted =>
      _user != null && _user!.displayName.trim().length >= 3;
  bool get needsOnboarding => _user != null && !isProfileCompleted;

  /// Account suspended from the admin panel.
  ///
  /// Checked before everything else on the way in, including onboarding, so a
  /// suspended account cannot skip the block by never finishing onboarding.
  bool get isSuspended => _user?.isSuspended ?? false;

  /// Reason shown on the suspended screen, when one was recorded.
  String get suspendedReason => _user?.suspendedReason ?? '';

  /// True when this account must be stopped at the door.
  ///
  /// A suspended admin is *not* let past: `isAdmin` is a separate field and
  /// could otherwise be left set on a suspended account, which would keep granting
  /// access to the admin panel.
  bool get needsModeration => isSuspended;

  /// Mirrors the account's moderation state into the playback gate.
  ///
  /// This is deliberately synchronous: the moment a profile snapshot says the
  /// account is suspended, PlayerProvider can stop the current audio before the
  /// next notification or car button reaches it.
  void _syncPlaybackAccess() {
    PlaybackAccess.instance.update(
      suspended: _user?.isSuspended ?? false,
      softBanned: _user?.isSoftBanned ?? false,
    );
  }

  AuthProvider() {
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final online = state == AppLifecycleState.resumed;
    if (_presenceUid != null && _presenceOnline != online) {
      unawaited(_writeOnlineStatus(online));
    }
  }

  void _startPresence(String uid) {
    if (_presenceUid != uid) {
      final previousUid = _presenceUid;
      if (previousUid != null) {
        unawaited(() async {
          try {
            await _authService.setOnlineStatus(previousUid, false);
            await _authService.updateListeningStatus(previousUid, null, null);
          } catch (e) {
            debugPrint('[Presence] could not clear previous account: $e');
          }
        }());
      }
      _presenceHeartbeat?.cancel();
      _presenceUid = uid;
      _presenceOnline = false;
      _presenceHeartbeat = Timer.periodic(const Duration(minutes: 1), (_) {
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.resumed) {
          unawaited(_writeOnlineStatus(true));
        }
      });
    }
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      unawaited(_writeOnlineStatus(true));
    }
  }

  Future<void> _writeOnlineStatus(bool online) async {
    final uid = _presenceUid;
    if (uid == null) return;
    try {
      await _authService.setOnlineStatus(uid, online);
      _presenceOnline = online;
      if (_user?.uid == uid) {
        _user!.isOnline = online;
        _user!.lastActiveAt = DateTime.now();
      }
    } catch (e) {
      debugPrint('[Presence] online status update failed: $e');
    }
  }

  Future<void> _stopPresence() async {
    final uid = _presenceUid;
    _presenceHeartbeat?.cancel();
    _presenceHeartbeat = null;
    _presenceUid = null;
    _presenceOnline = false;
    if (uid != null) {
      try {
        await _authService.setOnlineStatus(uid, false);
        await _authService.updateListeningStatus(uid, null, null);
      } catch (e) {
        debugPrint('[Presence] could not mark signed-out user offline: $e');
      }
    }
  }

  Future<void> _init() async {
    // Firebase first: everything below reads AuthService, which needs it.
    await _ensureFirebase();
    // Load cached user off UI thread - avoid blocking first frame
    await _loadCachedUser();
    // A cached suspended account must close the playback gate before Android
    // Auto restores the saved queue. With no cache the gate stays closed until
    // the auth stream reports the real account below.
    if (_user != null) _syncPlaybackAccess();
    // Defer first notify to next frame so Splash can build once without jank
    Future.microtask(() {
      _isLoading = false;
      notifyListeners();
    });

    // Listen for Firebase auth changes (overwrites cache with fresh data)
    _authSubscription = _authService.authStateChanges.listen((
      firebaseUser,
    ) async {
      final generation = ++_authEventGeneration;
      await _userProfileSubscription?.cancel();
      _userProfileSubscription = null;
      if (generation != _authEventGeneration) return;
      try {
        if (firebaseUser != null) {
          UserModel? userData;
          // A failed read is *not* the same as "no profile document". The two
          // used to be conflated, so any transient Firestore error (offline,
          // rules, timeout) invented an empty account and left the user logged
          // in with a blank profile.
          var readFailed = false;
          try {
            userData = await _authService.getUserData(firebaseUser.uid);
          } catch (e) {
            readFailed = true;
            debugPrint('Profile read failed for ${firebaseUser.uid}: $e');
          }
          // Auth events can overlap while the Firestore profile read is in
          // flight. A slow response for an old account must not undo a later
          // sign-out or account switch.
          if (generation != _authEventGeneration) return;

          if (userData != null) {
            _user = userData;
          } else if (!readFailed &&
              (_user == null || _user!.uid != firebaseUser.uid)) {
            // Genuinely no profile document (first sign-in): bootstrap a
            // minimal one. Onboarding fills in the rest. We deliberately do
            // NOT do this when the read failed - keeping the cached user (or
            // staying signed out) is far better than a phantom account.
            _user = UserModel(
              uid: firebaseUser.uid,
              email: firebaseUser.email ?? '',
              displayName: firebaseUser.displayName ?? '',
              photoUrl: firebaseUser.photoURL ?? '',
              isAdmin: false,
              spotifyProfileUrl: '',
            );
          }
          _watchUserProfile(firebaseUser.uid, generation);
        } else {
          _user = null;
        }
      } catch (e) {
        debugPrint('Auth state listener error: $e');
      }
      if (generation != _authEventGeneration) return;
      _syncPlaybackAccess();
      if (firebaseUser != null) {
        _startPresence(firebaseUser.uid);
      } else {
        await _stopPresence();
      }
      // Keep the navbar portrait on disk for offline launches. Fire-and-forget:
      // a slow image download must not hold up the signed-in state.
      if (_user != null) unawaited(AvatarCache.warm(_user!.photoUrl));
      await _saveCachedUser();
      if (generation != _authEventGeneration) return;
      _isLoading = false;
      notifyListeners();
    });
  }

  void _watchUserProfile(String uid, int generation) {
    _userProfileSubscription = _authService.watchUserData(uid).listen(
      (freshUser) {
        if (generation != _authEventGeneration ||
            freshUser == null ||
            _user?.uid != uid) {
          return;
        }
        _user = freshUser;
        _syncPlaybackAccess();
        PlaybackSettingsController.instance.bindUid(freshUser.uid);
        ThemeController.instance.bindUid(freshUser.uid);
        EqualizerProvider.setUid(freshUser.uid);
        unawaited(_saveCachedUser());
        notifyListeners();
      },
      onError: (Object error) =>
          debugPrint('Profile watch failed for $uid: $error'),
    );
  }

  Future<void> _saveCachedUser() async {
    // Snapshot the auth generation *before* awaiting: if a sign-out/sign-in
    // lands while the write is in flight, the newer event must win, so a stale
    // write cannot resurrect the cached user after a sign-out cleared it.
    final generation = _authEventGeneration;
    try {
      final user = _user;
      final prefs = await SharedPreferences.getInstance();
      if (generation != _authEventGeneration) return;
      if (user == null) {
        await prefs.remove('cached_user');
        return;
      }
      await prefs.setString(
        'cached_user',
        jsonEncode({
          'uid': user.uid,
          'email': user.email,
          'displayName': user.displayName,
          'photoUrl': user.photoUrl,
          'spotifyProfileUrl': user.spotifyProfileUrl,
          'isAdmin': user.isAdmin,
          'isSuspended': user.isSuspended,
          'suspendedAt': user.suspendedAt?.toIso8601String(),
          'suspendedReason': user.suspendedReason,
          'createdAt': user.createdAt.toIso8601String(),
        }),
      );
    } catch (e) {
      debugPrint('Failed to save cached user: $e');
    }
  }

  @override
  void dispose() {
    _authEventGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _presenceHeartbeat?.cancel();
    final uid = _presenceUid;
    if (uid != null) {
      unawaited(
        _authService.setOnlineStatus(uid, false).catchError((Object error) {
          debugPrint('[Presence] could not mark disposed user offline: $error');
        }),
      );
    }
    _presenceUid = null;
    _authSubscription?.cancel();
    unawaited(_userProfileSubscription?.cancel() ?? Future<void>.value());
    _userProfileSubscription = null;
    super.dispose();
  }

  /// Joins Firebase initialisation instead of assuming it already happened.
  ///
  /// This provider is created lazily by the splash, which initialises Firebase
  /// first, so in practice it is always ready - but the guard costs nothing and
  /// turns a race into a no-op if construction order ever changes again.
  Future<void> _ensureFirebase() async {
    try {
      await FirebaseService.initialize();
    } catch (e) {
      debugPrint('Firebase init failed (auth will retry): $e');
    }
  }

  Future<void> _loadCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_user');
      if (cached == null) return;
      // Offload JSON + DateTime parse to background isolate
      final parsed = await compute(_parseUserIsolate, cached);
      // An identity without a uid is not a usable account; treating it as one
      // is how a blank "logged in" state could appear before Firebase replied.
      if (parsed != null && parsed.uid.isNotEmpty) {
        _user = parsed;
        // Warm the cached portrait now; this also gives an offline launch a
        // chance to reuse it while Firebase is still catching up.
        unawaited(AvatarCache.warm(parsed.photoUrl));
      }
    } catch (e) {
      debugPrint('Failed to load cached user: $e');
    }
  }

  Future<bool> signInWithGoogle() async {
    _isSigningIn = true;
    notifyListeners();
    try {
      final user = await _authService.signInWithGoogle();
      _user = user;
      _syncPlaybackAccess();
      if (user != null) {
        unawaited(AvatarCache.warm(user.photoUrl));
        await _saveCachedUser();
      }
      return user != null;
    } catch (e) {
      debugPrint('AuthProvider sign-in error: $e');
      return false;
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    // Invalidate any profile read still running for the previous account.
    _authEventGeneration++;
    await _userProfileSubscription?.cancel();
    _userProfileSubscription = null;
    try {
      await _authService.signOut();
    } catch (e) {
      // A platform sign-out failure must never leave the app showing the old
      // account as signed in: clear the local state regardless.
      debugPrint('Sign-out error (clearing local state anyway): $e');
    }
    _user = null;
    _syncPlaybackAccess();
    PlaybackSettingsController.instance.bindUid(null);
    ThemeController.instance.bindUid(null);
    EqualizerProvider.setUid(null);
    await _saveCachedUser();
    notifyListeners();
  }

  Future<void> updateSpotifyProfileUrl(String url) async {
    if (_user == null) return;
    try {
      await _authService.updateSpotifyUrl(_user!.uid, url);
    } catch (e) {
      debugPrint('updateSpotifyUrl offline, caching locally: $e');
    }
    _user!.spotifyProfileUrl = url;
    await _saveCachedUser();
    notifyListeners();
  }

  Future<void> updateDisplayName(String name) async {
    if (_user == null) return;
    final trimmed = name.trim();
    if (trimmed.length < 3) {
      throw Exception('Name must be at least 3 characters');
    }
    try {
      await _authService.updateDisplayName(_user!.uid, trimmed);
    } catch (e) {
      debugPrint('updateDisplayName offline, caching locally: $e');
    }
    _user!.displayName = trimmed;
    await _saveCachedUser();
    notifyListeners();
  }

  Future<void> completeOnboarding({
    required String displayName,
    String spotifyUrl = '',
  }) async {
    if (_user == null) return;
    final trimmed = displayName.trim();
    if (trimmed.length < 3) {
      throw Exception('Name must be at least 3 characters');
    }
    if (spotifyUrl.isNotEmpty && !spotifyUrl.contains('open.spotify.com')) {
      throw Exception('Invalid Spotify URL');
    }
    try {
      await _authService.completeProfile(
        _user!.uid,
        displayName: trimmed,
        spotifyUrl: spotifyUrl,
      );
    } catch (e) {
      debugPrint('completeOnboarding offline, caching locally: $e');
    }
    _user!.displayName = trimmed;
    _user!.spotifyProfileUrl = spotifyUrl;
    await _saveCachedUser();
    notifyListeners();
  }

  Future<void> skipOnboarding() async {
    // Spotify linking is optional; the display name remains the required field.
    notifyListeners();
  }

  Future<void> updateListeningStatus(
    String? trackId, {
    String? jamSessionId,
    String trackTitle = '',
    String trackArtist = '',
    String trackArtwork = '',
  }) async {
    if (_user == null) return;
    await _authService.updateListeningStatus(
      _user!.uid,
      trackId,
      jamSessionId,
      trackTitle: trackTitle,
      trackArtist: trackArtist,
      trackArtwork: trackArtwork,
    );
    _user!.currentListeningTo = trackId;
    _user!.currentJamSession = jamSessionId;
    _user!.currentTrackTitle = trackTitle;
    _user!.currentTrackArtist = trackArtist;
    _user!.currentTrackArtwork = trackArtwork;
    notifyListeners();
  }

  /// Reloads the signed-in profile from Firestore (for example, after a
  /// suspended user pulls to refresh to check for a status change).
  Future<void> refreshUserData() async {
    final current = _user;
    if (current == null) return;
    final generation = _authEventGeneration;
    final refreshed = await _authService.getUserData(current.uid);
    if (generation != _authEventGeneration || refreshed == null) return;
    _user = refreshed;
    _syncPlaybackAccess();
    await _saveCachedUser();
    notifyListeners();
  }

  void refresh() {
    notifyListeners();
  }
}
