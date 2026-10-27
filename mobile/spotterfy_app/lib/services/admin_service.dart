import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:spotterfy_app/models/feedback_model.dart';
import 'package:spotterfy_app/models/user_model.dart';

/// Reads and moderates user accounts and feedback for the admin panel.
///
/// Firestore rules already allow an admin to update or delete any
/// `users/{userId}` document and manage `feedback`, so moderation goes straight
/// to Firestore - there is no backend endpoint to add or redeploy for any of this.
class AdminService {
  final FirebaseFirestore _firestore;

  AdminService([FirebaseFirestore? firestore])
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Everyone, newest account first.
  ///
  /// Unbounded by design: this is an internal tool that needs to search across
  /// the whole user base, so the filter and sort happen in
  /// [AdminProvider] rather than in the query. Fine at current scale; revisit
  /// with pagination if the user count grows into the thousands.
  Future<List<UserModel>> getAllUsers() async {
    final results = await Future.wait([
      _firestore.collection('users').get(),
      _firestore.collectionGroup('presence').get(),
    ]);
    final userSnap = results[0];
    final presenceSnap = results[1];
    return _decodeUsers(userSnap.docs, _presenceByUid(presenceSnap));
  }

  Map<String, Map<String, dynamic>> _presenceByUid(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final presence = <String, Map<String, dynamic>>{};
    for (final doc in snapshot.docs) {
      if (doc.id != 'current') continue;
      final uid = doc.reference.parent.parent?.id;
      if (uid != null) presence[uid] = doc.data();
    }
    return presence;
  }

  List<UserModel> _decodeUsers(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, Map<String, dynamic>> presence,
  ) {
    final out = <UserModel>[];
    for (final doc in docs) {
      // One malformed document must not take down the entire list.
      try {
        final data = {...doc.data(), ...?presence[doc.id]};
        out.add(UserModel.fromFirestore(data, doc.id));
      } catch (_) {
        continue;
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// Keeps the admin user list and online totals current while the panel is open.
  Stream<List<UserModel>> watchAllUsers() {
    final controller = StreamController<List<UserModel>>();
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? users;
    var presence = <String, Map<String, dynamic>>{};
    void emit() {
      final currentUsers = users;
      if (currentUsers == null || controller.isClosed) return;
      final result = _decodeUsers(currentUsers, presence);
      controller.add(result);
    }

    final usersSub = _firestore.collection('users').snapshots().listen((
      snapshot,
    ) {
      users = snapshot.docs;
      emit();
    }, onError: controller.addError);
    final presenceSub = _firestore
        .collectionGroup('presence')
        .snapshots()
        .listen((snapshot) {
          presence = _presenceByUid(snapshot);
          emit();
        }, onError: controller.addError);
    controller.onCancel = () async {
      await usersSub.cancel();
      await presenceSub.cancel();
    };
    return controller.stream;
  }

  /// How many users have something loaded right now.
  ///
  /// Derived from the already-loaded list, which merges each user's live
  /// `presence/current` document into the corresponding user model.
  int activeCount(List<UserModel> users) =>
      users.where((u) => u.isActiveNow).length;

  Future<int> getPlaylistCount() async {
    final result = await _firestore.collection('playlists').count().get();
    return result.count ?? 0;
  }

  /// Suspends [uid], recording when and why.
  ///
  /// The reason is written alongside the flag because a silent suspension is
  /// indistinguishable from a bug to the person on the receiving end.
  Future<void> suspendUser(String uid, String reason) async {
    await _firestore.collection('users').doc(uid).update({
      'isSuspended': true,
      'suspendedAt': FieldValue.serverTimestamp(),
      'suspendedReason': reason,
    });
  }

  /// Restores an account and clears the reason so stale text cannot resurface.
  Future<void> restoreUser(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'isSuspended': false,
      'suspendedAt': null,
      'suspendedReason': '',
    });
  }

  Future<void> setAdmin(String uid, bool value) async {
    await _firestore.collection('users').doc(uid).update({'isAdmin': value});
  }

  Future<void> setDisplayName(String uid, String name) async {
    await _firestore.collection('users').doc(uid).update({'displayName': name});
  }

  /// Removes the account document entirely.
  ///
  /// Deliberately not exposed in the panel UI: it is irreversible and the
  /// related playlists, friendships and notifications in other collections are
  /// not removed with it, so "delete" here would silently orphan data rather
  /// than clean up. Suspension is the reversible option.
  Future<void> deleteUser(String uid) async {
    await _firestore.collection('users').doc(uid).delete();
  }

  /// Retrieves all feedback submissions, newest first.
  Future<List<FeedbackModel>> getAllFeedback() async {
    final snap = await _firestore.collection('feedback').get();
    final out = <FeedbackModel>[];
    for (final doc in snap.docs) {
      try {
        out.add(FeedbackModel.fromFirestore(doc.data(), doc.id));
      } catch (_) {
        continue;
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// Marks feedback as read or unread.
  Future<void> markFeedbackRead(String feedbackId, bool isRead) async {
    await _firestore.collection('feedback').doc(feedbackId).update({
      'isRead': isRead,
    });
  }

  /// Deletes a feedback item from Firestore.
  Future<void> deleteFeedback(String feedbackId) async {
    await _firestore.collection('feedback').doc(feedbackId).delete();
  }
}
