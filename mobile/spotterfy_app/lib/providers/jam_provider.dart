import 'package:flutter/material.dart';
import 'dart:async';
import 'package:spotterfy_app/models/jam_session_model.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/services/jam_service.dart';

class JamProvider extends ChangeNotifier {
  /// Created on first use: [JamService] touches `FirebaseFirestore.instance` in
  /// its field initializer, which throws before `Firebase.initializeApp()`.
  JamService? _service;
  JamService get _jamService => _service ??= JamService();
  JamSessionModel? _currentSession;
  List<JamSessionModel> _activeSessions = [];
  StreamSubscription? _sessionSub;
  StreamSubscription? _activeSub;

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

  JamProvider() {
    _activeSub = _jamService.getActiveSessions().listen(
      (snap) {
        _activeSessions = snap.docs
            .map(
              (d) => JamSessionModel(
                id: d.id,
                name: d['name'] as String? ?? '',
                createdBy: d['createdBy'] as String? ?? '',
                tracks: [],
                participants:
                    (d['participants'] as List<dynamic>?)
                        ?.map((e) => e as String)
                        .toList() ??
                    [],
              ),
            )
            .toList();
        notifyListeners();
      },
      // See SocialProvider._onListenError: a listener without an error handler
      // turns every PERMISSION_DENIED (which is what a revoked token produces)
      // into an unhandled async exception.
      onError: _onListenError,
    );
  }

  void _onListenError(Object error, StackTrace stack) {
    debugPrint('[Jam] listener stopped: $error');
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
    await _jamService.joinJamSession(uid, sessionId);
    _subscribe(sessionId);
  }

  /// Subscribes to [sessionId] and parses the full document, including the
  /// shared queue.
  void _subscribe(String sessionId) {
    _sessionSub?.cancel();
    _sessionSub = _jamService.listenToJamSession(sessionId).listen((snap) {
      if (!snap.exists) {
        _currentSession = null;
        notifyListeners();
        return;
      }
      final data = snap.data() ?? const {};
      final raw = (data['tracks'] as List<dynamic>? ?? const []);
      _currentSession = JamSessionModel(
        id: snap.id,
        name: data['name'] as String? ?? '',
        createdBy: data['createdBy'] as String? ?? '',
        tracks: raw
            .map(
              (t) => TrackModel.fromJson(Map<String, dynamic>.from(t as Map)),
            )
            .toList(),
        currentTrackIndex: (data['currentTrackIndex'] as num?)?.toInt() ?? 0,
        currentPositionMs: (data['currentPositionMs'] as num?)?.toInt() ?? 0,
        isPlaying: data['isPlaying'] as bool? ?? false,
        participants:
            (data['participants'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );
      notifyListeners();
    }, onError: _onListenError);
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
    _currentSession = null;
    notifyListeners();
  }

  Future<void> leaveSession(String uid) async {
    final session = _currentSession;
    if (session == null) return;
    await _jamService.leaveJamSession(uid, session.id);
    _sessionSub?.cancel();
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
