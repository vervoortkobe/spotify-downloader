import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/jam_provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';

class JamScreen extends StatelessWidget {
  const JamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final jam = context.watch<JamProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF07110b),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Jam Sessions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF10b981)),
            onPressed: () => _createSession(context),
          ),
        ],
      ),
      body: jam.activeSessions.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.groups, color: Color(0xFFa1a1aa), size: 64),
                  const SizedBox(height: 16),
                  const Text('No active jam sessions', style: TextStyle(color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 8),
                  const Text('Create one or join an existing session',
                    style: TextStyle(color: Color(0xFFa1a1aa), fontSize: 14)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: jam.activeSessions.length,
              itemBuilder: (_, i) {
                final s = jam.activeSessions[i];
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0f1d17),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF1a3a2a)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48, height: 48,
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
                            Text(s.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            Text('${s.participants.length} listening',
                              style: const TextStyle(color: Color(0xFFa1a1aa), fontSize: 12)),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          final auth = context.read<AuthProvider>();
                          if (auth.user == null) return;
                          await jam.joinSession(auth.user!.uid, s.id);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10b981),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFFa1a1aa))),
          ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10b981), foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
