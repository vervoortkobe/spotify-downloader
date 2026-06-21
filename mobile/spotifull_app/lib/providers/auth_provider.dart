import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
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

  Stream<firebase_auth.User?> get authState => _authService.authStateChanges;

  AuthProvider() {
    _authService.authStateChanges.listen((firebaseUser) async {
      try {
        if (firebaseUser != null) {
          final userData = await _authService.getUserData(firebaseUser.uid);
          if (userData != null) {
            _user = userData;
          }
        } else {
          _user = null;
        }
      } catch (e) {
        debugPrint('Auth state listener error: $e');
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

  Future<void> updateSpotifyUrl(String url) async {
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
