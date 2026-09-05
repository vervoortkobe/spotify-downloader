import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/screens/profile_screen.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotterfyTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Downloads', style: TextStyle(color: SpotterfyTheme.text, fontSize: 22, fontWeight: FontWeight.bold)),
        actions: [
          Consumer<AuthProvider>(builder: (_, auth, _) => GestureDetector(
            onTap: () => Navigator.push(context, swipeRoute(const ProfileScreen())),
            child: Container(margin: const EdgeInsets.only(right: 12), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: SpotterfyTheme.card, width: 1.5)), child: CircleAvatar(radius: 16, backgroundColor: SpotterfyTheme.surface, backgroundImage: (auth.user?.photoUrl.isNotEmpty ?? false) ? NetworkImage(auth.user!.photoUrl) : null, child: (auth.user?.photoUrl.isEmpty ?? true) ? const Icon(Icons.person, color: SpotterfyTheme.muted, size: 18) : null)),
          )),
        ],
      ),
      body: Consumer<PlaylistProvider>(builder: (_, prov, _) {
        final downloaded = prov.playlists.where((p) => p.tracks.isNotEmpty).toList();
        if (downloaded.isEmpty) {
          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.download_done, color: SpotterfyTheme.muted, size: 56),
              const SizedBox(height: 12),
              Text('No downloads yet', style: TextStyle(color: SpotterfyTheme.text, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('Downloaded tracks will appear here.\nSwipe right on a track to queue, left to play.', textAlign: TextAlign.center, style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 100),
          itemCount: downloaded.length,
          itemBuilder: (_, i) {
            final p = downloaded[i];
            return ListTile(
              leading: Container(width: 48, height: 48, decoration: BoxDecoration(color: SpotterfyTheme.surface, borderRadius: BorderRadius.circular(8), image: p.coverUrl.isNotEmpty ? DecorationImage(image: NetworkImage(p.coverUrl), fit: BoxFit.cover) : null), child: p.coverUrl.isEmpty ? Icon(Icons.music_note, color: SpotterfyTheme.muted) : null),
              title: Text(p.name, style: TextStyle(color: SpotterfyTheme.text, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${p.tracks.length} tracks • Offline available', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: Color(0xFFa1a1aa)),
            );
          },
        );
      }),
    );
  }
}
