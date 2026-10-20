import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/providers/jam_provider.dart';
import 'package:spotterfy_app/providers/social_provider.dart';
import 'package:spotterfy_app/services/network_stats_service.dart';
import 'package:spotterfy_app/services/playlist_service.dart';
import 'package:spotterfy_app/services/social_service.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/jam_session_sheet.dart';
import 'package:spotterfy_app/widgets/profile_playlist_tile.dart';
import 'package:spotterfy_app/widgets/presence_dot.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/chat_screen.dart';
import 'package:spotterfy_app/screens/downloads_screen.dart';
import 'package:spotterfy_app/screens/playlist_detail_screen.dart';
import 'package:spotterfy_app/screens/settings_screen.dart';
import 'package:spotterfy_app/screens/user_playlists_screen.dart';
import 'package:spotterfy_app/screens/admin_screen.dart';

/// The profile previews this many playlists; the rest live behind "View all".
const _playlistPreviewCount = 5;

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
  Timer? _presenceRefreshTimer;

  String? get _targetUid => widget.uid;

  bool get _isOwnProfile =>
      _targetUid == null ||
      _targetUid == context.read<AuthProvider>().user?.uid;

  @override
  void initState() {
    super.initState();
    if (_targetUid != null) {
      _loadUser();
      _startPresenceRefresh();
    }
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.uid != oldWidget.uid && widget.uid != null) {
      _loadUser();
      _startPresenceRefresh();
    }
  }

  void _startPresenceRefresh() {
    _presenceRefreshTimer?.cancel();
    _presenceRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _presenceRefreshTimer?.cancel();
    super.dispose();
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
    final player = context.watch<PlayerProvider>();
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
              _sectionTitle(
                'Your Playlists',
                trailing: own.isEmpty ? null : '${own.length}',
              ),
              if (own.isEmpty)
                _emptyHint('You have not imported any playlists yet.')
              else
                ...own
                    .take(_playlistPreviewCount)
                    .map(
                      (playlist) => _playlistItem(
                        context,
                        playlist,
                        isActive: player.isActivePlaylist(playlist.id),
                      ),
                    ),
              if (own.length > _playlistPreviewCount)
                _viewAllPlaylistsButton(
                  context,
                  total: own.length,
                  onTap: () => Navigator.push(
                    context,
                    swipeRoute(
                      UserPlaylistsScreen(
                        title: 'Your Playlists',
                        playlists: own,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              _sectionTitle('Other'),
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
    final uid = _targetUid!;
    final isFriend = context.watch<SocialProvider>().isFriend(uid);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: isFriend
          ? FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('presence')
                .doc('current')
                .snapshots()
          : null,
      builder: (context, snapshot) {
        final presence = snapshot.data?.data() ?? const <String, dynamic>{};
        final online = isFriend &&
            presence['isOnline'] == true &&
            (presence['lastActiveAt'] as Timestamp?)?.toDate().isAfter(
                  DateTime.now().subtract(const Duration(minutes: 3)),
                ) ==
                true;
        final player = context.watch<PlayerProvider>();
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
                showOnlineDot: isFriend,
                isOnline: online,
              ),
              if (isFriend &&
                  online &&
                  (presence['currentListeningTo'] as String?)?.isNotEmpty ==
                      true) ...[
                const SizedBox(height: 12),
                _nowPlayingCard(presence),
              ],
              const SizedBox(height: 24),
              // Relationship actions: request -> accept -> message / jam.
              _socialActions(context),
              const SizedBox(height: 28),
              // A dedicated section, separate from your own profile's stats.
              _sectionTitle('Playlists', trailing: '${_theirPlaylists.length}'),
              const SizedBox(height: 8),
              if (_theirPlaylists.isEmpty)
                _emptyHint('This user has not shared any playlists yet.')
              else
                ..._theirPlaylists
                    .take(_playlistPreviewCount)
                    .map(
                      (playlist) => _playlistItem(
                        context,
                        playlist,
                        isActive: player.isActivePlaylist(playlist.id),
                      ),
                    ),
              if (_theirPlaylists.length > _playlistPreviewCount)
                _viewAllPlaylistsButton(
                  context,
                  total: _theirPlaylists.length,
                  onTap: () => Navigator.push(
                    context,
                    swipeRoute(
                      UserPlaylistsScreen(
                        title: 'Playlists',
                        playlists: _theirPlaylists,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
      },
    );
  }

  /// Shared look for the relationship actions: one pill shape, one height and
  /// accent-derived colours so the block reads as a set.
  ///
  /// It used to pair the theme's pill-shaped Message button with a default
  /// 12px-radius outline for Create jam, and pinned the accent label to
  /// hardcoded black - which the light palettes get wrong.
  ButtonStyle _socialButtonStyle({bool filled = false, bool quiet = false}) {
    const shape = StadiumBorder();
    const label = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
    if (filled) {
      return FilledButton.styleFrom(
        backgroundColor: SpotterfyTheme.primary,
        foregroundColor: SpotterfyTheme.onAccent,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: shape,
        textStyle: label,
        elevation: 0,
      );
    }
    return OutlinedButton.styleFrom(
      foregroundColor: quiet ? SpotterfyTheme.muted : SpotterfyTheme.primary,
      backgroundColor: quiet ? Colors.transparent : SpotterfyTheme.primaryBg,
      side: BorderSide(
        color: quiet
            ? SpotterfyTheme.overlay(0.18)
            : SpotterfyTheme.primary.withValues(alpha: 0.45),
      ),
      minimumSize: const Size(0, 46),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      shape: shape,
      textStyle: label,
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
                  child: FilledButton.icon(
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
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text(
                      'Accept',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: _socialButtonStyle(filled: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: req.isEmpty
                        ? null
                        : () => social.declineRequest(req.first),
                    style: _socialButtonStyle(quiet: true),
                    child: const Text(
                      'Decline',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

      case 'outgoing':
        // Reads as a state rather than an action: accent-wash fill, accent
        // border and a waiting glyph. Tapping it unsends, which is the whole
        // point of showing the state on the button itself rather than in a
        // separate card with a Cancel link.
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
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: const Text('Friend request sent'),
                style: _socialButtonStyle(),
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
                  child: FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      swipeRoute(ChatScreen(peer: peer)),
                    ),
                    icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                    label: const Text(
                      'Message',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: _socialButtonStyle(filled: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _createJamWith(peer),
                    icon: const Icon(Icons.graphic_eq_rounded, size: 18),
                    label: const Text(
                      'Create jam',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: _socialButtonStyle(),
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
              child: FilledButton.icon(
                onPressed: send,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Send friend request'),
                style: _socialButtonStyle(filled: true),
              ),
            ),
          ],
        );
    }
  }

  /// Starts a jam with [peer] and drops straight into the session sheet.
  ///
  /// The friend is invited up front: creating the session without them left a
  /// jam that only the creator was in, which is not a jam at all. Failures are
  /// surfaced instead of being swallowed by a "created" snackbar.
  Future<void> _createJamWith(SocialUser peer) async {
    final uid = _targetUid;
    final auth = context.read<AuthProvider>();
    final jam = context.read<JamProvider>();
    final playlistProv = context.read<PlaylistProvider>();
    if (uid == null || auth.user == null) return;

    if (jam.inJam) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('You are already in a jam')));
      return;
    }

    final tracks = playlistProv.currentPlaylist?.tracks ?? const [];
    try {
      await jam.createSession(
        auth.user!.uid,
        'Jam with ${peer.displayName}',
        tracks,
        invite: [peer.uid],
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    showJamSessionSheet(context);
  }

  // ------------------------------------------------------------ shared

  Widget _header({
    required String displayName,
    required String email,
    required String photoUrl,
    bool showOnlineDot = false,
    bool isOnline = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: SpotterfyTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SpotterfyTheme.overlay(0.08)),
      ),
      child: Column(
        children: [
          // Centred avatar over centred text, rather than a left-aligned row.
          // A profile reads as a portrait, and the centred stack keeps long
          // names from colliding with the edge on a narrow screen.
          Stack(
            clipBehavior: Clip.none,
            children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: SpotterfyTheme.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: SpotterfyTheme.primary.withValues(alpha: 0.45),
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
                  color: SpotterfyTheme.primary.withValues(alpha: 0.22),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: photoUrl.isEmpty
                ? Icon(Icons.person, color: SpotterfyTheme.muted, size: 34)
                : null,
          ),
          if (showOnlineDot)
            Positioned(
              right: 0,
              bottom: 0,
              child: PresenceDot(
                isOnline: isOnline,
                borderColor: SpotterfyTheme.surface,
              ),
            ),
            ],
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
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _nowPlayingCard(Map<String, dynamic> presence) {
    final title = presence['currentTrackTitle'] as String? ?? '';
    final artist = presence['currentTrackArtist'] as String? ?? '';
    final artwork = presence['currentTrackArtwork'] as String? ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SpotterfyTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpotterfyTheme.overlay(0.08)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: artwork.isEmpty
                ? Container(
                    width: 48,
                    height: 48,
                    color: SpotterfyTheme.overlay(0.12),
                    child: Icon(Icons.music_note, color: SpotterfyTheme.muted),
                  )
                : Image.network(
                    artwork,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 48,
                      height: 48,
                      color: SpotterfyTheme.overlay(0.12),
                      child: Icon(Icons.music_note, color: SpotterfyTheme.muted),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Listening to', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 11)),
                const SizedBox(height: 3),
                Text(title.isEmpty ? 'A track' : title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: SpotterfyTheme.text, fontSize: 14, fontWeight: FontWeight.w700)),
                if (artist.isNotEmpty)
                  Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.graphic_eq, color: SpotterfyTheme.primary, size: 20),
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
          if (trailing != null) _countBadge(trailing),
        ],
      ),
    );
  }

  /// A count shown as a number inside a small grey circle, so it reads as a
  /// badge instead of blending into the heading text.
  Widget _countBadge(String count) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: SpotterfyTheme.overlay(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SpotterfyTheme.overlay(0.06)),
      ),
      child: Text(
        count,
        style: TextStyle(
          color: SpotterfyTheme.text,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
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

  Widget _statItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: SpotterfyTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SpotterfyTheme.overlay(0.08)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: SpotterfyTheme.text,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: SpotterfyTheme.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _playlistItem(
    BuildContext context,
    PlaylistModel playlist, {
    required bool isActive,
  }) {
    return ProfilePlaylistTile(
      playlist: playlist,
      isActive: isActive,
      onTap: () => Navigator.push(
        context,
        swipeRoute(PlaylistDetailScreen(playlist: playlist)),
      ),
    );
  }

  /// Opens the full playlist list when the profile preview is capped at
  /// [_playlistPreviewCount] rows.
  Widget _viewAllPlaylistsButton(
    BuildContext context, {
    required int total,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: SpotterfyTheme.primary,
            backgroundColor: SpotterfyTheme.primaryBg,
            side: BorderSide(
              color: SpotterfyTheme.primary.withValues(alpha: 0.45),
            ),
            minimumSize: const Size(0, 44),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('View all $total playlists'),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: SpotterfyTheme.primary,
              ),
            ],
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
