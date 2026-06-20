import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserModel?> signInWithGoogle() async {
    try {
      // Android client ID from google-services.json OAuth client (client_type: 3)
      const String serverClientId =
          '393890062277-asirar78ga330bfu96rog9e3hfdbqm9u.apps.googleusercontent.com';
      await GoogleSignIn.instance.initialize(
        serverClientId: serverClientId,
      );
      final GoogleSignInAccount googleUser = await GoogleSignIn.instance
          .authenticate();

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return null;

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        return UserModel.fromFirestore(doc.data()!, user.uid);
      }

      final newUser = UserModel(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? '',
        photoUrl: user.photoURL ?? '',
        isAdmin: false,
        isApproved: false,
      );
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(newUser.toFirestore());
      return newUser;
    } catch (e) {
      debugPrint('Sign in failed: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
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
