import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // google_sign_in ^7.2.0 uses singleton instance
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserModel?> signInWithGoogle() async {
    try {
      // 7.x requires initialize() before authenticate()
      try {
        await _googleSignIn.initialize();
      } catch (_) {
        // already initialized or no serverClientId needed for basic scopes
      }

      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate();

      // In 7.x googleUser.authentication is sync and only has idToken
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return null;

      try {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          return UserModel.fromFirestore(doc.data()!, user.uid);
        }
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
      }

      final newUser = UserModel(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? '',
        photoUrl: user.photoURL ?? '',
        isAdmin: false,
        isApproved: false,
      );
      try {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .set(newUser.toFirestore());
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
      }
      return newUser;
    } catch (e) {
      debugPrint('Google sign-in failed: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  Future<UserModel?> getUserData(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc.data()!, uid);
  }

  Future<void> updateSpotifyUrl(String uid, String url) async {
    await _firestore.collection('users').doc(uid).update({
      'spotifyProfileUrl': url,
    });
  }

  Future<void> updateDisplayName(String uid, String name) async {
    await _firestore.collection('users').doc(uid).update({'displayName': name});
  }

  Future<void> completeProfile(
    String uid, {
    required String displayName,
    String spotifyUrl = '',
  }) async {
    await _firestore.collection('users').doc(uid).update({
      'displayName': displayName,
      'spotifyProfileUrl': spotifyUrl,
      'hasCompletedOnboarding': true,
    });
  }

  Future<void> updateListeningStatus(
    String uid,
    String? trackId,
    String? jamSessionId,
  ) async {
    await _firestore.collection('users').doc(uid).update({
      'currentListeningTo': trackId,
      'currentJamSession': jamSessionId,
    });
  }

  Future<List<UserModel>> getAllUsers() async {
    final snap = await _firestore.collection('users').get();
    return snap.docs
        .map((d) => UserModel.fromFirestore(d.data(), d.id))
        .toList();
  }

  Future<void> approveUser(String uid) async {
    await _firestore.collection('users').doc(uid).update({'isApproved': true});
  }

  Future<void> denyUser(String uid) async {
    await _firestore.collection('users').doc(uid).delete();
  }

  Future<int> getActiveUserCount() async {
    final snap = await _firestore
        .collection('users')
        .where('currentListeningTo', isNull: false)
        .get();
    return snap.docs.length;
  }
}
