import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseService {
  static Future<void> initialize() async {
    await Firebase.initializeApp();
    FirebaseFirestore.instance.settings = Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  /// Prefix search over the `users` collection, matching display name first
  /// and email as a fallback. Firestore range queries are case-sensitive, so we
  /// run a lowercase and a capitalized pass and merge (deduped by uid).
  static Future<List<Map<String, String>>> searchUsers(
    String query, {
    String? excludeUid,
    int limit = 20,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final byUid = <String, Map<String, String>>{};

    void addDoc(DocumentSnapshot<Map<String, dynamic>> d) {
      final data = d.data();
      if (data == null) return;
      final uid = d.id;
      if (excludeUid != null && uid == excludeUid) return;
      if (byUid.containsKey(uid)) return;
      final display = (data['displayName'] as String?)?.trim() ?? '';
      byUid[uid] = {
        'uid': uid,
        'displayName': display.isNotEmpty
            ? display
            : ((data['email'] as String?) ?? uid),
        'email': (data['email'] as String?) ?? '',
        'photoUrl': (data['photoUrl'] as String?) ?? '',
      };
    }

    /// Range query on one field -> Firestore's automatic single-field index is
    /// enough, so no composite index has to be deployed for search to work.
    Future<void> runOn(String field, String prefix) async {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(field, isGreaterThanOrEqualTo: prefix)
            .where(field, isLessThan: '$prefix\uf8ff')
            .limit(limit)
            .get();
        snap.docs.forEach(addDoc);
      } catch (e) {
        debugPrint('searchUsers($field~$prefix) failed: $e');
      }
    }

    await runOn('displayName', q);
    if (byUid.length < limit && q.isNotEmpty) {
      // Capitalize first letter to catch "John" when stored as "john".
      await runOn('displayName', q[0].toUpperCase() + q.substring(1));
    }
    if (byUid.length < limit && q.contains('@')) {
      await runOn('email', q.toLowerCase());
    }
    return byUid.values.take(limit).toList();
  }
}
