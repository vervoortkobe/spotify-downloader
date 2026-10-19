import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/jam_session_model.dart';
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
    // Invited friends are participants from the very first write. Writing the
    // creator first and adding invitees in a second update left a window where
    // the jam existed with nobody to jam with, and a failed second write left it
    // that way for good.
    final participants = <String>{uid, ...invite};
    final docRef = await _firestore.collection('jam_sessions').add({
      'name': name,
      'createdBy': uid,
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'currentTrackIndex': 0,
      'currentPositionMs': 0,
      'isPlaying': false,
      'ended': false,
      'participants': participants.toList(),
      'createdAt': FieldValue.serverTimestamp(),
    });
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

  /// Every session that has not ended, newest first. A one-shot read for the
  /// polling "live jams" list.
  Future<List<JamSessionModel>> activeSessionsOnce() async {
    final snap = await _firestore.collection('jam_sessions').get();
    return snap.docs
        .where((d) => d.data()['ended'] != true)
        .map(jamSessionFromDoc)
        .toList();
  }

  /// A single session including its shared queue, or null when it is gone. A
  /// one-shot read for the polling in-jam view.
  Future<JamSessionModel?> jamSessionOnce(String sessionId) async {
    final doc = await _firestore
        .collection('jam_sessions')
        .doc(sessionId)
        .get();
    if (!doc.exists) return null;
    return jamSessionFromDoc(doc);
  }

  /// Deserializes a session document, tolerating missing fields.
  static JamSessionModel jamSessionFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return JamSessionModel(
      id: doc.id,
      name: data['name'] as String? ?? '',
      createdBy: data['createdBy'] as String? ?? '',
      tracks: (data['tracks'] as List<dynamic>? ?? const [])
          .map((t) => TrackModel.fromJson(Map<String, dynamic>.from(t as Map)))
          .toList(),
      currentTrackIndex: (data['currentTrackIndex'] as num?)?.toInt() ?? 0,
      currentPositionMs: (data['currentPositionMs'] as num?)?.toInt() ?? 0,
      isPlaying: data['isPlaying'] as bool? ?? false,
      ended: data['ended'] as bool? ?? false,
      participants: (data['participants'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  void dispose() {
    _subscription?.cancel();
  }
}
