import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/social_provider.dart';
import 'package:spotterfy_app/services/social_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/app_chrome.dart';
import 'package:spotterfy_app/widgets/presence_avatar.dart';
import 'package:spotterfy_app/widgets/user_avatar.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SocialProvider>().markNotificationsRead();
    });
  }

  Future<void> _respond(FriendRequest request, bool accept) async {
    final social = context.read<SocialProvider>();
    final auth = context.read<AuthProvider>();
    if (accept) {
      await social.acceptRequest(
        myName: auth.user?.displayName ?? 'Me',
        myPhoto: auth.user?.photoUrl ?? '',
        request: request,
      );
    } else {
      await social.declineRequest(request);
    }
  }

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialProvider>();
    return HideAppChrome(
      child: AppGradientScaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Notifications',
            style: TextStyle(
              color: SpotterfyTheme.text,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: social.notifications.isEmpty
            ? Center(
                child: Text(
                  "You're all caught up",
                  style: TextStyle(color: SpotterfyTheme.muted),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                itemCount: social.notifications.length,
                separatorBuilder: (context, index) => Divider(
                  color: SpotterfyTheme.borderColor,
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  final notification = social.notifications[index];
                  final requests = social.requests
                      .where(
                        (candidate) =>
                            candidate.otherUid == notification.fromUid &&
                            candidate.isIncoming &&
                            candidate.isPending,
                      )
                      .toList();
                  final request = requests.isEmpty ? null : requests.first;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    leading: social.isFriend(notification.fromUid)
                        ? PresenceAvatar(
                            uid: notification.fromUid,
                            photoUrl: notification.photoUrl,
                            radius: 20,
                          )
                        : UserAvatar(
                            photoUrl: notification.photoUrl,
                            radius: 20,
                          ),
                    title: Text(
                      notification.fromName,
                      style: TextStyle(
                        color: SpotterfyTheme.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      notification.body,
                      style: TextStyle(color: SpotterfyTheme.muted),
                    ),
                    trailing: request == null
                        ? (notification.read
                              ? null
                              : Icon(
                                  Icons.circle,
                                  color: SpotterfyTheme.primary,
                                  size: 9,
                                ))
                        : Wrap(
                            spacing: 6,
                            children: [
                              FilledButton.icon(
                                onPressed: () => _respond(request, true),
                                icon: const Icon(Icons.check_rounded, size: 16),
                                label: const Text('Accept'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: SpotterfyTheme.primaryDark,
                                  foregroundColor: SpotterfyTheme.onAccent,
                                  elevation: 5,
                                  shadowColor: SpotterfyTheme.primary.withValues(alpha: 0.5),
                                  minimumSize: const Size(0, 36),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  shape: const StadiumBorder(),
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _respond(request, false),
                                icon: const Icon(Icons.close_rounded, size: 16),
                                label: const Text('Deny'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: SpotterfyTheme.muted,
                                  backgroundColor: SpotterfyTheme.surface,
                                  minimumSize: const Size(0, 36),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  side: BorderSide(color: SpotterfyTheme.borderColor),
                                  shape: const StadiumBorder(),
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  );
                },
              ),
      ),
    );
  }
}
