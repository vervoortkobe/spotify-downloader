import 'dart:async';

import 'package:flutter/foundation.dart';

/// The account-level permission for audio playback.
///
/// Playback is reachable from screens, the notification, Bluetooth media
/// buttons and Android Auto. Keeping the decision here gives all of those paths
/// the same answer, including calls made without a [BuildContext] or before the
/// suspended screen is mounted.
class PlaybackAccess extends ChangeNotifier {
  PlaybackAccess._();

  static final PlaybackAccess instance = PlaybackAccess._();

  bool _known = false;
  bool _suspended = false;
  bool _softBanned = false;
  Completer<void> _knownCompleter = Completer<void>();

  /// True once [AuthProvider] has supplied the signed-in account's status.
  bool get isKnown => _known;

  /// Resolves as soon as the signed-in account's status is known.
  Future<void> get whenKnown => _knownCompleter.future;

  bool get isSuspended => _suspended;
  bool get isSoftBanned => _softBanned;

  /// Playback stays denied until the account status is known, so a cold Android
  /// Auto start cannot start music before the suspension check has run.
  bool get canPlay => _known && !_suspended;

  /// Streaming is additionally gated by the soft-ban flag.
  ///
  /// A soft-banned user can log in and browse but cannot play audio. Use
  /// [canStream] wherever audio output is initiated; use [canPlay] only where
  /// the full-account suspension lock is the relevant check.
  bool get canStream => _known && !_suspended && !_softBanned;

  /// Applies the signed-in account's moderation state.
  void update({required bool suspended, bool softBanned = false}) {
    final changed =
        !_known || _suspended != suspended || _softBanned != softBanned;
    _known = true;
    _suspended = suspended;
    _softBanned = softBanned;
    if (!_knownCompleter.isCompleted) _knownCompleter.complete();
    if (changed) notifyListeners();
  }

  @visibleForTesting
  void reset() {
    _known = false;
    _suspended = false;
    _softBanned = false;
    _knownCompleter = Completer<void>();
    notifyListeners();
  }
}
