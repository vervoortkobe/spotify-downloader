import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:spotterfy_app/services/social_service.dart';
import 'package:spotterfy_app/services/polling_service.dart';

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

  /// Begins polling for [uid]'s social data. Safe to call repeatedly; only the
  /// first call for a given uid actually starts the timers.
  ///
  /// Each list is refreshed on its own timer. The signature functions keep
  /// [notifyListeners] from firing when a tick returns the same data, so a
  /// quiet account does not rebuild the UI every few seconds.
  void start(String uid) {
    if (_uid == uid) return;
    stop();
    _uid = uid;

    _friendsSub = PollingService.instance
        .poll(
          fetch: () => _service.friendsOnce(uid),
          interval: PollingService.socialInterval,
          signature: (list) => list.map((f) => f.uid).join(','),
        )
        .listen((v) {
          _friends = v;
          notifyListeners();
        });

    _requestsSub = PollingService.instance
        .poll(
          fetch: () => _service.friendRequestsOnce(uid),
          interval: PollingService.socialInterval,
          signature: (list) =>
              list.map((r) => '${r.otherUid}:${r.status}').join(','),
        )
        .listen((v) {
          _requests = v;
          notifyListeners();
        });

    _notificationsSub = PollingService.instance
        .poll(
          fetch: () => _service.notificationsOnce(uid),
          interval: PollingService.socialInterval,
          signature: (list) =>
              '${list.length}:${list.where((n) => !n.read).length}:'
              '${list.isEmpty ? '' : list.first.id}',
        )
        .listen((v) {
          _notifications = v;
          notifyListeners();
        });

    _chatsSub = PollingService.instance
        .poll(
          fetch: () => _service.chatsOnce(uid),
          interval: PollingService.socialInterval,
          signature: (list) => list
              .map(
                (c) =>
                    '${c.id}:${c.updatedAt.millisecondsSinceEpoch}:'
                    '${c.lastMessage}',
              )
              .join('|'),
        )
        .listen((v) {
          _chats = v;
          notifyListeners();
        });
  }

  /// Stops every timer. The polling streams only run while subscribed, so
  /// cancelling is enough - there is no listener to leak.
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
