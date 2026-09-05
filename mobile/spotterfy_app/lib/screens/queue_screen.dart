import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotterfyTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Queue', style: TextStyle(color: SpotterfyTheme.text, fontSize: 22, fontWeight: FontWeight.bold)),
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
              Text('Play a playlist or swipe right on a track\nto add it to the queue.', textAlign: TextAlign.center, style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
            ]),
          );
        }
        return ReorderableListView.builder(
          padding: const EdgeInsets.only(bottom: 140, top: 8),
          itemCount: q.length,
          onReorderItem: (oldIndex, newIndex) {
            final item = q.removeAt(oldIndex);
            q.insert(newIndex, item);
            player.setQueue(q, startIndex: player.currentIndex);
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
