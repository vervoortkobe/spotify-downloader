import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/profile_screen.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotterfyTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Discover',
          style: TextStyle(
            color: SpotterfyTheme.text,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Consumer<AuthProvider>(
            builder: (_, auth, _) => GestureDetector(
              onTap: () =>
                  Navigator.push(context, swipeRoute(const ProfileScreen())),
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: SpotterfyTheme.card, width: 1.5),
                ),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: SpotterfyTheme.surface,
                  backgroundImage: (auth.user?.photoUrl.isNotEmpty ?? false)
                      ? NetworkImage(auth.user!.photoUrl)
                      : null,
                  child: (auth.user?.photoUrl.isEmpty ?? true)
                      ? Icon(
                          Icons.person,
                          color: SpotterfyTheme.muted,
                          size: 18,
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your top genres',
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildGenreCard('Hip Hop', Colors.blue),
                  _buildGenreCard('Rock', Colors.red),
                  _buildGenreCard('Pop', Colors.purple),
                  _buildGenreCard('Electronic', Colors.orange),
                  _buildGenreCard('R&B', Colors.pink),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Recommended for you',
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 1.5,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _buildBrowseCategory(
                  'Daily Mix 1',
                  Icons.playlist_play,
                  Colors.green,
                ),
                _buildBrowseCategory(
                  'Discover Weekly',
                  Icons.auto_awesome,
                  Colors.blue,
                ),
                _buildBrowseCategory(
                  'New Music Friday',
                  Icons.new_releases,
                  Colors.red,
                ),
                _buildBrowseCategory(
                  'Release Radar',
                  Icons.radar,
                  Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Browse all',
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 2.5,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _buildBrowseCategory('Podcasts', Icons.mic, Colors.green),
                _buildBrowseCategory('Charts', Icons.bar_chart, Colors.blue),
                _buildBrowseCategory(
                  'Mood',
                  Icons.sentiment_satisfied,
                  Colors.orange,
                ),
                _buildBrowseCategory(
                  'Workout',
                  Icons.fitness_center,
                  Colors.purple,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenreCard(String genre, Color color) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              genre,
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrowseCategory(String title, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: SpotterfyTheme.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: SpotterfyTheme.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
