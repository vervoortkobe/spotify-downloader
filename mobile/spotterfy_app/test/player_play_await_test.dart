import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the fix for "play takes ages / pause does nothing".
///
/// just_audio's `play()` future only completes when playback is *paused or
/// stopped*, not when audio starts. Awaiting it therefore blocks for the whole
/// track. That bug is invisible to the compiler and to a normal unit test, so
/// the only cheap guard is a source-level check: no code path may await it.
void main() {
  final playerProvider = File('lib/providers/player_provider.dart');

  test('no call site awaits the play() future', () {
    final source = playerProvider.readAsStringSync();
    final offenders = <String>[];
    for (final line in source.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
      // Anything that consumes the future is the bug. A bare `_player.play()`
      // inside unawaited() or .catchError() is the intended fix.
      if (RegExp(r'await\s+_player\s*\.\s*play\s*\(').hasMatch(trimmed)) {
        offenders.add(trimmed);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'await on play() blocks until the track ends. Wait on playingStream '
          'via _playUntilAudible() instead.',
    );
  });

  test('the guarded helper exists and is the only way playback starts', () {
    final source = playerProvider.readAsStringSync();
    expect(
      source,
      contains('Future<void> _playUntilAudible()'),
      reason: 'the bounded playingStream wait should exist',
    );
    expect(source, contains('playingStream'));
  });

  test('playback start is bounded so a stalled source cannot wedge the UI', () {
    final source = playerProvider.readAsStringSync();
    expect(
      source,
      matches(RegExp(r'_playUntilAudible[\s\S]{0,900}?\.timeout\(')),
      reason: 'the wait needs a ceiling or the toggle lock never releases',
    );
  });
}
