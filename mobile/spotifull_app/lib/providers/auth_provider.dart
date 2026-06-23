import 'package:flutter/foundation.dart';
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
    _authService.authStateChanges.listen((firebaseUser) async {
      try {
        if (firebaseUser != null) {
          // Try Firestore first, fall back to local-only user (Firestore rules may block)
          UserModel? userData;
          try {
            userData = await _authService.getUserData(firebaseUser.uid);
          } catch (_) {
            debugPrint('Firestore read blocked (rules) - using local-only user');
          }

          if (userData != null) {
            _user = userData;
          } else {
            // Create a minimal user so auth works even without Firestore
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
        _user = null;
      }
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<bool> signInWithGoogle() async {
    _isSigningIn = true;
    notifyListeners();
    final user = await _authService.signInWithGoogle();
    _user = user;
    _isSigningIn = false;
    notifyListeners();
    return user != null;
  }

  Future<void> signOut() async {
    await _authService.signOut();
    _user = null;
    notifyListeners();
  }

  Future<void> updateSpotifyProfileUrl(String url) async {
    if (_user == null) return;
    await _authService.updateSpotifyUrl(_user!.uid, url);
    _user!.spotifyProfileUrl = url;
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
