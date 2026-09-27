import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
      body: ListView(
        padding: const EdgeInsets.only(bottom: 110),
        children: [
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
                                  ? const Icon(
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
                              style: const TextStyle(
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
                  style: const TextStyle(color: Colors.white, fontSize: 16),
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
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (badge > 0) ...[
            const SizedBox(width: 8),
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
          const Spacer(),
          ?trailing,
          if (onTap != null && badge > 0)
            TextButton(
              onPressed: onTap,
              child: const Text(
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
        color: n.read ? const Color(0xFF0f1d17) : const Color(0xFF12241c),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: n.read
              ? const Color(0xFF1a3a2a)
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  n.body,
                  style: const TextStyle(
                    color: Color(0xFFa1a1aa),
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
                  icon: const Icon(
                    Icons.check,
                    color: SpotterfyTheme.primary,
                    size: 20,
                  ),
                  tooltip: 'Accept',
                  onPressed: () => _acceptRequest(context, n.fromUid),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Color(0xFFa1a1aa),
                    size: 20,
                  ),
                  tooltip: 'Decline',
                  onPressed: () => _declineRequest(context, n.fromUid),
                ),
              ],
            )
          else
            IconButton(
              icon: const Icon(
                Icons.chevron_right,
                color: Color(0xFFa1a1aa),
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
        color: const Color(0xFF0f1d17),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1a3a2a)),
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  c.lastMessage,
                  style: const TextStyle(
                    color: Color(0xFFa1a1aa),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFFa1a1aa), size: 20),
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
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(
              Icons.music_note,
              color: SpotterfyTheme.primary,
              size: 20,
            ),
            tooltip: 'Create a jam',
            onPressed: () => _createSession(context, withFriend: f),
          ),
          IconButton(
            icon: const Icon(
              Icons.chat_bubble_outline,
              color: Colors.white,
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
        color: const Color(0xFF0f1d17),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1a3a2a)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF1a3a2a),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.groups, color: Color(0xFF10b981)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${s.participants.length} listening',
                  style: const TextStyle(
                    color: Color(0xFFa1a1aa),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              if (auth.user == null) return;
              await jam.joinSession(auth.user!.uid, s.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10b981),
              foregroundColor: Colors.white,
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

  /// Creates a jam. When launched from a friend row the session is named for
  /// that friend and they're invited immediately; from the app bar it opens a
  /// picker of friends.
  void _createSession(BuildContext context, {SocialUser? withFriend}) {
    if (withFriend != null) {
      _showJamDialog(
        context,
        initialName: 'Jam with ${withFriend.displayName}',
      );
      return;
    }
    _showFriendPicker(context);
  }

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

    final picked = await showModalBottomSheet<SocialUser>(
      context: context,
      backgroundColor: SpotterfyTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text(
                'Create a jam with',
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
                      style: const TextStyle(color: SpotterfyTheme.text),
                    ),
                    trailing: const Icon(
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
    if (picked != null && context.mounted) {
      _showJamDialog(context, initialName: 'Jam with ${picked.displayName}');
    }
  }

  void _showJamDialog(BuildContext context, {String initialName = ''}) {
    final nameController = TextEditingController(text: initialName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0f1d17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Create Jam Session',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Session name',
            hintStyle: const TextStyle(color: Color(0xFFa1a1aa)),
            filled: true,
            fillColor: const Color(0xFF0a1410),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFFa1a1aa)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final auth = context.read<AuthProvider>();
              final jam = context.read<JamProvider>();
              final playlistProv = context.read<PlaylistProvider>();
              final name = nameController.text.trim();
              if (auth.user == null || name.isEmpty) return;
              final tracks = playlistProv.currentPlaylist?.tracks ?? [];
              await jam.createSession(auth.user!.uid, name, tracks);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10b981),
              foregroundColor: Colors.white,
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
