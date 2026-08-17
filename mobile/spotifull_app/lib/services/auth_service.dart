import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserModel?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
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
      debugPrint('Sign in failed: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
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
