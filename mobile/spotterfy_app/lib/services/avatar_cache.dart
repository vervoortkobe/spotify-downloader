import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Warms the same disk cache that `CachedNetworkImage` reads from.
///
/// Avatars are small, but they are the first thing to go missing offline: a
/// plain `NetworkImage` never touches the cache, so the navbar falls back to a
/// person icon as soon as the connection drops. Downloading the signed-in
/// user's picture (and the people in the chat list) while online means the
/// cached file is still there on the next cold, offline launch.
class AvatarCache {
  AvatarCache._();

  /// URLs already requested in this process, so polling the same friend list
  /// does not re-open the cache for every tick.
  static final Set<String> _warmed = <String>{};

  static Future<void> warm(String? url) async {
    final key = url?.trim() ?? '';
    if (key.isEmpty || !_warmed.add(key)) return;
    try {
      final cache = DefaultCacheManager();
      // getFileFromCache is free and covers the common case. Only go to the
      // network when the picture has never been downloaded.
      final cached = await cache.getFileFromCache(key);
      if (cached != null) return;
      await cache.downloadFile(key);
    } catch (_) {
      // Offline or a dead URL: allow a later attempt instead of remembering
      // the failure for the rest of the session.
      _warmed.remove(key);
    }
  }
}
