import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/playlist_card.dart';
import 'playlist_detail_screen.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/profile_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final playlistProv = context.watch<PlaylistProvider>();
    
    return Scaffold(
      backgroundColor: SpotterfyTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Your Library',
          style: TextStyle(
            color: SpotterfyTheme.text,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: SpotterfyTheme.text, size: 24),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.add, color: SpotterfyTheme.text, size: 24),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.person, size: 26),
            color: SpotterfyTheme.muted,
            onPressed: () => Navigator.push(
              context,
              swipeRoute(const ProfileScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Library tabs
          Container(
            color: SpotterfyTheme.surface,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildLibraryTab('Playlists', true),
                  _buildLibraryTab('Artists', false),
                  _buildLibraryTab('Albums', false),
                  _buildLibraryTab('Podcasts', false),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Sort & Filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: SpotterfyTheme.card,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.sort, color: SpotterfyTheme.muted, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Recents',
                        style: TextStyle(
                          color: SpotterfyTheme.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, color: SpotterfyTheme.muted, size: 16),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.filter_list, color: SpotterfyTheme.text, size: 20),
                  onPressed: () {},
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Grid of playlists
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.4,
                ),
                itemCount: playlistProv.playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlistProv.playlists[index];
                  return PlaylistCard(
                    playlist: playlist,
                    onTap: () => Navigator.push(
                      context,
                      swipeRoute(PlaylistDetailScreen(playlist: playlist)),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryTab(String text, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Text(
            text,
            style: TextStyle(
              color: isSelected ? SpotterfyTheme.text : SpotterfyTheme.muted,
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 4),
          if (isSelected)
            Container(
              width: 24,
              height: 2,
              color: SpotterfyTheme.primary,
            ),
        ],
      ),
    );
  }
}
