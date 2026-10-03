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
        icon: Icon(Icons.group_add, color: SpotterfyTheme.muted, size: 20),
        onPressed: () => _createSession(context),
        tooltip: 'New jam',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
      // Sits above the mini player, which is drawn over this tab's navigator.
      floatingActionButton: FloatingActionButton(
        onPressed: () => _startMessage(context),
        backgroundColor: SpotterfyTheme.primary,
        foregroundColor: Colors.black,
        tooltip: 'New message',
        child: const Icon(Icons.chat_bubble_outline),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 110),
        children: [
          if (jam.inJam) _jamBanner(context, jam.currentSession!),
          if (notifications.isNotEmpty) ...[
            _sectionHeader(
              'Notifications',
              badge: unread,
              onTap: social.markNotificationsRead,
            ),
            ...notifications.take(20).map((n) => _notificationRow(context, n)),
            const SizedBox(height: 8),
          ],

          if (chats.isNotEmpty) ...[
            _sectionHeader('Chats'),
            ...chats.map((c) => _chatRow(context, c)),
          ] else if (notifications.isEmpty && friends.isEmpty && sessions.isEmpty && !jam.inJam && _query.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      color: SpotterfyTheme.mutedDark,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No chats or jams yet',
                      style: TextStyle(
                        color: SpotterfyTheme.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Start a conversation or join a jam session',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: SpotterfyTheme.mutedDark,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (friends.isNotEmpty) ...[
            _sectionHeader(
              'Friends',
              trailing: IconButton(
                icon: Icon(
                  _friendsExpanded ? Icons.expand_less : Icons.expand_more,
                  color: SpotterfyTheme.muted,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _friendsExpanded = !_friendsExpanded),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
            if (_friendsExpanded || _query.isNotEmpty)
              ...friends.map((f) => _friendRow(context, f))
            else
              SizedBox(
                height: 74,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: friends.length,
                  itemBuilder: (_, i) {
                    final f = friends[i];
                    return GestureDetector(
                      onTap: () => _openChat(context, f),
                      child: Container(
                        width: 66,
                        margin: const EdgeInsets.only(right: 12),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: SpotterfyTheme.surface,
                              backgroundImage: f.photoUrl.isNotEmpty
                                  ? NetworkImage(f.photoUrl)
                                  : null,
                              child: f.photoUrl.isEmpty
                                  ? Icon(
                                      Icons.person,
                                      color: SpotterfyTheme.muted,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              f.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: SpotterfyTheme.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],

          _sectionHeader('Live jams'),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: Center(
                child: Text(
                  _query.isNotEmpty
                      ? 'No jams for "$_query"'
                      : 'No active jam sessions',
                  style: TextStyle(color: SpotterfyTheme.text, fontSize: 16),
                ),
              ),
            )
          else
            ...sessions.map((s) => _jamRow(context, s)),
        ],
      ),
    );
  }

  Widget _sectionHeader(
    String title, {
    int badge = 0,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: SpotterfyTheme.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (badge > 0) ...[
            SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: SpotterfyTheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$badge',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          Spacer(),
          ?trailing,
          if (onTap != null && badge > 0)
            TextButton(
              onPressed: onTap,
              child: Text(
                'Mark read',
                style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  /// Chat-style row: avatar, who + what, time.
  Widget _notificationRow(BuildContext context, AppNotification n) {
    final isRequest = n.type == 'friendRequest';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: n.read ? SpotterfyTheme.surface : const Color(0xFF12241c),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: n.read
              ? SpotterfyTheme.borderColor
              : SpotterfyTheme.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          _avatar(n.photoUrl, 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n.fromName,
                  style: TextStyle(
                    color: SpotterfyTheme.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  n.body,
                  style: TextStyle(
                    color: SpotterfyTheme.mutedDark,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isRequest)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.check,
                    color: SpotterfyTheme.primary,
                    size: 20,
                  ),
                  tooltip: 'Accept',
                  onPressed: () => _acceptRequest(context, n.fromUid),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: SpotterfyTheme.mutedDark,
                    size: 20,
                  ),
                  tooltip: 'Decline',
                  onPressed: () => _declineRequest(context, n.fromUid),
                ),
              ],
            )
          else
            IconButton(
              icon: Icon(
                Icons.chevron_right,
                color: SpotterfyTheme.mutedDark,
                size: 20,
              ),
              onPressed: () => _openProfile(context, n.fromUid),
            ),
        ],
      ),
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SpotterfyTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SpotterfyTheme.borderColor),
      ),
      child: Row(
        children: [
          _avatar(c.peerPhoto, 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.peerName,
                  style: TextStyle(
                    color: SpotterfyTheme.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  c.lastMessage,
                  style: TextStyle(
                    color: SpotterfyTheme.mutedDark,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: SpotterfyTheme.mutedDark, size: 20),
        ],
      ),
    );
  }

  Widget _friendRow(BuildContext context, SocialUser f) {
    return ListTile(
      dense: true,
      leading: _avatar(f.photoUrl, 38),
      title: Text(
        f.displayName,
        style: TextStyle(
          color: SpotterfyTheme.text,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              Icons.music_note,
              color: SpotterfyTheme.primary,
              size: 20,
            ),
            tooltip: 'Create a jam',
            onPressed: () => _createSession(context, withFriend: f),
          ),
          IconButton(
            icon: Icon(
              Icons.chat_bubble_outline,
              color: SpotterfyTheme.text,
              size: 20,
            ),
            tooltip: 'Message',
            onPressed: () => _openChat(context, f),
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SpotterfyTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SpotterfyTheme.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: SpotterfyTheme.borderColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.groups, color: SpotterfyTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.name,
                  style: TextStyle(
                    color: SpotterfyTheme.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${s.participants.length} listening',
                  style: TextStyle(
                    color: SpotterfyTheme.mutedDark,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (jam.inJam)
            OutlinedButton(
              onPressed: null,
              style: OutlinedButton.styleFrom(
                foregroundColor: SpotterfyTheme.mutedDark,
                side: BorderSide(color: SpotterfyTheme.borderColor),
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
                foregroundColor: SpotterfyTheme.text,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Join'),
            ),
        ],
      ),
    );
  }

  /// Shared by the friend rows and the jam picker.
  Widget _avatar(String photoUrl, double radius) => CircleAvatar(
    radius: radius,
    backgroundColor: SpotterfyTheme.surface,
    backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
    child: photoUrl.isEmpty
        ? Icon(Icons.person, color: SpotterfyTheme.muted, size: radius)
        : null,
  );

  void _openChat(BuildContext context, SocialUser peer) {
    Navigator.push(context, swipeRoute(ChatScreen(peer: peer)));
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
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showJamSessionSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.groups, color: SpotterfyTheme.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: SpotterfyTheme.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        session.isPlaying ? 'Playing now' : 'Paused',
                        style: TextStyle(
                          color: SpotterfyTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: SpotterfyTheme.muted,
                  size: 20,
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
    final friends = await SocialService.instance.friendsOnce(uid);
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
              foregroundColor: Colors.black,
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
    final friends = await SocialService.instance.friendsOnce(uid);
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
              foregroundColor: SpotterfyTheme.text,
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
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: SpotterfyTheme.surface,
                    backgroundImage: f.photoUrl.isNotEmpty
                        ? NetworkImage(f.photoUrl)
                        : null,
                    child: f.photoUrl.isEmpty
                        ? Icon(
                            Icons.person,
                            color: SpotterfyTheme.muted,
                            size: 20,
                          )
                        : null,
                  ),
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
                  foregroundColor: Colors.black,
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
