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
import 'package:spotterfy_app/screens/playlist_detail_screen.dart';
import 'package:spotterfy_app/screens/settings_screen.dart';
import 'package:spotterfy_app/screens/admin_screen.dart';

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

    // "Your playlists" means playlists this account owns. Filtering here rather
    // than showing the whole provider list is what the heading promises.
    final own = playlistProv.playlists
        .where((p) => p.creatorUid == user?.uid)
        .toList();

    return AppGradientScaffold(
      title: 'Profile',
      body: SingleChildScrollView(
        // Bottom inset clears the mini player, which MainScreen draws over this
        // page rather than inside it.
        padding: const EdgeInsets.only(bottom: 140),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(
                displayName: user?.displayName ?? 'User',
                email: user?.email ?? '',
                photoUrl: user?.photoUrl ?? '',
              ),
              const SizedBox(height: 24),
              _sectionTitle('Your Stats'),
              Row(
                children: [
                  Expanded(child: _statItem('Playlists', '${own.length}')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _statItem(
                      'Total Tracks',
                      _calculateTotalTracks(own).toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _sectionTitle('Connection'),
              _connectionTile(context),
              const SizedBox(height: 24),
              _sectionTitle(
                'Your Playlists',
                trailing: own.isEmpty ? null : '${own.length}',
              ),
              if (own.isEmpty)
                _emptyHint('You have not imported any playlists yet.')
              else
                ...own.map((playlist) => _playlistItem(context, playlist)),
              const SizedBox(height: 16),
              _sectionTitle('More'),
              _actionButton(
                context,
                icon: Icons.download_done,
                title: 'Downloads',
                onTap: () {
                  Navigator.push(context, swipeRoute(const DownloadsScreen()));
                },
              ),
              const SizedBox(height: 8),
              _actionButton(
                context,
                icon: Icons.settings,
                title: 'Settings',
                onTap: () {
                  Navigator.push(context, swipeRoute(const SettingsScreen()));
                },
              ),
              // Admin-only, and only for the signed-in user's own profile.
              // Another member's profile has no business offering moderation
              // tools, so the uid check is not just `auth.isAdmin`.
              if (auth.isAdmin && _targetUid == null) ...[
                const SizedBox(height: 8),
                _actionButton(
                  context,
                  icon: Icons.shield,
                  title: 'Admin Panel',
                  onTap: () {
                    Navigator.push(context, swipeRoute(const AdminScreen()));
                  },
                ),
              ],
              const SizedBox(height: 8),
              _actionButton(
                context,
                icon: Icons.logout,
                title: 'Sign Out',
                isDestructive: true,
                onTap: () => _confirmSignOut(context),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final social = context.read<SocialProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotterfyTheme.surface,
        title: Text('Sign Out', style: TextStyle(color: SpotterfyTheme.text)),
        content: Text(
          'Are you sure?',
          style: TextStyle(color: SpotterfyTheme.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: SpotterfyTheme.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Sign Out',
              style: TextStyle(color: SpotterfyTheme.primary),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await NetworkStatsService.instance?.setUserId(null);
    // Tear the Firestore listeners down *before* revoking the token. They are
    // all gated on `request.auth != null`, so leaving them attached across a
    // sign-out makes every one of them answer PERMISSION_DENIED.
    // Captured before the await above so no BuildContext crosses the gap.
    social.syncUid(null);
    await auth.signOut();
    // No navigation here. The splash screen is the auth gate - it watches
    // AuthProvider and swaps MainScreen for LoginScreen in place. Navigating
    // instead reparented MainScreen's TabNavigators, whose static per-tab
    // GlobalKeys then duplicated and crashed the frame.
  }

  // ------------------------------------------------------------- other

  Widget _buildOtherProfile(BuildContext context) {
    if (_loading) {
      return AppGradientScaffold(
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
        // Reads as "pressed": empty fill, accent border and accent text, so it
        // looks like a toggle that is currently on. Tapping it unsends, which is
        // the whole point of showing the state on the button itself rather than in
        // a separate card with a Cancel link.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Friendship'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => social.declineRequest(
                  social.requests.firstWhere(
                    (r) => r.otherUid == uid && r.isPending,
                  ),
                ),
                icon: const Icon(Icons.hourglass_top, size: 18),
                label: const Text('Friend request sent'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: SpotterfyTheme.primary,
                  side: BorderSide(color: SpotterfyTheme.primary),
                ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SpotterfyTheme.primary.withValues(alpha: 0.16),
            SpotterfyTheme.surface.withValues(alpha: 0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: SpotterfyTheme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        children: [
          // Centred avatar over centred text, rather than a left-aligned row.
          // A profile reads as a portrait, and the centred stack keeps long
          // names from colliding with the edge on a narrow screen.
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: SpotterfyTheme.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: SpotterfyTheme.primary.withValues(alpha: 0.45),
                width: 2.5,
              ),
              image: photoUrl.isNotEmpty
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(photoUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: SpotterfyTheme.primary.withValues(alpha: 0.22),
                  blurRadius: 18,
                ),
              ],
            ),
            child: photoUrl.isEmpty
                ? Icon(Icons.person, color: SpotterfyTheme.muted, size: 44)
                : null,
          ),
          const SizedBox(height: 14),
          Text(
            displayName,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: SpotterfyTheme.text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              email,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: SpotterfyTheme.muted, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  /// Section heading with an optional trailing count, so "Your playlists" can
  /// report its size without the caller composing a string.
  Widget _sectionTitle(String text, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _emptyHint(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      text,
      style: TextStyle(color: SpotterfyTheme.muted, fontSize: 13),
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
          Divider(color: SpotterfyTheme.card, height: 12),
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
              style: TextStyle(
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
            style: TextStyle(
              color: SpotterfyTheme.text,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _playlistItem(BuildContext context, PlaylistModel playlist) {
    // A rounded card with real artwork rather than a bare ListTile: the rows sit
    // directly on the page background, so grouping them gives the section an
    // edge and makes the artwork read as the thing you are picking.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: SpotterfyTheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(
            context,
            swipeRoute(PlaylistDetailScreen(playlist: playlist)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: playlist.coverUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: playlist.coverUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                Container(color: SpotterfyTheme.card),
                            errorWidget: (_, _, _) => Container(
                              color: SpotterfyTheme.card,
                              child: Icon(
                                Icons.music_note,
                                color: SpotterfyTheme.muted,
                                size: 22,
                              ),
                            ),
                          )
                        : Container(
                            color: SpotterfyTheme.card,
                            child: Icon(
                              Icons.music_note,
                              color: SpotterfyTheme.muted,
                              size: 22,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: SpotterfyTheme.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${playlist.tracks.length} tracks  •  ${playlist.sourceLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: SpotterfyTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: SpotterfyTheme.mutedDark),
              ],
            ),
          ),
        ),
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
