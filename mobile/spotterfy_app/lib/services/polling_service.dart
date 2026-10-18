import 'dart:async';

import 'package:flutter/foundation.dart';

/// Refreshes data on a fixed interval instead of holding a live Firestore
/// listener open.
///
/// Every tick is an explicit read. That trades a couple of seconds of latency
/// and a handful of reads for predictability: a tick that fails is logged and
/// retried on the next one, so a single bad network moment no longer leaves a
/// screen stale for the rest of the session the way a dropped `.snapshots()`
/// subscription can.
///
/// A timer only runs while the returned stream has listeners, so leaving a
/// screen stops its reads.
class PollingService {
  PollingService._internal();

  static final PollingService instance = PollingService._internal();

  /// Conversations are the most latency-sensitive surface, so they poll
  /// fastest.
  static const Duration chatInterval = Duration(seconds: 3);

  /// The in-jam session - shared queue, current track, play state - changes on
  /// user actions and should feel immediate.
  static const Duration jamInterval = Duration(seconds: 2);

  /// The social graph - friends, requests, notifications, chat list and the
  /// list of live jams - changes rarely.
  static const Duration socialInterval = Duration(seconds: 8);

  /// Emits the result of [fetch] immediately, then again every [interval],
  /// until every listener has cancelled.
  ///
  /// [signature] suppresses redundant emissions: when it returns a value equal
  /// to the previous tick's, the freshly-fetched payload is dropped. Lists of
  /// re-deserialized objects are never `==` to one another, so without a
  /// signature every tick would notify listeners even when nothing changed.
  ///
  /// [refresh] lets a caller force an immediate tick - used after sending a
  /// message so the sender does not wait out the interval.
  ///
  /// A failed [fetch] is logged and skipped: the previous value stays on screen
  /// and the next tick retries.
  Stream<T> poll<T>({
    required Future<T> Function() fetch,
    required Duration interval,
    Object? Function(T value)? signature,
    Stream<void>? refresh,
  }) {
    final controller = StreamController<T>.broadcast();
    StreamSubscription<void>? refreshSub;
    Timer? timer;
    Object? lastSignature;
    var hasEmitted = false;
    var busy = false;

    Future<void> tick() async {
      if (busy || controller.isClosed) return;
      busy = true;
      try {
        final value = await fetch();
        if (controller.isClosed) return;
        if (signature != null) {
          final next = signature(value);
          if (hasEmitted && next == lastSignature) return;
          lastSignature = next;
        }
        hasEmitted = true;
        controller.add(value);
      } catch (error) {
        debugPrint('[Polling] refresh failed, keeping last value: $error');
      } finally {
        busy = false;
      }
    }

    controller.onListen = () {
      tick();
      timer?.cancel();
      timer = Timer.periodic(interval, (_) => tick());
      refreshSub?.cancel();
      refreshSub = refresh?.listen((_) => tick());
    };
    controller.onCancel = () {
      timer?.cancel();
      timer = null;
      refreshSub?.cancel();
      refreshSub = null;
    };

    return controller.stream;
  }
}
