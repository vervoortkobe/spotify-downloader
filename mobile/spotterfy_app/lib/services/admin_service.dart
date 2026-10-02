import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:spotterfy_app/models/user_model.dart';

/// Reads and moderates user accounts for the admin panel.
///
/// Firestore rules already allow an admin to update or delete any
/// `users/{userId}` document, so moderation goes straight to Firestore - there
/// is no backend endpoint to add or redeploy for any of this.
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
    final snap = await _firestore.collection('users').get();
    final out = <UserModel>[];
    for (final doc in snap.docs) {
      // One malformed document must not take down the entire list.
      try {
        out.add(UserModel.fromFirestore(doc.data(), doc.id));
      } catch (_) {
        continue;
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// How many users have something loaded right now.
  ///
  /// Derived from the already-loaded list rather than a second query, because
  /// [UserModel.currentListeningTo] is a field on the same document - the
  /// previous separate `where('currentListeningTo', isNull: false)` query cost a
  /// full extra read and could disagree with the list it was meant to describe.
  int activeCount(List<UserModel> users) =>
      users.where((u) => u.isActiveNow).length;

  /// Suspends [uid], recording when and why.
  ///
  /// The reason is written alongside the flag because a silent ban is
  /// indistinguishable from a bug to the person on the receiving end.
  Future<void> banUser(String uid, String reason) async {
    await _firestore.collection('users').doc(uid).update({
      'isBanned': true,
      'bannedAt': FieldValue.serverTimestamp(),
      'bannedReason': reason,
    });
  }

  /// Lifts a ban and clears the reason so a stale one cannot resurface.
  Future<void> unbanUser(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'isBanned': false,
      'bannedAt': null,
      'bannedReason': '',
    });
  }

  Future<void> setAdmin(String uid, bool value) async {
    await _firestore.collection('users').doc(uid).update({'isAdmin': value});
  }

  Future<void> setApproved(String uid, bool value) async {
    await _firestore.collection('users').doc(uid).update({'isApproved': value});
  }

  Future<void> setDisplayName(String uid, String name) async {
    await _firestore.collection('users').doc(uid).update({'displayName': name});
  }

  /// Removes the account document entirely.
  ///
  /// Deliberately not exposed in the panel UI: it is irreversible and the
  /// related playlists, friendships and notifications in other collections are
  /// not removed with it, so "delete" here would silently orphan data rather
  /// than clean up. Ban is the reversible option.
  Future<void> deleteUser(String uid) async {
    await _firestore.collection('users').doc(uid).delete();
  }
}
