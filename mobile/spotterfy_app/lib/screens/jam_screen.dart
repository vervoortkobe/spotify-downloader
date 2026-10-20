import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/models/jam_session_model.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/jam_provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/providers/social_provider.dart';
import 'package:spotterfy_app/services/social_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/base_page.dart';
import 'package:spotterfy_app/widgets/mini_player.dart';
import 'package:spotterfy_app/widgets/user_avatar.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/chat_screen.dart';
import 'package:spotterfy_app/screens/profile_screen.dart';
import 'package:spotterfy_app/widgets/jam_session_sheet.dart';

/// The Chat tab: notifications, friend conversations, and live jam sessions.
///
/// The search box filters *friends* (and their conversations), not jam session
/// names, because with a friend graph in place "who can I talk to" is the useful
/// question to ask here.
class JamScreen extends StatefulWidget {
  const JamScreen({super.key});

  @override
  State<JamScreen> createState() => _JamScreenState();
}

class _JamScreenState extends State<JamScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _friendsExpanded = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(
      () =>
          setState(() => _query = _searchController.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool matches(String haystack) =>
      _query.isEmpty || haystack.toLowerCase().contains(_query);

  /// Friends to offer in a picker. A failed read is treated as "no friends" so
  /// the picker can prompt instead of throwing out of an async handler.
  Future<List<SocialUser>> _friendsOrEmpty(String uid) async {
    try {
      return await SocialService.instance.friendsOnce(uid);
    } catch (e) {
      debugPrint('[Jam] friend picker read failed: $e');
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final jam = context.watch<JamProvider>();
    final social = context.watch<SocialProvider>();

    var sessions = jam.activeSessions;
    if (_query.isNotEmpty) {
      sessions = sessions
          .where((s) => s.name.toLowerCase().contains(_query))
          .toList();
    }

    final friends = social.friends
        .where((f) => matches(f.displayName))
        .toList();
    final chats = social.chats.where((c) => matches(c.peerName)).toList();
    // Only surface notifications worth acting on; accepted/friend-request rows
    // are actionable, message notifications are noise once the chat is listed.
    final notifications = social.notifications
        .where((n) => n.type != 'message')
        .where((n) => matches(n.fromName))
        .toList();
    final unread = social.unreadNotifications;

    return BasePageScaffold(
      searchController: _searchController,
      searchHint: 'Search friends',
      query: _query,
      action: IconButton(
        icon: Icon(
          Icons.group_add_rounded,
          color: SpotterfyTheme.muted,
          size: 20,
        ),
        onPressed: () => _createSession(context),
        tooltip: 'New jam',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
      // The mini player is drawn over the bottom of this tab's navigator, so the
      // button is lifted by the footer's height instead of sitting underneath it.
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: MiniPlayer.footerHeight),
        child: FloatingActionButton(
          onPressed: () => _startMessage(context),
          backgroundColor: SpotterfyTheme.accentSurface,
          foregroundColor: SpotterfyTheme.text,
          elevation: 2,
          tooltip: 'New message',
          child: const Icon(Icons.chat_bubble_outline_rounded),
        ),
      ),
      body: ListView(
        // Clears the mini player: the list scrolls under it, but the last row
        // must still be reachable.
        padding: EdgeInsets.only(bottom: MiniPlayer.footerHeight + 56),
        children: [
          if (jam.inJam) _jamBanner(context, jam.currentSession!),
          if (notifications.isNotEmpty) ...[
            _sectionHeader(
              'Notifications',
              badge: unread,
              onTap: social.markNotificationsRead,
            ),
            _group([
              for (final n in notifications.take(20))
                _notificationRow(context, n),
            ]),
            const SizedBox(height: 6),
          ],

          if (chats.isNotEmpty) ...[
            _sectionHeader('Chats', count: chats.length),
            _group([for (final c in chats) _chatRow(context, c)]),
          ] else if (notifications.isEmpty &&
              friends.isEmpty &&
              sessions.isEmpty &&
              !jam.inJam &&
              _query.isEmpty) ...[
            _emptyEverything(),
          ],

          if (friends.isNotEmpty) ...[
            _sectionHeader(
              'Friends',
              count: friends.length,
              trailing: IconButton(
                icon: Icon(
                  _friendsExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: SpotterfyTheme.muted,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _friendsExpanded = !_friendsExpanded),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: _friendsExpanded ? 'Collapse' : 'Expand',
              ),
            ),
            if (_friendsExpanded || _query.isNotEmpty)
              ...friends.map((f) => _friendRow(context, f))
            else
              SizedBox(
                height: 78,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: friends.length,
                  itemBuilder: (_, i) {
                    final f = friends[i];
                    return _friendBubble(context, f);
                  },
                ),
              ),
          ],

          _sectionHeader('Live jams', count: sessions.length),
          if (sessions.isEmpty)
            _emptyJams()
          else
            ...sessions.map((s) => _jamRow(context, s)),
        ],
      ),
    );
  }

  /// One rounded surface holding a run of compact rows.
  ///
  /// Grouping replaces the old stack of individually-bordered cards: the page
  /// reads as two lists (what happened, who you talk to) instead of a pile of
  /// equally loud boxes.
  Widget _group(List<Widget> rows) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SpotterfyTheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpotterfyTheme.borderColor),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: SpotterfyTheme.borderColor.withValues(alpha: 0.7),
              ),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(
    String title, {
    int badge = 0,
    int count = 0,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 10, 8),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: SpotterfyTheme.text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 7),
            Text(
              '$count',
              style: TextStyle(
                color: SpotterfyTheme.mutedDark,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (badge > 0) ...[
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: SpotterfyTheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$badge',
                style: TextStyle(
                  color: SpotterfyTheme.onAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          const Spacer(),
          ?trailing,
          if (onTap != null && badge > 0)
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Mark read',
                style: TextStyle(
                  color: SpotterfyTheme.muted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Compact notification row: 30px avatar, one line of body text, and small
  /// accept/decline actions. The previous row was an 80px avatar inside a
  /// full card, which made three notifications fill the screen.
  Widget _notificationRow(BuildContext context, AppNotification n) {
    final isRequest = n.type == 'friendRequest';
    return Material(
      color: n.read
          ? Colors.transparent
          : SpotterfyTheme.primary.withValues(alpha: 0.06),
      child: InkWell(
        onTap: isRequest ? null : () => _openProfile(context, n.fromUid),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
          child: Row(
            children: [
              _avatar(n.photoUrl, 15),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            n.fromName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: SpotterfyTheme.text,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (!n.read) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: SpotterfyTheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      n.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: SpotterfyTheme.mutedDark,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isRequest) ...[
                _compactIcon(
                  Icons.check_rounded,
                  SpotterfyTheme.primary,
                  'Accept',
                  () => _acceptRequest(context, n.fromUid),
                ),
                _compactIcon(
                  Icons.close_rounded,
                  SpotterfyTheme.mutedDark,
                  'Decline',
                  () => _declineRequest(context, n.fromUid),
                ),
              ] else
                Icon(
                  Icons.chevron_right_rounded,
                  color: SpotterfyTheme.mutedDark,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Small tap target for the inline notification/friend actions.
  ///
  /// Deliberately smaller than the 48px default: a notification row with two of
  /// those was taller than the content it carried.
  Widget _compactIcon(
    IconData icon,
    Color color,
    String tooltip,
    VoidCallback onTap,
  ) {
    return IconButton(
      icon: Icon(icon, color: color, size: 18),
      tooltip: tooltip,
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
    );
  }

  Future<void> _acceptRequest(BuildContext context, String otherUid) async {
    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    final req = social.requests.where(
      (r) => r.otherUid == otherUid && r.isPending,
    );
    if (req.isEmpty) return;
    await social.acceptRequest(
      myName: auth.user?.displayName ?? 'Me',
      myPhoto: auth.user?.photoUrl ?? '',
      request: req.first,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Friend added')));
  }

  Future<void> _declineRequest(BuildContext context, String otherUid) async {
    final social = context.read<SocialProvider>();
    final req = social.requests.where(
      (r) => r.otherUid == otherUid && r.isPending,
    );
    if (req.isEmpty) return;
    await social.declineRequest(req.first);
  }

  Widget _chatRow(BuildContext context, ChatThread c) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openThread(context, c),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
          child: Row(
            children: [
              _avatar(c.peerPhoto, 17),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      c.peerName,
                      style: TextStyle(
                        color: SpotterfyTheme.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      c.lastMessage,
                      style: TextStyle(
                        color: SpotterfyTheme.mutedDark,
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: SpotterfyTheme.mutedDark,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Friend avatar in the horizontal row, with a soft accent ring.
  Widget _friendBubble(BuildContext context, SocialUser f) {
    return GestureDetector(
      onTap: () => _openChat(context, f),
      child: Container(
        width: 68,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: SpotterfyTheme.primary.withValues(alpha: 0.32),
                  width: 1.4,
                ),
              ),
              child: _avatar(f.photoUrl, 22),
            ),
            const SizedBox(height: 6),
            Text(
              f.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: SpotterfyTheme.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _friendRow(BuildContext context, SocialUser f) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      leading: _avatar(f.photoUrl, 18),
      title: Text(
        f.displayName,
        style: TextStyle(
          color: SpotterfyTheme.text,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _compactIcon(
            Icons.graphic_eq_rounded,
            SpotterfyTheme.primary,
            'Create a jam',
            () => _createSession(context, withFriend: f),
          ),
          const SizedBox(width: 4),
          _compactIcon(
            Icons.chat_bubble_outline_rounded,
            SpotterfyTheme.text,
            'Message',
            () => _openChat(context, f),
          ),
        ],
      ),
      onTap: () => _openChat(context, f),
    );
  }

  Widget _jamRow(BuildContext context, dynamic s) {
    final jam = context.read<JamProvider>();
    final auth = context.read<AuthProvider>();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: SpotterfyTheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SpotterfyTheme.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: SpotterfyTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.groups_rounded,
              color: SpotterfyTheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: SpotterfyTheme.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${s.participants.length} listening',
                  style: TextStyle(
                    color: SpotterfyTheme.mutedDark,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (jam.inJam)
            OutlinedButton(
              onPressed: null,
              style: OutlinedButton.styleFrom(
                disabledForegroundColor: SpotterfyTheme.mutedDark,
                side: BorderSide(color: SpotterfyTheme.borderColor),
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('In a jam'),
            )
          else
            ElevatedButton(
              onPressed: () async {
                if (auth.user == null) return;
                try {
                  await jam.joinSession(auth.user!.uid, s.id);
                } on StateError catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('$e')));
                  }
                  return;
                }
                if (context.mounted) showJamSessionSheet(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: SpotterfyTheme.primary,
                foregroundColor: SpotterfyTheme.onAccent,
                elevation: 0,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('Join'),
            ),
        ],
      ),
    );
  }

  /// Shared by the friend rows and the jam picker.
  ///
  /// [radius] is the circle's radius: callers pass the size they want, since the
  /// old call sites passed diameters here and every avatar came out double size.
  Widget _avatar(String photoUrl, double radius) =>
      UserAvatar(photoUrl: photoUrl, radius: radius);

  /// Nothing at all yet: no notifications, chats, friends or jams.
  Widget _emptyEverything() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: SpotterfyTheme.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.forum_outlined,
                color: SpotterfyTheme.primary.withValues(alpha: 0.85),
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No chats or jams yet',
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Start a conversation or join a jam session',
              textAlign: TextAlign.center,
              style: TextStyle(color: SpotterfyTheme.mutedDark, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// No live jams: an icon-led empty block instead of a bare line of text.
  Widget _emptyJams() {
    final searching = _query.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        decoration: BoxDecoration(
          color: SpotterfyTheme.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: SpotterfyTheme.borderColor.withValues(alpha: 0.8),
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: SpotterfyTheme.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.groups_outlined,
                color: SpotterfyTheme.primary.withValues(alpha: 0.85),
                size: 22,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              searching ? 'No jams for "$_query"' : 'No live jams right now',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              searching
                  ? 'Try another search'
                  : 'Start one and invite a friend',
              textAlign: TextAlign.center,
              style: TextStyle(color: SpotterfyTheme.mutedDark, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }

  void _openChat(BuildContext context, SocialUser peer) {
    Navigator.push(context, swipeRoute(ChatScreen(peer: peer)));
  }

  /// Opens a conversation from its thread summary.
  ///
  /// [ChatScreen] takes the peer rather than the thread id, so the summary is
  /// mapped back to a [SocialUser] here.
  void _openThread(BuildContext context, ChatThread c) {
    Navigator.push(
      context,
      swipeRoute(
        ChatScreen(
          peer: SocialUser(
            uid: c.peerUid,
            displayName: c.peerName,
            photoUrl: c.peerPhoto,
          ),
        ),
      ),
    );
  }

  void _openProfile(BuildContext context, String uid) {
    Navigator.push(context, swipeRoute(ProfileScreen(uid: uid)));
  }

  /// Persistent "you are in a jam" strip. Tapping it opens the session sheet.
  Widget _jamBanner(BuildContext context, JamSessionModel session) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: const Color(0xFF12241c),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showJamSessionSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: SpotterfyTheme.primary.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.groups_rounded,
                    color: SpotterfyTheme.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        session.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: SpotterfyTheme.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: session.isPlaying
                                  ? SpotterfyTheme.primary
                                  : SpotterfyTheme.mutedDark,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            session.isPlaying ? 'Playing now' : 'Paused',
                            style: TextStyle(
                              color: SpotterfyTheme.muted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: SpotterfyTheme.muted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Picks a friend, then asks for the text and sends it.
  ///
  /// Two steps on purpose: "send a message" needs both a recipient and content,
  /// and a single dialog that did both would have to invent a recipient when
  /// the user only meant to open an existing conversation.
  Future<void> _startMessage(BuildContext context) async {
    final uid = context.read<SocialProvider>().uid;
    if (uid == null) return;
    final friends = await _friendsOrEmpty(uid);
    if (!context.mounted) return;
    if (friends.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add a friend first')));
      return;
    }
    final picked = await showModalBottomSheet<SocialUser>(
      context: context,
      useRootNavigator: true,
      backgroundColor: SpotterfyTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text(
                'Message',
                style: TextStyle(
                  color: SpotterfyTheme.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: friends.length,
                itemBuilder: (_, i) {
                  final f = friends[i];
                  return ListTile(
                    leading: _avatar(f.photoUrl, 20),
                    title: Text(
                      f.displayName,
                      style: TextStyle(color: SpotterfyTheme.text),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: SpotterfyTheme.muted,
                    ),
                    onTap: () => Navigator.pop(sheetCtx, f),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;

    final text = await _promptMessage(context);
    if (text == null || text.isEmpty || !context.mounted) return;
    final auth = context.read<AuthProvider>();
    await context.read<SocialProvider>().sendMessage(
      myName: auth.user?.displayName ?? 'Me',
      myPhoto: auth.user?.photoUrl ?? '',
      peer: picked,
      text: text,
    );
  }

  Future<String?> _promptMessage(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotterfyTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Message', style: TextStyle(color: SpotterfyTheme.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: SpotterfyTheme.text),
          decoration: InputDecoration(
            hintText: 'Type a message',
            hintStyle: TextStyle(color: SpotterfyTheme.mutedDark),
            filled: true,
            fillColor: SpotterfyTheme.fill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: SpotterfyTheme.mutedDark),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: SpotterfyTheme.primary,
              foregroundColor: SpotterfyTheme.onAccent,
            ),
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  /// Creates a jam. When launched from a friend row the session is named for
  /// that friend and they're invited immediately; from the app bar it opens a
  /// picker of friends.
  void _createSession(BuildContext context, {SocialUser? withFriend}) {
    if (withFriend != null) {
      _showJamDialog(
        context,
        initialName: 'Jam with ${withFriend.displayName}',
        invite: [withFriend.uid],
      );
      return;
    }
    _showFriendPicker(context);
  }

  /// Multi-select friend picker for the app-bar "new jam" action.
  Future<void> _showFriendPicker(BuildContext context) async {
    final uid = context.read<SocialProvider>().uid;
    if (uid == null) return;
    final friends = await _friendsOrEmpty(uid);
    if (!context.mounted) return;

    if (friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a friend first — jams are with friends'),
        ),
      );
      return;
    }

    final picked = await showModalBottomSheet<List<SocialUser>>(
      context: context,
      // Above the mini player: the sheet is opened on a tab navigator, which
      // the mini player is drawn over.
      useRootNavigator: true,
      backgroundColor: SpotterfyTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => _FriendPicker(friends: friends),
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;

    final names = picked.map((f) => f.displayName).toList();
    final initial = names.length == 1
        ? 'Jam with ${names.first}'
        : 'Jam with ${names.take(2).join(', ')}${names.length > 2 ? ' +${names.length - 2}' : ''}';
    _showJamDialog(
      context,
      initialName: initial,
      invite: picked.map((f) => f.uid).toList(),
    );
  }

  void _showJamDialog(
    BuildContext context, {
    String initialName = '',
    List<String> invite = const [],
  }) {
    final nameController = TextEditingController(text: initialName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotterfyTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Create Jam Session',
          style: TextStyle(color: SpotterfyTheme.text),
        ),
        content: TextField(
          controller: nameController,
          style: TextStyle(color: SpotterfyTheme.text),
          decoration: InputDecoration(
            hintText: 'Session name',
            hintStyle: TextStyle(color: SpotterfyTheme.mutedDark),
            filled: true,
            fillColor: SpotterfyTheme.fill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: SpotterfyTheme.mutedDark),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final auth = context.read<AuthProvider>();
              final jam = context.read<JamProvider>();
              final playlistProv = context.read<PlaylistProvider>();
              final name = nameController.text.trim();
              if (auth.user == null || name.isEmpty) return;
              // One jam at a time: refuse rather than orphan the current session.
              if (jam.inJam) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('You are already in a jam')),
                  );
                }
                return;
              }
              final tracks = playlistProv.currentPlaylist?.tracks ?? const [];
              try {
                await jam.createSession(
                  auth.user!.uid,
                  name,
                  tracks,
                  invite: invite,
                );
              } on StateError catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('$e')));
                }
                return;
              }
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) showJamSessionSheet(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: SpotterfyTheme.primary,
              foregroundColor: SpotterfyTheme.onAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

/// Multi-select friend picker for starting a jam.
///
/// Returns the chosen friends, or null if dismissed. Multi-select because a jam
/// is a group thing: the creator picks everyone up front rather than hoping they
/// find the session in the live list.
class _FriendPicker extends StatefulWidget {
  final List<SocialUser> friends;

  const _FriendPicker({required this.friends});

  @override
  State<_FriendPicker> createState() => _FriendPickerState();
}

class _FriendPickerState extends State<_FriendPicker> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text(
              'Who is in this jam?',
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.friends.length,
              itemBuilder: (_, i) {
                final f = widget.friends[i];
                final on = _selected.contains(f.uid);
                return ListTile(
                  leading: UserAvatar(photoUrl: f.photoUrl, radius: 20),
                  title: Text(
                    f.displayName,
                    style: TextStyle(color: SpotterfyTheme.text),
                  ),
                  trailing: Icon(
                    on ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: on ? SpotterfyTheme.primary : SpotterfyTheme.muted,
                  ),
                  onTap: () => setState(() {
                    if (on) {
                      _selected.remove(f.uid);
                    } else {
                      _selected.add(f.uid);
                    }
                  }),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.pop(
                        context,
                        widget.friends
                            .where((f) => _selected.contains(f.uid))
                            .toList(),
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SpotterfyTheme.primary,
                  foregroundColor: SpotterfyTheme.onAccent,
                ),
                child: Text(
                  _selected.isEmpty
                      ? 'Select friends'
                      : 'Add ${_selected.length} '
                            '${_selected.length == 1 ? 'friend' : 'friends'}',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
