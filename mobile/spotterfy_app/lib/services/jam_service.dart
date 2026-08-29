import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/track_model.dart';

class JamService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription? _subscription;

  Future<String> createJamSession(String uid, String name, List<TrackModel> tracks) async {
    final docRef = await _firestore.collection('jam_sessions').add({
      'name': name,
      'createdBy': uid,
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'currentTrackIndex': 0,
      'currentPositionMs': 0,
      'isPlaying': false,
      'participants': [uid],
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

  Future<void> updatePlaybackState(String sessionId, {bool? isPlaying, int? positionMs, int? trackIndex}) async {
    final data = <String, dynamic>{};
    if (isPlaying != null) data['isPlaying'] = isPlaying;
    if (positionMs != null) data['currentPositionMs'] = positionMs;
    if (trackIndex != null) data['currentTrackIndex'] = trackIndex;
    await _firestore.collection('jam_sessions').doc(sessionId).update(data);
  }

  Stream<DocumentSnapshot> listenToJamSession(String sessionId) {
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
