import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/jam_provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// Opens the live jam session: the shared queue plus the controls for it.
///
/// Shown as a sheet rather than a route because a jam is something you keep an
/// eye on while doing other things - the whole point is that it stays running
/// in the background.
void showJamSessionSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    // Above the mini player: this is opened from a tab navigator, which the mini
    // player is drawn over.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: SpotterfyTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const JamSessionSheet(),
  );
}

class JamSessionSheet extends StatelessWidget {
  const JamSessionSheet({super.key});

  Future<void> _playTrack(
    BuildContext context,
    JamProvider jam,
    PlayerProvider player,
    int index,
  ) async {
    final session = jam.currentSession;
    if (session == null || index < 0 || index >= session.tracks.length) return;
    final track = session.tracks[index];
    await player.play(track, queue: session.tracks);
    await jam.updatePlayback(
      isPlaying: player.isPlaying,
      positionMs: player.position.inMilliseconds,
      trackIndex: index,
    );
  }

  Future<void> _toggleJam(
    BuildContext context,
    JamProvider jam,
    PlayerProvider player,
  ) async {
    final session = jam.currentSession;
    if (session == null) return;
    final playingThisJam = player.currentTrack != null &&
        session.tracks.any((t) => t.id == player.currentTrack!.id);
    if (playingThisJam && player.isPlaying) {
      await player.pause();
      await jam.updatePlayback(
        isPlaying: false,
        positionMs: player.position.inMilliseconds,
      );
      return;
    }
    if (playingThisJam) {
      await player.resume();
      await jam.updatePlayback(
        isPlaying: player.isPlaying,
        positionMs: player.position.inMilliseconds,
      );
      return;
    }
    await _playTrack(context, jam, player, session.currentTrackIndex);
  }

  @override
  Widget build(BuildContext context) {
    final jam = context.watch<JamProvider>();
    final auth = context.read<AuthProvider>();
    final session = jam.currentSession;
    if (session == null) return const SizedBox.shrink();

    final myUid = auth.user?.uid;
    final iAmCreator = session.createdBy == myUid;
    final player = context.watch<PlayerProvider>();
    final playingThisJam =
        player.currentTrack != null &&
        session.tracks.any((t) => t.id == player.currentTrack!.id);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: SpotterfyTheme.overlay(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: SpotterfyTheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.groups,
                    color: SpotterfyTheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: SpotterfyTheme.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${session.participants.length} '
                        '${session.participants.length == 1 ? 'person' : 'people'}'
                        ' in this jam',
                        style: TextStyle(
                          color: SpotterfyTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Shared queue',
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: session.tracks.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'This jam has no songs yet',
                          style: TextStyle(color: SpotterfyTheme.muted),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: session.tracks.length,
                      itemBuilder: (_, i) {
                        final t = session.tracks[i];
                        final isCurrent = i == session.currentTrackIndex;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: SpotterfyTheme.fill,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isCurrent && session.isPlaying
                                  ? Icons.volume_up
                                  : Icons.music_note,
                              size: 18,
                              color: isCurrent
                                  ? SpotterfyTheme.primary
                                  : SpotterfyTheme.muted,
                            ),
                          ),
                          title: Text(
                            t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent
                                  ? SpotterfyTheme.primary
                                  : SpotterfyTheme.text,
                              fontSize: 14,
                              fontWeight: isCurrent
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            t.artists,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: SpotterfyTheme.muted,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () => _playTrack(context, jam, player, i),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _toggleJam(context, jam, player),
                    icon: Icon(
                      playingThisJam && player.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                      size: 18,
                    ),
                    label: Text(
                      playingThisJam && player.isPlaying ? 'Pause' : 'Play',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SpotterfyTheme.text,
                      side: BorderSide(color: SpotterfyTheme.borderColor),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _playTrack(
                      context,
                      jam,
                      player,
                      session.currentTrackIndex + 1,
                    ),
                    icon: const Icon(Icons.skip_next, size: 18),
                    label: const Text('Next'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SpotterfyTheme.text,
                      side: BorderSide(color: SpotterfyTheme.borderColor),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: iAmCreator
                  ? ElevatedButton.icon(
                      onPressed: () async {
                        await jam.endSession(myUid!);
                        if (context.mounted) Navigator.pop(context);
                      },
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('End jam'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFef4444),
                        foregroundColor: Colors.white,
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: () async {
                        await jam.leaveSession(myUid!);
                        if (context.mounted) Navigator.pop(context);
                      },
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Leave jam'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: SpotterfyTheme.text,
                        side: BorderSide(color: SpotterfyTheme.borderColor),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
