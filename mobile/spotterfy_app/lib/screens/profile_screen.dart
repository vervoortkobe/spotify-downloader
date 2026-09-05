import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/login_screen.dart';
import 'package:spotterfy_app/screens/settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final playlistProv = context.watch<PlaylistProvider>();
    final user = auth.user;

    return Scaffold(
      backgroundColor: SpotterfyTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Profile',
          style: TextStyle(
            color: SpotterfyTheme.text,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile header
              Row(
                children: [
                  // Profile picture placeholder
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: SpotterfyTheme.surface,
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: SpotterfyTheme.primary.withValues(alpha: 0.3), width: 2),
                      image: (user?.photoUrl.isNotEmpty ?? false) ? DecorationImage(image: NetworkImage(user!.photoUrl), fit: BoxFit.cover) : null,
                      boxShadow: [BoxShadow(color: SpotterfyTheme.primary.withValues(alpha: 0.2), blurRadius: 12)],
                    ),
                    child: (user?.photoUrl.isEmpty ?? true)
                        ? Center(child: Icon(Icons.person, color: SpotterfyTheme.muted, size: 40))
                        : null,
                  ),
                  const SizedBox(width: 20),
                  // Profile info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? 'User',
                          style: TextStyle(
                            color: SpotterfyTheme.text,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.email ?? '',
                          style: TextStyle(
                            color: SpotterfyTheme.muted,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Stats section
              Text(
                'Your Stats',
                style: TextStyle(
                  color: SpotterfyTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _statItem('Playlists', '${playlistProv.playlists.length}'),
                  _statItem('Total Tracks', _calculateTotalTracks(playlistProv.playlists)),
                ],
              ),
              const SizedBox(height: 32),

              // Your Playlists section
              Text(
                'Your Playlists',
                style: TextStyle(
                  color: SpotterfyTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              // List of user's playlists
              ...playlistProv.playlists
                  .where((p) => p.creatorUid == user?.uid)
                  .map((playlist) => _playlistItem(context, playlist)),

              const SizedBox(height: 32),

              // Settings button
              _actionButton(
                context,
                icon: Icons.settings,
                title: 'Settings',
                onTap: () {
                  Navigator.push(
                    context,
                    swipeRoute(const SettingsScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),

              // Logout button
              _actionButton(
                context,
                icon: Icons.logout,
                title: 'Sign Out',
                isDestructive: true,
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: SpotterfyTheme.surface,
                      title: Text('Sign Out', style: TextStyle(color: SpotterfyTheme.text)),
                      content: Text('Are you sure?', style: TextStyle(color: SpotterfyTheme.muted)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text('Cancel', style: TextStyle(color: SpotterfyTheme.muted)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text('Sign Out', style: TextStyle(color: SpotterfyTheme.primary)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await auth.signOut();
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _calculateTotalTracks(List<dynamic> playlists) {
    int total = 0;
    for (final p in playlists) {
      total += (p.tracks?.length ?? 0) as int;
    }
    return '$total';
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
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: SpotterfyTheme.muted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _playlistItem(BuildContext context, dynamic playlist) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: SpotterfyTheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: playlist.coverUrl.isNotEmpty
            ? Image.network(playlist.coverUrl, fit: BoxFit.cover)
            : Icon(Icons.music_note, color: SpotterfyTheme.muted, size: 24),
      ),
      title: Text(
        playlist.name,
        style: TextStyle(
          color: SpotterfyTheme.text,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${playlist.tracks?.length ?? 0} tracks',
        style: TextStyle(
          color: SpotterfyTheme.muted,
          fontSize: 12,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFFa1a1aa)),
      onTap: () {
        // TODO: Navigate to playlist detail
      },
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
