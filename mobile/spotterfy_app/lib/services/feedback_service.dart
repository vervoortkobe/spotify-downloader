import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:spotterfy_app/models/user_model.dart';

/// Handles saving user feedback into Firestore.
class FeedbackService {
  final FirebaseFirestore _firestore;

  FeedbackService([FirebaseFirestore? firestore])
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Submits feedback to the top-level 'feedback' Firestore collection.
  Future<void> submitFeedback({
    required String message,
    UserModel? user,
  }) async {
    final authUser = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? authUser?.uid ?? 'anonymous';
    final email = user?.email ?? authUser?.email ?? '';
    final name = (user?.displayName.trim().isNotEmpty == true)
        ? user!.displayName
        : (authUser?.displayName?.trim().isNotEmpty == true
            ? authUser!.displayName!
            : (email.isNotEmpty ? email : 'Anonymous'));
    final photo = user?.photoUrl ?? authUser?.photoURL ?? '';

    await _firestore.collection('feedback').add({
      'userId': uid,
      'userEmail': email,
      'userName': name,
      'userPhotoUrl': photo,
      'message': message.trim(),
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      'platform': defaultTargetPlatform.name,
    });
  }
}
