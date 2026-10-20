import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// A circular profile picture backed by the on-disk image cache.
///
/// Replaces the scattered `CircleAvatar(backgroundImage: NetworkImage(...))`
/// call sites. `NetworkImage` only has an in-memory cache, which is why the
/// navbar avatar and chat avatars turned into placeholders when the app was
/// opened without a connection. `CachedNetworkImage` keeps the last successful
/// download on disk and serves it again offline.
class UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final double radius;
  final IconData fallbackIcon;
  final Color? backgroundColor;

  const UserAvatar({
    super.key,
    required this.photoUrl,
    this.radius = 16,
    this.fallbackIcon = Icons.person,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final url = photoUrl?.trim() ?? '';
    final diameter = radius * 2;
    final fallback = Container(
      width: diameter,
      height: diameter,
      color: backgroundColor ?? SpotterfyTheme.surface,
      alignment: Alignment.center,
      child: Icon(
        fallbackIcon,
        color: SpotterfyTheme.muted,
        size: radius * 1.1,
      ),
    );

    if (url.isEmpty) return ClipOval(child: fallback);

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: diameter,
        height: diameter,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 120),
        // Keep the decoded bitmap small: these are 30-40 px circles, not full
        // profile pages, and a grid of friends should not hold full-size bitmaps.
        memCacheWidth: (diameter * 3).round(),
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}
