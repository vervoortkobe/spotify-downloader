import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/jam_provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/base_page.dart';

class JamScreen extends StatefulWidget {
  const JamScreen({super.key});

  @override
  State<JamScreen> createState() => _JamScreenState();
}

class _JamScreenState extends State<JamScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() => _query = _searchController.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jam = context.watch<JamProvider>();
    var sessions = jam.activeSessions;
    if (_query.isNotEmpty) {
      sessions = sessions.where((s) => s.name.toLowerCase().contains(_query)).toList();
    }
    return BasePageScaffold(
      backgroundColor: const Color(0xFF07110b),
      searchController: _searchController,
      searchHint: 'Search chats',
      query: _query,
      action: IconButton(
        icon: Icon(Icons.group_add, color: SpotterfyTheme.muted, size: 20),
        onPressed: () => _createSession(context),
        tooltip: 'New jam',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
      body: sessions.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.groups, color: Color(0xFFa1a1aa), size: 64),
                  const SizedBox(height: 16),
                  Text(_query.isNotEmpty ? 'No chats for "$_query"' : 'No active jam sessions', style: const TextStyle(color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 8),
                  const Text('Create one or join an existing session', style: TextStyle(color: Color(0xFFa1a1aa), fontSize: 14)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: sessions.length,
              itemBuilder: (_, i) {
                final s = sessions[i];
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF0f1d17), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF1a3a2a))),
                  child: Row(
                    children: [
                      Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFF1a3a2a), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.groups, color: Color(0xFF10b981))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)), Text('${s.participants.length} listening', style: const TextStyle(color: Color(0xFFa1a1aa), fontSize: 12))])),
                      ElevatedButton(
                        onPressed: () async {
                          final auth = context.read<AuthProvider>();
                          if (auth.user == null) return;
                          await jam.joinSession(auth.user!.uid, s.id);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10b981), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: const Text('Join'),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _createSession(BuildContext context) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0f1d17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Create Jam Session', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Session name',
            hintStyle: const TextStyle(color: Color(0xFFa1a1aa)),
            filled: true,
            fillColor: const Color(0xFF0a1410),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFFa1a1aa)))),
          ElevatedButton(
            onPressed: () async {
              final auth = context.read<AuthProvider>();
              final jam = context.read<JamProvider>();
              final playlistProv = context.read<PlaylistProvider>();
              if (auth.user == null || nameController.text.isEmpty) return;
              final tracks = playlistProv.currentPlaylist?.tracks ?? [];
              await jam.createSession(auth.user!.uid, nameController.text, tracks);
              if (context.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10b981), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}