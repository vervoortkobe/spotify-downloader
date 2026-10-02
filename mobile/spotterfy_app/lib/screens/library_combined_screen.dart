import 'package:flutter/material.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/screens/library_screen.dart';
import 'package:spotterfy_app/screens/storage_screen.dart';

class LibraryCombinedScreen extends StatefulWidget {
  const LibraryCombinedScreen({super.key});

  @override
  State<LibraryCombinedScreen> createState() => _LibraryCombinedScreenState();
}

class _LibraryCombinedScreenState extends State<LibraryCombinedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: SpotterfyTheme.primary,
          indicatorWeight: 3,
          labelColor: SpotterfyTheme.text,
          unselectedLabelColor: SpotterfyTheme.muted,
          labelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.normal,
          ),
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'Playlists'),
            Tab(text: 'Local Files'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [LibraryScreen(), StorageScreen()],
      ),
    );
  }
}
