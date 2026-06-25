import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotifull_app/models/user_model.dart';
import 'package:spotifull_app/services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  UserModel? _user;
  bool _isLoading = true;
  bool _isSigningIn = false;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isSigningIn => _isSigningIn;
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get isApproved => _user?.isApproved ?? false;
  bool get needsOnboarding => _user != null && _user!.spotifyProfileUrl.isEmpty;
  bool get needsSpotifySync {
    if (_user == null || _user!.spotifyProfileUrl.isEmpty) return false;
    if (_user!.lastSpotifySync == null) return true;
    return DateTime.now().difference(_user!.lastSpotifySync!).inHours >= 1;
  }

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    // Load cached user immediately for fast startup
    await _loadCachedUser();
    _isLoading = false;
    notifyListeners();

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
      await SharedPreferences.getInstance()
          .then((p) => p.remove('cached_user'));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_user', jsonEncode({
      'uid': _user!.uid,
      'email': _user!.email,
      'displayName': _user!.displayName,
      'photoUrl': _user!.photoUrl,
      'spotifyProfileUrl': _user!.spotifyProfileUrl,
      'isAdmin': _user!.isAdmin,
      'isApproved': _user!.isApproved,
      'createdAt': _user!.createdAt.toIso8601String(),
      'lastSpotifySync': _user!.lastSpotifySync?.toIso8601String(),
    }));
  }

  Future<void> _loadCachedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_user');
      if (cached == null) return;
      final data = jsonDecode(cached) as Map<String, dynamic>;
      _user = UserModel(
        uid: data['uid'] as String? ?? '',
        email: data['email'] as String? ?? '',
        displayName: data['displayName'] as String? ?? '',
        photoUrl: data['photoUrl'] as String? ?? '',
        spotifyProfileUrl: data['spotifyProfileUrl'] as String? ?? '',
        isAdmin: data['isAdmin'] as bool? ?? false,
        isApproved: data['isApproved'] as bool? ?? false,
        createdAt: data['createdAt'] != null
            ? DateTime.parse(data['createdAt'] as String)
            : DateTime.now(),
        lastSpotifySync: data['lastSpotifySync'] != null
            ? DateTime.parse(data['lastSpotifySync'] as String)
            : null,
      );
    } catch (e) {
      debugPrint('Failed to load cached user: $e');
    }
  }

  Future<bool> signInWithGoogle() async {
    _isSigningIn = true;
    notifyListeners();
    final user = await _authService.signInWithGoogle();
    _user = user;
    if (user != null) await _saveCachedUser();
    _isSigningIn = false;
    notifyListeners();
    return user != null;
  }

  Future<void> signOut() async {
    await _authService.signOut();
    _user = null;
    await _saveCachedUser();
    notifyListeners();
  }

  Future<void> updateSpotifyProfileUrl(String url) async {
    if (_user == null) return;
    await _authService.updateSpotifyUrl(_user!.uid, url);
    _user!.spotifyProfileUrl = url;
    await _saveCachedUser();
    notifyListeners();
  }

  Future<void> updateListeningStatus(String? trackId, {String? jamSessionId}) async {
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
