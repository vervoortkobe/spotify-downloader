import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
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
          width: radius * 2,
          height: radius * 2,
          child: Stack(
            children: [
              Positioned.fill(
                child: UserAvatar(photoUrl: photoUrl, radius: radius),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: PresenceDot(
                  isOnline: online,
                  borderColor: SpotterfyTheme.surface,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
