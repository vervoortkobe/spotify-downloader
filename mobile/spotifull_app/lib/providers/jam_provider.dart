import 'package:flutter/material.dart';
import 'dart:async';
import 'package:spotifull_app/models/jam_session_model.dart';
import 'package:spotifull_app/models/track_model.dart';
import 'package:spotifull_app/services/jam_service.dart';

class JamProvider extends ChangeNotifier {
  final JamService _jamService = JamService();
  JamSessionModel? _currentSession;
  List<JamSessionModel> _activeSessions = [];
  StreamSubscription? _sessionSub;
  StreamSubscription? _activeSub;

  JamSessionModel? get currentSession => _currentSession;
  List<JamSessionModel> get activeSessions => _activeSessions;

  JamProvider() {
    _activeSub = _jamService.getActiveSessions().listen((snap) {
      _activeSessions = snap.docs
          .map((d) => JamSessionModel(
                id: d.id,
                name: d['name'] as String? ?? '',
                createdBy: d['createdBy'] as String? ?? '',
                tracks: [],
                participants: (d['participants'] as List<dynamic>?)
                        ?.map((e) => e as String)
                        .toList() ??
                    [],
              ))
          .toList();
      notifyListeners();
    });
  }

  Future<String> createSession(String uid, String name, List<TrackModel> tracks) async {
    final id = await _jamService.createJamSession(uid, name, tracks);
    _sessionSub = _jamService.listenToJamSession(id).listen((snap) {
      _currentSession = JamSessionModel(
        id: snap.id,
        name: snap['name'] as String? ?? '',
        createdBy: snap['createdBy'] as String? ?? '',
        tracks: [],
        currentTrackId: snap['currentTrackIndex']?.toString(),
        currentPositionMs: snap['currentPositionMs'] as int? ?? 0,
        isPlaying: snap['isPlaying'] as bool? ?? false,
        participants: (snap['participants'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );
      notifyListeners();
    });
    return id;
  }

  Future<void> joinSession(String uid, String sessionId) async {
    await _jamService.joinJamSession(uid, sessionId);
    _sessionSub = _jamService.listenToJamSession(sessionId).listen((snap) {
      _currentSession = JamSessionModel(
        id: snap.id,
        name: snap['name'] as String? ?? '',
        createdBy: snap['createdBy'] as String? ?? '',
        tracks: [],
        participants: [],
      );
      notifyListeners();
    });
  }

  Future<void> leaveSession(String uid) async {
    if (_currentSession != null) {
      await _jamService.leaveJamSession(uid, _currentSession!.id);
    }
    _sessionSub?.cancel();
    _currentSession = null;
    notifyListeners();
  }

  Future<void> updatePlayback({bool? isPlaying, int? positionMs, int? trackIndex}) async {
    if (_currentSession == null) return;
    await _jamService.updatePlaybackState(
      _currentSession!.id,
      isPlaying: isPlaying,
      positionMs: positionMs,
      trackIndex: trackIndex,
    );
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _activeSub?.cancel();
    _jamService.dispose();
    super.dispose();
  }
}
