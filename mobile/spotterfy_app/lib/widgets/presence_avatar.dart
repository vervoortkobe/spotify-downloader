import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:spotterfy_app/widgets/user_avatar.dart';
import 'package:spotterfy_app/widgets/presence_dot.dart';

/// Friend avatar with a live online/offline indicator.
class PresenceAvatar extends StatelessWidget {
  final String uid;
  final String photoUrl;
  final double radius;

  const PresenceAvatar({
    super.key,
    required this.uid,
    required this.photoUrl,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('presence')
          .doc('current')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final lastActive = (data?['lastActiveAt'] as Timestamp?)?.toDate();
        final online =
            data?['isOnline'] == true &&
            lastActive != null &&
            DateTime.now().difference(lastActive) < const Duration(minutes: 3);
        return SizedBox(
          width: radius * 2 + 6,
          height: radius * 2 + 6,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 3,
                top: 3,
                child: UserAvatar(photoUrl: photoUrl, radius: radius),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: PresenceDot(
                  isOnline: online,
                  borderColor: const Color(0xFF121212),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
