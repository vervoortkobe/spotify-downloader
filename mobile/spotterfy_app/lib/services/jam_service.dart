import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/track_model.dart';

class JamService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription? _subscription;

  Future<String> createJamSession(
    String uid,
    String name,
    List<TrackModel> tracks, {
    List<String> invite = const [],
  }) async {
    final docRef = await _firestore.collection('jam_sessions').add({
      'name': name,
      'createdBy': uid,
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'currentTrackIndex': 0,
      'currentPositionMs': 0,
      'isPlaying': false,
      'ended': false,
      'participants': [uid],
      'createdAt': FieldValue.serverTimestamp(),
    });
    // Invite everyone up front rather than making them find the session in the
    // live list: a jam you were invited to should already list you as a
    // participant, so it shows up as "your jam" the moment it is created.
    if (invite.isNotEmpty) {
      await _firestore.collection('jam_sessions').doc(docRef.id).update({
        'participants': FieldValue.arrayUnion(invite),
      });
    }
    return docRef.id;
  }

  Future<void> joinJamSession(String uid, String sessionId) async {
    await _firestore.collection('jam_sessions').doc(sessionId).update({
      'participants': FieldValue.arrayUnion([uid]),
    });
  }

  Future<void> leaveJamSession(String uid, String sessionId) async {
    await _firestore.collection('jam_sessions').doc(sessionId).update({
      'participants': FieldValue.arrayRemove([uid]),
    });
  }

  /// Ends a session outright. Only the creator may call this.
  ///
  /// The document is marked rather than deleted: `firestore.rules` sets
  /// `allow delete: false` on `jam_sessions`, so a client-side delete is
  /// rejected. Marking `ended` + `isPlaying: false` achieves the same visible
  /// result - the session drops out of the live list and every participant's
  /// listener sees it close.
  Future<void> endJamSession(String uid, String sessionId) async {
    await _firestore.collection('jam_sessions').doc(sessionId).update({
      'ended': true,
      'endedBy': uid,
      'endedAt': FieldValue.serverTimestamp(),
      'isPlaying': false,
    });
  }

  Future<void> updatePlaybackState(
    String sessionId, {
    bool? isPlaying,
    int? positionMs,
    int? trackIndex,
  }) async {
    final data = <String, dynamic>{};
    if (isPlaying != null) data['isPlaying'] = isPlaying;
    if (positionMs != null) data['currentPositionMs'] = positionMs;
    if (trackIndex != null) data['currentTrackIndex'] = trackIndex;
    await _firestore.collection('jam_sessions').doc(sessionId).update(data);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> listenToJamSession(
    String sessionId,
  ) {
    return _firestore.collection('jam_sessions').doc(sessionId).snapshots();
  }

  Stream<QuerySnapshot> getActiveSessions() {
    return _firestore
        .collection('jam_sessions')
        .where('isPlaying', isEqualTo: true)
        .snapshots();
  }

  void dispose() {
    _subscription?.cancel();
  }
}
