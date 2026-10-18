import 'package:flutter/material.dart';
import 'dart:async';
import 'package:spotterfy_app/models/jam_session_model.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/services/jam_service.dart';
import 'package:spotterfy_app/services/polling_service.dart';

class JamProvider extends ChangeNotifier {
  /// Created on first use: [JamService] touches `FirebaseFirestore.instance` in
  /// its field initializer, which throws before `Firebase.initializeApp()`.
  JamService? _service;
  JamService get _jamService => _service ??= JamService();
  JamSessionModel? _currentSession;
  List<JamSessionModel> _activeSessions = [];
  StreamSubscription<List<JamSessionModel>>? _activeSub;
  StreamSubscription<JamSessionModel?>? _sessionSub;
  String? _uid;

  JamSessionModel? get currentSession => _currentSession;
  List<JamSessionModel> get activeSessions => _activeSessions;

  /// True while this user is in a jam. Enforces "one jam at a time": creating or
  /// joining a second session is refused while this is true.
  bool get inJam => _currentSession != null;

  /// Only the creator may end a jam; everyone else leaves instead.
  bool canEnd(String? uid) =>
      _currentSession != null &&
      uid != null &&
      _currentSession!.createdBy == uid;

  /// The shared queue, deserialized from the session document.
  ///
  /// Stored as full track JSON so the queue can be played without a second fetch.
  List<TrackModel> get currentQueue => _currentSession?.tracks ?? const [];

  JamProvider();

  /// Starts (or restarts) polling for [uid]. A null uid tears everything down.
  void syncUid(String? uid) {
    if (_uid == uid) return;
    _uid = uid;
    _activeSub?.cancel();
    _activeSub = null;
    _activeSessions = [];
    if (uid == null) {
      _sessionSub?.cancel();
      _sessionSub = null;
      _currentSession = null;
      notifyListeners();
      return;
    }
    // The live-jam list is discovery data; it does not need the short in-jam
    // interval, so it polls with the rest of the social graph.
    _activeSub = PollingService.instance
        .poll(
          fetch: () => _jamService.activeSessionsOnce(),
          interval: PollingService.socialInterval,
          signature: (list) => list
              .map((s) => '${s.id}:${s.name}:${s.participants.length}')
              .join('|'),
        )
        .listen((sessions) {
          _activeSessions = sessions;
          notifyListeners();
        });
    notifyListeners();
  }

  /// Creates a session and subscribes to it.
  ///
  /// [invite] are uids to add as participants up front. Refuses if already in a
  /// jam - one at a time, so a second create would silently orphan the first.
  Future<String> createSession(
    String uid,
    String name,
    List<TrackModel> tracks, {
    List<String> invite = const [],
  }) async {
    if (_currentSession != null) throw StateError('already in a jam');
    final id = await _jamService.createJamSession(
      uid,
      name,
      tracks,
      invite: invite,
    );
    _subscribe(id);
    return id;
  }

  Future<void> joinSession(String uid, String sessionId) async {
    if (_currentSession != null) throw StateError('already in a jam');
    final alreadyParticipant = _activeSessions.any(
      (session) => session.id == sessionId && session.participants.contains(uid),
    );
    if (!alreadyParticipant) {
      await _jamService.joinJamSession(uid, sessionId);
    }
    _subscribe(sessionId);
  }

  /// Polls [sessionId] for the full document, including the shared queue and
  /// playback state.
  ///
  /// The session polls faster than the rest of the app: everyone in a jam should
  /// see a track change or a play/pause from another participant quickly. A
  /// session that disappears or comes back ended drops this user out of the jam.
  void _subscribe(String sessionId) {
    _sessionSub?.cancel();
    _sessionSub = PollingService.instance
        .poll<JamSessionModel?>(
          fetch: () => _jamService.jamSessionOnce(sessionId),
          interval: PollingService.jamInterval,
          signature: (session) => session == null
              ? 'gone'
              : '${session.tracks.length}:${session.currentTrackIndex}:'
                    '${session.currentPositionMs ~/ 1000}:${session.isPlaying}:'
                    '${session.participants.length}:${session.ended}',
        )
        .listen((session) {
          if (session == null || session.ended) {
            _sessionSub?.cancel();
            _sessionSub = null;
            _currentSession = null;
          } else {
            _currentSession = session;
          }
          notifyListeners();
        });
  }

  /// Ends the jam. Creator only - see [canEnd].
  Future<void> endSession(String uid) async {
    final session = _currentSession;
    if (session == null) return;
    if (session.createdBy != uid) {
      throw StateError('only the creator can end a jam');
    }
    await _jamService.endJamSession(uid, session.id);
    _sessionSub?.cancel();
    _sessionSub = null;
    _currentSession = null;
    notifyListeners();
  }

  Future<void> leaveSession(String uid) async {
    final session = _currentSession;
    if (session == null) return;
    await _jamService.leaveJamSession(uid, session.id);
    _sessionSub?.cancel();
    _sessionSub = null;
    _currentSession = null;
    notifyListeners();
  }

  Future<void> updatePlayback({
    bool? isPlaying,
    int? positionMs,
    int? trackIndex,
  }) async {
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
