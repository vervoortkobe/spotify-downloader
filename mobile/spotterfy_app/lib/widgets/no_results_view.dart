import 'package:flutter/material.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// Shared "nothing found" panel.
///
/// Extracted from the Discover page's empty-search state so every list in the
/// app reports "no matches" the same way, with the copy tailored per screen.
/// Render it as a full body (or the child of a scroll view) so it can centre
/// itself in the available space.
class NoResultsView extends StatelessWidget {
  /// The text the user typed, interpolated into the title.
  final String query;

  /// Headline. Defaults to `Nothing found for "<query>"`.
  final String? title;

  /// Supporting line. Defaults to a generic spelling/different-search hint.
  final String? message;

  final IconData icon;

  /// Optional trailing action, e.g. a "Clear search" button.
  final String? actionLabel;
  final VoidCallback? onAction;

  const NoResultsView({
    super.key,
    required this.query,
    this.title,
    this.message,
    this.icon = Icons.search_off,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    return Center(
      child: SingleChildScrollView(
        // Bottom padding clears the persistent mini player + nav bar.
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: SpotterfyTheme.muted),
            const SizedBox(height: 16),
            Text(
              title ?? (q.isEmpty ? 'Nothing found' : 'Nothing found for "$q"'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message ?? 'Check the spelling or try a different search.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: SpotterfyTheme.muted, fontSize: 13),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: onAction,
                icon: const Icon(
                  Icons.clear,
                  color: SpotterfyTheme.primary,
                  size: 18,
                ),
                label: Text(
                  actionLabel!,
                  style: const TextStyle(color: SpotterfyTheme.primary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
