import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotterfy_app/models/user_model.dart';
import 'package:spotterfy_app/services/auth_service.dart';
import 'package:spotterfy_app/services/firebase_service.dart';

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
      isApproved: data['isApproved'] as bool? ?? false,
      hasCompletedOnboarding: data['hasCompletedOnboarding'] as bool? ?? false,
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'] as String)
          : DateTime.now(),
      lastSpotifySync: data['lastSpotifySync'] != null
          ? DateTime.parse(data['lastSpotifySync'] as String)
          : null,
    );
  } catch (_) {
    return null;
  }
}

class AuthProvider extends ChangeNotifier {
  /// Created on first use: [AuthService] touches `FirebaseAuth.instance` and
  /// `FirebaseFirestore.instance` in its field initializers, both of which
  /// throw before `Firebase.initializeApp()` has run.
  AuthService? _service;
  AuthService get _authService => _service ??= AuthService();

  UserModel? _user;
  bool _isLoading = true;
  bool _isSigningIn = false;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isSigningIn => _isSigningIn;
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get isApproved => _user?.isApproved ?? false;
  bool get isProfileCompleted =>
      _user != null &&
      _user!.displayName.trim().length >= 3 &&
      _user!.hasCompletedOnboarding;
  bool get needsOnboarding => _user != null && !isProfileCompleted;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    // Firebase first: everything below reads AuthService, which needs it.
    await _ensureFirebase();
    // Load cached user off UI thread - avoid blocking first frame
    await _loadCachedUser();
    // Defer first notify to next frame so Splash can build once without jank
    Future.microtask(() {
      _isLoading = false;
      notifyListeners();
    });

    // Listen for Firebase auth changes (overwrites cache with fresh data)
    _authService.authStateChanges.listen((firebaseUser) async {
      try {
        if (firebaseUser != null) {
          UserModel? userData;
          try {
            userData = await _authService.getUserData(firebaseUser.uid);
          } catch (_) {
            debugPrint('Firestore read blocked (rules) - keeping cached user');
          }

          if (userData != null) {
            _user = userData;
          } else if (_user == null || _user!.uid != firebaseUser.uid) {
            _user = UserModel(
              uid: firebaseUser.uid,
              email: firebaseUser.email ?? '',
              displayName: firebaseUser.displayName ?? '',
              photoUrl: firebaseUser.photoURL ?? '',
              isAdmin: false,
              isApproved: true,
              spotifyProfileUrl: '',
            );
          }
        } else {
          _user = null;
        }
      } catch (e) {
        debugPrint('Auth state listener error: $e');
      }
      await _saveCachedUser();
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<void> _saveCachedUser() async {
    if (_user == null) {
      await SharedPreferences.getInstance().then(
        (p) => p.remove('cached_user'),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'cached_user',
      jsonEncode({
        'uid': _user!.uid,
        'email': _user!.email,
        'displayName': _user!.displayName,
        'photoUrl': _user!.photoUrl,
        'spotifyProfileUrl': _user!.spotifyProfileUrl,
        'isAdmin': _user!.isAdmin,
        'isApproved': _user!.isApproved,
        'hasCompletedOnboarding': _user!.hasCompletedOnboarding,
        'createdAt': _user!.createdAt.toIso8601String(),
        'lastSpotifySync': _user!.lastSpotifySync?.toIso8601String(),
      }),
    );
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
      if (parsed != null) _user = parsed;
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
      if (user != null) await _saveCachedUser();
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
    await _authService.signOut();
    _user = null;
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
    if (trimmed.length < 3)
      throw Exception('Name must be at least 3 characters');
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
    if (trimmed.length < 3)
      throw Exception('Name must be at least 3 characters');
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
    _user!.hasCompletedOnboarding = true;
    await _saveCachedUser();
    notifyListeners();
  }

  Future<void> skipOnboarding() async {
    // do not mark completed, so it will show again next launch if profile incomplete
    notifyListeners();
  }

  Future<void> updateListeningStatus(
    String? trackId, {
    String? jamSessionId,
  }) async {
    if (_user == null) return;
    await _authService.updateListeningStatus(_user!.uid, trackId, jamSessionId);
    _user!.currentListeningTo = trackId;
    _user!.currentJamSession = jamSessionId;
    notifyListeners();
  }

  void refresh() {
    notifyListeners();
  }
}
