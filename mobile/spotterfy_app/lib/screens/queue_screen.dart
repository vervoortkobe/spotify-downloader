// ignore_for_file: unnecessary_underscores
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/screens/profile_screen.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotterfyTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 48,
        leading: Consumer<AuthProvider>(builder: (_, auth, __) => GestureDetector(
          onTap: () => Navigator.push(context, swipeRoute(const ProfileScreen())),
          child: Padding(padding: const EdgeInsets.only(left: 10), child: Center(child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: SpotterfyTheme.card, width: 1.4), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 5)]), child: CircleAvatar(radius: 14, backgroundColor: SpotterfyTheme.surface, backgroundImage: (auth.user?.photoUrl.isNotEmpty ?? false) ? NetworkImage(auth.user!.photoUrl) : null, child: (auth.user?.photoUrl.isEmpty ?? true) ? Icon(Icons.person, color: SpotterfyTheme.muted, size: 16) : null))),
        ))),
        titleSpacing: 8,
        title: Text('Queue', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
      ),
      body: Consumer<PlayerProvider>(builder: (context, player, _) {
        final q = player.queue;
        if (q.isEmpty) {
          return Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.queue_music, color: SpotterfyTheme.muted, size: 56),
              const SizedBox(height: 12),
              Text('Queue is empty', style: TextStyle(color: SpotterfyTheme.text, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('Play a playlist or swipe left on a track\nto add it to the queue, right to play.', textAlign: TextAlign.center, style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
            ]),
          );
        }
        return ReorderableListView.builder(
          padding: const EdgeInsets.only(bottom: 140, top: 8),
          itemCount: q.length,
          onReorderItem: (oldIndex, newIndex) {
            final item = q.removeAt(oldIndex);
            q.insert(newIndex, item);
            // Adjust currentIndex to stay on same track after reorder
            var cur = player.currentIndex;
            if (oldIndex == cur) {
              cur = newIndex;
            } else if (oldIndex < cur && newIndex >= cur) {
              cur -= 1;
            } else if (oldIndex > cur && newIndex <= cur) {
              cur += 1;
            }
            player.setQueue(q, startIndex: cur);
            HapticFeedback.lightImpact();
          },
          itemBuilder: (_, i) {
            final t = q[i];
            final isCurrent = i == player.currentIndex;
            final isPlaying = isCurrent && player.isPlaying;
            return Dismissible(
              key: ValueKey('q-${t.id}-$i'),
              direction: DismissDirection.endToStart,
              background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), color: const Color(0xFFef4444), child: const Icon(Icons.delete, color: Colors.white)),
              onDismissed: (_) {
                player.removeFromQueue(i);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Removed "${t.title}"'), backgroundColor: SpotterfyTheme.surface));
              },
              child: ListTile(
                key: ValueKey('tile-$i'),
                leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: t.cover.isNotEmpty ? Image.network(t.cover, width: 48, height: 48, fit: BoxFit.cover) : Container(width: 48, height: 48, color: SpotterfyTheme.surface, child: Icon(Icons.music_note, color: SpotterfyTheme.muted))),
                title: Text(t.title, style: TextStyle(color: isCurrent ? SpotterfyTheme.primary : SpotterfyTheme.text, fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(t.artists, style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isPlaying) Container(width: 18, height: 18, decoration: BoxDecoration(color: SpotterfyTheme.primary, shape: BoxShape.circle), child: const Icon(Icons.equalizer, color: Colors.white, size: 12)),
                  const SizedBox(width: 4),
                  Icon(Icons.drag_handle, color: SpotterfyTheme.muted, size: 18),
                ]),
                selected: isCurrent,
                selectedTileColor: SpotterfyTheme.primary.withValues(alpha: 0.08),
                onTap: () => player.playFromQueue(i),
                onLongPress: () => HapticFeedback.mediumImpact(),
              ),
            );
          },
        );
      }),
    );
  }
}