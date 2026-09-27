import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// A person as shown in friend lists, pickers and chat headers.
class SocialUser {
  final String uid;
  final String displayName;
  final String photoUrl;

  const SocialUser({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
  });

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'displayName': displayName,
    'photoUrl': photoUrl,
  };
}

/// A friend request, from either direction.
class FriendRequest {
  final String otherUid;
  final String otherName;
  final String otherPhoto;
  final String status; // pending | accepted | declined

  /// 'incoming' means they asked you; 'outgoing' means you asked them.
  final String direction;
  final DateTime at;

  const FriendRequest({
    required this.otherUid,
    required this.otherName,
    required this.otherPhoto,
    required this.status,
    required this.direction,
    required this.at,
  });

  bool get isIncoming => direction == 'incoming';
  bool get isPending => status == 'pending';

  factory FriendRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? {};
    return FriendRequest(
      otherUid: d.id,
      otherName: (data['name'] as String?) ?? 'User',
      otherPhoto: (data['photoUrl'] as String?) ?? '',
      status: (data['status'] as String?) ?? 'pending',
      direction: (data['direction'] as String?) ?? 'incoming',
      at:
          (data['at'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// An entry in the chat page's notification list.
class AppNotification {
  final String id;
  final String type; // friendRequest | friendAccepted | message
  final String fromUid;
  final String fromName;
  final String photoUrl;
  final String body;
  final DateTime at;
  final bool read;

  const AppNotification({
    required this.id,
    required this.type,
    required this.fromUid,
    required this.fromName,
    required this.photoUrl,
    required this.body,
    required this.at,
    required this.read,
  });

  factory AppNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? {};
    return AppNotification(
      id: d.id,
      type: (data['type'] as String?) ?? 'message',
      fromUid: (data['fromUid'] as String?) ?? '',
      fromName: (data['fromName'] as String?) ?? 'User',
      photoUrl: (data['photoUrl'] as String?) ?? '',
      body: (data['body'] as String?) ?? '',
      at:
          (data['at'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      read: (data['read'] as bool?) ?? false,
    );
  }
}

/// A one-to-one conversation.
class ChatThread {
  final String id;
  final String peerUid;
  final String peerName;
  final String peerPhoto;
  final String lastMessage;
  final DateTime updatedAt;

  const ChatThread({
    required this.id,
    required this.peerUid,
    required this.peerName,
    required this.peerPhoto,
    required this.lastMessage,
    required this.updatedAt,
  });
}

/// A single text message.
class ChatMessage {
  final String id;
  final String senderUid;
  final String text;
  final DateTime at;

  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.text,
    required this.at,
  });
}

/// Friendships, friend requests, notifications and direct messages.
///
/// The model is deliberately simple and one-directional-per-copy: a friend
/// request is written to *both* users' `friendRequests` subcollections (one
/// `outgoing`, one `incoming`) so each side can list their own view with a
/// plain query instead of a collection group. Accepting promotes the pair to
/// `friends`, which is the only thing that gates messaging and jamming.
class SocialService {
  SocialService._internal();
  static final SocialService instance = SocialService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Deterministic id for a pair, so both users derive the same chat document
  /// without coordinating.
  static String chatIdFor(String a, String b) {
    final ids = [a, b]..sort();
    return ids.join('__');
  }

  // ------------------------------------------------------------- friends

  /// Everyone the user has accepted as a friend.
  Stream<List<SocialUser>> friendsStream(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('friends')
        .snapshots()
        .map(
          (snap) => snap.docs.map(_userFromFriendDoc).toList()
            ..sort(
              (a, b) => a.displayName.toLowerCase().compareTo(
                b.displayName.toLowerCase(),
              ),
            ),
        );
  }

  SocialUser _userFromFriendDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? {};
    return SocialUser(
      uid: d.id,
      displayName: (data['displayName'] as String?) ?? 'User',
      photoUrl: (data['photoUrl'] as String?) ?? '',
    );
  }

  /// True when [uid] has [other] as an accepted friend.
  Future<bool> isFriend(String uid, String other) async {
    try {
      final d = await _db
          .collection('users')
          .doc(uid)
          .collection('friends')
          .doc(other)
          .get();
      return d.exists;
    } catch (_) {
      return false;
    }
  }

  // ----------------------------------------------------- friend requests

  Stream<List<FriendRequest>> friendRequestsStream(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('friendRequests')
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map(FriendRequest.fromDoc).toList()
                ..sort((a, b) => b.at.compareTo(a.at)),
        );
  }

  /// Sends a friend request, writing both the sender's outgoing copy and the
  /// recipient's incoming copy, and notifying the recipient.
  Future<void> sendFriendRequest({
    required String uid,
    required String name,
    required String photoUrl,
    required SocialUser other,
  }) async {
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();

    batch.set(
      _db
          .collection('users')
          .doc(uid)
          .collection('friendRequests')
          .doc(other.uid),
      {
        'status': 'pending',
        'direction': 'outgoing',
        'name': other.displayName,
        'photoUrl': other.photoUrl,
        'at': now,
      },
    );
    batch.set(
      _db
          .collection('users')
          .doc(other.uid)
          .collection('friendRequests')
          .doc(uid),
      {
        'status': 'pending',
        'direction': 'incoming',
        'name': name,
        'photoUrl': photoUrl,
        'at': now,
      },
    );
    batch.set(
      _db.collection('users').doc(other.uid).collection('notifications').doc(),
      {
        'type': 'friendRequest',
        'fromUid': uid,
        'fromName': name,
        'photoUrl': photoUrl,
        'body': 'sent you a friend request',
        'read': false,
        'at': now,
      },
    );
    await batch.commit();
  }

  /// Accepts a request: both sides become friends, both request copies are
  /// marked accepted, and the original sender is notified.
  Future<void> acceptFriendRequest({
    required String uid,
    required String name,
    required String photoUrl,
    required FriendRequest request,
  }) async {
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();

    for (final (a, b) in [(uid, request.otherUid), (request.otherUid, uid)]) {
      batch.set(_db.collection('users').doc(a).collection('friends').doc(b), {
        'displayName': a == uid ? request.otherName : name,
        'photoUrl': a == uid ? request.otherPhoto : photoUrl,
        'at': now,
      });
      batch.set(
        _db.collection('users').doc(a).collection('friendRequests').doc(b),
        {
          'status': 'accepted',
          'direction': a == uid ? 'incoming' : 'outgoing',
          'name': a == uid ? request.otherName : name,
          'photoUrl': a == uid ? request.otherPhoto : photoUrl,
          'at': now,
        },
        SetOptions(merge: true),
      );
    }

    batch.set(
      _db
          .collection('users')
          .doc(request.otherUid)
          .collection('notifications')
          .doc(),
      {
        'type': 'friendAccepted',
        'fromUid': uid,
        'fromName': name,
        'photoUrl': photoUrl,
        'body': 'accepted your friend request',
        'read': false,
        'at': now,
      },
    );
    await batch.commit();
  }

  /// Declines (or cancels) a request by marking both copies declined.
  Future<void> declineFriendRequest(String uid, String otherUid) async {
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();
    for (final u in [uid, otherUid]) {
      final other = u == uid ? otherUid : uid;
      batch.set(
        _db.collection('users').doc(u).collection('friendRequests').doc(other),
        {'status': 'declined', 'handledAt': now},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  /// Removes the friendship on both sides.
  Future<void> unfriend(String uid, String otherUid) async {
    final batch = _db.batch();
    for (final u in [uid, otherUid]) {
      final other = u == uid ? otherUid : uid;
      batch.delete(
        _db.collection('users').doc(u).collection('friends').doc(other),
      );
      batch.delete(
        _db.collection('users').doc(u).collection('friendRequests').doc(other),
      );
    }
    await batch.commit();
  }

  // --------------------------------------------------------- notifications

  Stream<List<AppNotification>> notificationsStream(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map(AppNotification.fromDoc).toList()
                ..sort((a, b) => b.at.compareTo(a.at)),
        );
  }

  Future<void> markNotificationsRead(String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();
  }

  // -------------------------------------------------------------- messages

  /// Friends you have a conversation with, newest activity first.
  Stream<List<ChatThread>> chatsStream(String uid) {
    return _db
        .collection('chats')
        .where('members', arrayContains: uid)
        .snapshots()
        .map((snap) {
          final threads = snap.docs.map((
            DocumentSnapshot<Map<String, dynamic>> d,
          ) {
            final data = d.data() ?? {};
            final members = (data['members'] as List?)?.cast<String>() ?? [];
            final peer = members.firstWhere((m) => m != uid, orElse: () => uid);
            final names = (data['memberNames'] as Map?)?.cast<String, String>();
            return ChatThread(
              id: d.id,
              peerUid: peer,
              peerName: names?[peer] ?? 'User',
              peerPhoto: '',
              lastMessage: (data['lastMessage'] as String?) ?? '',
              updatedAt:
                  (data['updatedAt'] as Timestamp?)?.toDate() ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            );
          }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return threads;
        });
  }

  Stream<List<ChatMessage>> messagesStream(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('at')
        .snapshots()
        .map(
          (snap) => snap.docs.map((DocumentSnapshot<Map<String, dynamic>> d) {
            final data = d.data() ?? {};
            return ChatMessage(
              id: d.id,
              senderUid: (data['senderUid'] as String?) ?? '',
              text: (data['text'] as String?) ?? '',
              at:
                  (data['at'] as Timestamp?)?.toDate() ??
                  DateTime.fromMillisecondsSinceEpoch(0),
            );
          }).toList(),
        );
  }

  /// Sends a message, creating the conversation on first use.
  Future<void> sendMessage({
    required String uid,
    required String myName,
    required String myPhoto,
    required SocialUser peer,
    required String text,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final chatId = chatIdFor(uid, peer.uid);
    final chatRef = _db.collection('chats').doc(chatId);
    final now = FieldValue.serverTimestamp();

    final batch = _db.batch();
    batch.set(chatRef, {
      'members': [uid, peer.uid],
      'memberNames': {uid: myName, peer.uid: peer.displayName},
      'memberPhotos': {uid: myPhoto, peer.uid: peer.photoUrl},
      'lastMessage': clean,
      'createdBy': uid,
      'updatedAt': now,
    }, SetOptions(merge: true));
    batch.set(chatRef.collection('messages').doc(), {
      'senderUid': uid,
      'text': clean,
      'at': now,
    });
    batch.set(
      _db.collection('users').doc(peer.uid).collection('notifications').doc(),
      {
        'type': 'message',
        'fromUid': uid,
        'fromName': myName,
        'photoUrl': myPhoto,
        'body': clean,
        'read': false,
        'at': now,
      },
    );
    await batch.commit();
  }

  /// Friend picker data for creating a jam with someone.
  Future<List<SocialUser>> friendsOnce(String uid) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('friends')
          .get();
      return snap.docs.map(_userFromFriendDoc).toList()..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    } catch (e) {
      debugPrint('[Social] friendsOnce failed: $e');
      return const [];
    }
  }
}
