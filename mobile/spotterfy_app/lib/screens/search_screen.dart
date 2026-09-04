import 'package:flutter/material.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/screens/profile_screen.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotterfyTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: SpotterfyTheme.card,
            borderRadius: BorderRadius.circular(20),
          ),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search, color: SpotterfyTheme.muted, size: 20),
              hintText: 'Artists, songs, or podcasts',
              hintStyle: TextStyle(color: SpotterfyTheme.muted, fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            style: TextStyle(color: SpotterfyTheme.text, fontSize: 14),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person, size: 26),
            color: SpotterfyTheme.muted,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
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
              'Browse all',
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 2.5,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _buildBrowseCategory('Podcasts', Icons.mic, Colors.green),
                  _buildBrowseCategory('New Releases', Icons.new_releases, Colors.red),
                  _buildBrowseCategory('Charts', Icons.bar_chart, Colors.blue),
                  _buildBrowseCategory('Mood', Icons.sentiment_satisfied, Colors.orange),
                  _buildBrowseCategory('Workout', Icons.fitness_center, Colors.purple),
                  _buildBrowseCategory('Focus', Icons.psychology, Colors.indigo),
                ],
              ),
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
        borderRadius: BorderRadius.circular(8),
        image: const DecorationImage(
          image: AssetImage('logo/spotterfy_black_bg.png'),
          fit: BoxFit.cover,
          opacity: 0.1,
        ),
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
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: SpotterfyTheme.text,
                  fontSize: 16,
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
