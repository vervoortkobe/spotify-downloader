import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/providers/status_provider.dart';
import 'package:spotterfy_app/providers/jam_provider.dart';
import 'package:spotterfy_app/providers/social_provider.dart';
import 'package:spotterfy_app/services/network_stats_service.dart';
import 'package:spotterfy_app/services/playlist_service.dart';
import 'package:spotterfy_app/services/social_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/chat_screen.dart';
import 'package:spotterfy_app/screens/downloads_screen.dart';
import 'package:spotterfy_app/screens/login_screen.dart';
import 'package:spotterfy_app/screens/playlist_detail_screen.dart';
import 'package:spotterfy_app/screens/settings_screen.dart';

/// A user's profile.
///
/// With no [uid] this is your own profile (stats, connection, playlists,
/// settings, sign out). Passing someone else's [uid] shows their public
/// profile and a dedicated "Playlists" section listing everything they created,
/// which is what the profile button on a shared playlist opens.
class ProfileScreen extends StatefulWidget {
  final String? uid;

  const ProfileScreen({super.key, this.uid});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _service = PlaylistService();

  Map<String, String>? _profile;
  List<PlaylistModel> _theirPlaylists = const [];
  bool _loading = false;
  bool _loadFailed = false;

  String? get _targetUid => widget.uid;

  bool get _isOwnProfile =>
      _targetUid == null ||
      _targetUid == context.read<AuthProvider>().user?.uid;

  @override
  void initState() {
    super.initState();
    if (_targetUid != null) {
      _loadUser();
    }
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.uid != oldWidget.uid && widget.uid != null) {
      _loadUser();
    }
  }

  /// Loads the other user's profile fields and their playlists.
  Future<void> _loadUser() async {
    final uid = _targetUid;
    if (uid == null) return;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final profile = await _service.getUserProfile(uid);
    List<PlaylistModel> playlists = const [];
    if (profile != null) {
      try {
        playlists = await _service.getUserPlaylists(uid);
      } catch (e) {
        // A failure here shouldn't blank the whole profile; the header is still
        // worth showing and the section can report its own empty state.
        playlists = const [];
      }
    }
    if (!mounted || uid != _targetUid) return;
    setState(() {
      _profile = profile;
      _theirPlaylists = playlists;
      _loading = false;
      _loadFailed = profile == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _isOwnProfile
        ? _buildOwnProfile(context)
        : _buildOtherProfile(context);
  }

  // ---------------------------------------------------------------- own

  Widget _buildOwnProfile(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final playlistProv = context.watch<PlaylistProvider>();
    final user = auth.user;

    return AppGradientScaffold(
      title: 'Profile',
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(
                displayName: user?.displayName ?? 'User',
                email: user?.email ?? '',
                photoUrl: user?.photoUrl ?? '',
              ),
              const SizedBox(height: 28),
              _sectionTitle('Your Stats'),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _statItem('Playlists', '${playlistProv.playlists.length}'),
                  _statItem(
                    'Total Tracks',
                    _calculateTotalTracks(playlistProv.playlists),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              _sectionTitle('Connection'),
              const SizedBox(height: 14),
              _connectionTile(context),
              const SizedBox(height: 28),
              _sectionTitle('Your Playlists'),
              const SizedBox(height: 8),
              if (playlistProv.playlists.isEmpty)
                _emptyHint('You have not imported any playlists yet.')
              else
                ...playlistProv.playlists
                    .where((p) => p.creatorUid == user?.uid)
                    .map((playlist) => _playlistItem(context, playlist)),
              const SizedBox(height: 28),
              _actionButton(
                context,
                icon: Icons.download_done,
                title: 'Downloads',
                onTap: () {
                  Navigator.push(context, swipeRoute(const DownloadsScreen()));
                },
              ),
              const SizedBox(height: 12),
              _actionButton(
                context,
                icon: Icons.settings,
                title: 'Settings',
                onTap: () {
                  Navigator.push(context, swipeRoute(const SettingsScreen()));
                },
              ),
              const SizedBox(height: 12),
              _actionButton(
                context,
                icon: Icons.logout,
                title: 'Sign Out',
                isDestructive: true,
                onTap: () => _confirmSignOut(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotterfyTheme.surface,
        title: const Text(
          'Sign Out',
          style: TextStyle(color: SpotterfyTheme.text),
        ),
        content: const Text(
          'Are you sure?',
          style: TextStyle(color: SpotterfyTheme.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: SpotterfyTheme.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sign Out',
              style: TextStyle(color: SpotterfyTheme.primary),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await NetworkStatsService.instance?.setUserId(null);
    await auth.signOut();
    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  // ------------------------------------------------------------- other

  Widget _buildOtherProfile(BuildContext context) {
    if (_loading) {
      return const AppGradientScaffold(
        body: Center(
          child: CircularProgressIndicator(color: SpotterfyTheme.primary),
        ),
      );
    }
    if (_loadFailed) {
      return AppGradientScaffold(
        title: 'Profile',
        body: Center(
          child: Text(
            'Could not load this profile',
            style: TextStyle(color: SpotterfyTheme.muted),
          ),
        ),
      );
    }

    final p = _profile;
    return AppGradientScaffold(
      title: p?['displayName'] ?? 'Profile',
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(
                displayName: p?['displayName'] ?? 'User',
                email: p?['email'] ?? '',
                photoUrl: p?['photoUrl'] ?? '',
              ),
              const SizedBox(height: 24),
              // Relationship actions: request -> accept -> message / jam.
              _socialActions(context),
              const SizedBox(height: 28),
              // A dedicated section, separate from your own profile's stats.
              _sectionTitle('Playlists (${_theirPlaylists.length})'),
              const SizedBox(height: 8),
              if (_theirPlaylists.isEmpty)
                _emptyHint('This user has not shared any playlists yet.')
              else
                ..._theirPlaylists.map(
                  (playlist) => _playlistItem(context, playlist),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Friend-request / message / jam controls for the viewed user.
  ///
  /// Renders whatever the current relationship is: nothing sent yet, an
  /// incoming request waiting on them, one we sent and are waiting on, or
  /// already friends (in which case messaging and a shared jam unlock).
  Widget _socialActions(BuildContext context) {
    final uid = _targetUid;
    if (uid == null) return const SizedBox.shrink();

    final social = context.watch<SocialProvider>();
    final auth = context.read<AuthProvider>();
    final state = social.relationshipWith(uid);
    final peer = SocialUser(
      uid: uid,
      displayName: _profile?['displayName'] ?? 'User',
      photoUrl: _profile?['photoUrl'] ?? '',
    );
    final myName = auth.user?.displayName ?? 'Me';
    final myPhoto = auth.user?.photoUrl ?? '';

    Future<void> send() async {
      await social.sendFriendRequest(
        myName: myName,
        myPhoto: myPhoto,
        other: peer,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Friend request sent to ${peer.displayName}')),
      );
    }

    switch (state) {
      case 'incoming':
        final req = social.requests.where(
          (r) => r.otherUid == uid && r.isPending,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('They want to be friends'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: req.isEmpty
                        ? null
                        : () async {
                            final r = req.first;
                            await social.acceptRequest(
                              myName: myName,
                              myPhoto: myPhoto,
                              request: r,
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${r.otherName} is now a friend'),
                              ),
                            );
                          },
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('Accept request'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SpotterfyTheme.primary,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: req.isEmpty
                      ? null
                      : () => social.declineRequest(req.first),
                  child: const Text('Decline'),
                ),
              ],
            ),
          ],
        );

      case 'outgoing':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Friend request'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: SpotterfyTheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.hourglass_top,
                    color: SpotterfyTheme.muted,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Waiting for them to accept',
                      style: TextStyle(
                        color: SpotterfyTheme.text,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => social.declineRequest(
                      social.requests.firstWhere(
                        (r) => r.otherUid == uid && r.isPending,
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: SpotterfyTheme.muted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

      case 'friends':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Friends'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      swipeRoute(ChatScreen(peer: peer)),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Message'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SpotterfyTheme.primary,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _createJamWith(peer),
                    icon: const Icon(Icons.groups, size: 18),
                    label: const Text('Create jam'),
                  ),
                ),
              ],
            ),
          ],
        );

      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Friendship'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: send,
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Send friend request'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SpotterfyTheme.primary,
                  foregroundColor: Colors.black,
                ),
              ),
            ),
          ],
        );
    }
  }

  void _createJamWith(SocialUser peer) {
    final uid = _targetUid;
    final auth = context.read<AuthProvider>();
    final jam = context.read<JamProvider>();
    final playlistProv = context.read<PlaylistProvider>();
    if (uid == null || auth.user == null) return;
    final tracks = playlistProv.currentPlaylist?.tracks ?? const [];
    jam.createSession(auth.user!.uid, 'Jam with ${peer.displayName}', tracks);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Jam with ${peer.displayName} created')),
    );
  }

  // ------------------------------------------------------------ shared

  Widget _header({
    required String displayName,
    required String email,
    required String photoUrl,
  }) {
    return Row(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: SpotterfyTheme.surface,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
              color: SpotterfyTheme.primary.withValues(alpha: 0.3),
              width: 2,
            ),
            image: photoUrl.isNotEmpty
                ? DecorationImage(
                    image: CachedNetworkImageProvider(photoUrl),
                    fit: BoxFit.cover,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: SpotterfyTheme.primary.withValues(alpha: 0.2),
                blurRadius: 12,
              ),
            ],
          ),
          child: photoUrl.isEmpty
              ? const Icon(Icons.person, color: SpotterfyTheme.muted, size: 40)
              : null,
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: const TextStyle(
                  color: SpotterfyTheme.text,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  email,
                  style: const TextStyle(
                    color: SpotterfyTheme.muted,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(
      color: SpotterfyTheme.text,
      fontSize: 18,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _emptyHint(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      text,
      style: const TextStyle(color: SpotterfyTheme.muted, fontSize: 13),
    ),
  );

  String _calculateTotalTracks(List<PlaylistModel> playlists) {
    var total = 0;
    for (final p in playlists) {
      total += p.tracks.length;
    }
    return '$total';
  }

  Widget _connectionTile(BuildContext context) {
    final net = context.watch<NetworkStatsService>();
    final warp = context.watch<StatusProvider>().warpConnected;
    final connTitle = !net.online
        ? 'Internet — Offline'
        : (net.isCellular ? 'Internet — Mobile data' : 'Internet — Wi-Fi');
    final connIcon = !net.online
        ? Icons.signal_wifi_off
        : (net.isCellular ? Icons.signal_cellular_alt : Icons.wifi);
    final connColor = !net.online ? Colors.red : SpotterfyTheme.primary;
    final warpTitle = warp == null
        ? 'WARP — Checking…'
        : (warp ? 'WARP — Connected' : 'WARP — Off');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: SpotterfyTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _connectionRow(icon: connIcon, title: connTitle, color: connColor),
          const Divider(color: SpotterfyTheme.card, height: 12),
          _connectionRow(
            icon: warp == true ? Icons.shield : Icons.shield_outlined,
            title: warpTitle,
            color: warp == true ? SpotterfyTheme.primary : SpotterfyTheme.muted,
          ),
        ],
      ),
    );
  }

  Widget _connectionRow({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: SpotterfyTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: SpotterfyTheme.text,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: SpotterfyTheme.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _playlistItem(BuildContext context, PlaylistModel playlist) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: SpotterfyTheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: playlist.coverUrl.isNotEmpty
            ? CachedNetworkImage(imageUrl: playlist.coverUrl, fit: BoxFit.cover)
            : const Icon(
                Icons.music_note,
                color: SpotterfyTheme.muted,
                size: 24,
              ),
      ),
      title: Text(
        playlist.name,
        style: const TextStyle(
          color: SpotterfyTheme.text,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${playlist.tracks.length} tracks • ${playlist.sourceLabel}',
        style: const TextStyle(color: SpotterfyTheme.muted, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFFa1a1aa)),
      onTap: () => Navigator.push(
        context,
        swipeRoute(PlaylistDetailScreen(playlist: playlist)),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    bool isDestructive = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: SpotterfyTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: isDestructive
              ? Border.all(color: Colors.red.withValues(alpha: 0.5))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDestructive ? Colors.red : SpotterfyTheme.muted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                color: isDestructive ? Colors.red : SpotterfyTheme.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (isDestructive)
              const Icon(Icons.chevron_right, color: Colors.red, size: 20),
          ],
        ),
      ),
    );
  }
}
