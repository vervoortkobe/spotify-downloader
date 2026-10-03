import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:spotterfy_app/services/social_service.dart';

/// Live social state for the signed-in user: friends, friend requests,
/// notifications and conversations.
///
/// Subscriptions are started once [start] is called with a uid and torn down in
/// [dispose], so a screen can read the data without owning the lifecycle.
class SocialProvider extends ChangeNotifier {
  final _service = SocialService.instance;

  StreamSubscription<List<SocialUser>>? _friendsSub;
  StreamSubscription<List<FriendRequest>>? _requestsSub;
  StreamSubscription<List<AppNotification>>? _notificationsSub;
  StreamSubscription<List<ChatThread>>? _chatsSub;

  String? _uid;

  List<SocialUser> _friends = const [];
  List<FriendRequest> _requests = const [];
  List<AppNotification> _notifications = const [];
  List<ChatThread> _chats = const [];

  String? get uid => _uid;
  List<SocialUser> get friends => _friends;
  List<FriendRequest> get requests => _requests;
  List<AppNotification> get notifications => _notifications;
  List<ChatThread> get chats => _chats;

  int get unreadNotifications => _notifications.where((n) => !n.read).length;

  List<FriendRequest> get incomingPending =>
      _requests.where((r) => r.isPending && r.isIncoming).toList();

  List<FriendRequest> get outgoingPending =>
      _requests.where((r) => r.isPending && !r.isIncoming).toList();

  bool isFriend(String otherUid) => _friends.any((f) => f.uid == otherUid);

  /// 'none' | 'incoming' | 'outgoing' | 'friends'
  String relationshipWith(String otherUid) {
    if (isFriend(otherUid)) return 'friends';
    for (final r in _requests) {
      if (r.otherUid != otherUid || !r.isPending) continue;
      return r.isIncoming ? 'incoming' : 'outgoing';
    }
    return 'none';
  }

  /// Begins listening. Safe to call repeatedly; only the first call for a given
  /// uid actually subscribes.
  void start(String uid) {
    if (_uid == uid) return;
    stop();
    _uid = uid;
    _friendsSub = _service.friendsStream(uid).listen((v) {
      _friends = v;
      notifyListeners();
    }, onError: _onListenError);
    _requestsSub = _service.friendRequestsStream(uid).listen((v) {
      _requests = v;
      notifyListeners();
    }, onError: _onListenError);
    _notificationsSub = _service.notificationsStream(uid).listen((v) {
      _notifications = v;
      notifyListeners();
    }, onError: _onListenError);
    _chatsSub = _service.chatsStream(uid).listen((v) {
      _chats = v;
      notifyListeners();
    }, onError: _onListenError);
  }

  /// Swallows listener errors instead of letting them escape.
  ///
  /// A `Stream.listen` with no `onError` turns *any* stream error into an
  /// unhandled async exception, which in debug prints an `Unhandled Exception`
  /// and in release takes the isolate's error handler. Every one of these
  /// queries is gated on `request.auth != null`, so the common trigger is
  /// ordinary: the token is revoked by a sign-out while the listen is still
  /// attached, and Firestore answers `PERMISSION_DENIED`. That is a normal
  /// lifecycle event, not a fault worth crashing on - the data simply stops
  /// updating until [syncUid] is called again with a live uid.
  void _onListenError(Object error, StackTrace stack) {
    debugPrint('[Social] listener stopped: $error');
  }

  void stop() {
    _friendsSub?.cancel();
    _requestsSub?.cancel();
    _notificationsSub?.cancel();
    _chatsSub?.cancel();
    _friendsSub = null;
    _requestsSub = null;
    _notificationsSub = null;
    _chatsSub = null;
  }

  /// Called on sign-in / app start once the uid is known.
  void syncUid(String? uid) {
    if (uid == null) {
      stop();
      _uid = null;
      _friends = const [];
      _requests = const [];
      _notifications = const [];
      _chats = const [];
      notifyListeners();
      return;
    }
    start(uid);
  }

  Future<void> sendFriendRequest({
    required String myName,
    required String myPhoto,
    required SocialUser other,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    await _service.sendFriendRequest(
      uid: uid,
      name: myName,
      photoUrl: myPhoto,
      other: other,
    );
  }

  Future<void> acceptRequest({
    required String myName,
    required String myPhoto,
    required FriendRequest request,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    await _service.acceptFriendRequest(
      uid: uid,
      name: myName,
      photoUrl: myPhoto,
      request: request,
    );
  }

  Future<void> declineRequest(FriendRequest request) async {
    final uid = _uid;
    if (uid == null) return;
    await _service.declineFriendRequest(uid, request.otherUid);
  }

  Future<void> unfriend(String otherUid) async {
    final uid = _uid;
    if (uid == null) return;
    await _service.unfriend(uid, otherUid);
  }

  Future<void> markNotificationsRead() async {
    final uid = _uid;
    if (uid == null) return;
    await _service.markNotificationsRead(uid);
  }

  Future<void> sendMessage({
    required String myName,
    required String myPhoto,
    required SocialUser peer,
    required String text,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    await _service.sendMessage(
      uid: uid,
      myName: myName,
      myPhoto: myPhoto,
      peer: peer,
      text: text,
    );
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
