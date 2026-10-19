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

  /// Wraps the panel in its own scroll view (the default), so it can be dropped
  /// in as a whole body. Set this to false when the caller already supplies the
  /// scrollable - under a [RefreshIndicator], say - because nesting two scroll
  /// views hands the drag to the inner one and the pull gesture is lost.
  final bool scrollable;

  const NoResultsView({
    super.key,
    required this.query,
    this.title,
    this.message,
    this.icon = Icons.search_off,
    this.actionLabel,
    this.onAction,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    final panel = Padding(
      // Bottom padding clears the persistent mini player + nav bar.
      padding: scrollable
          ? const EdgeInsets.fromLTRB(24, 24, 24, 120)
          : const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: SpotterfyTheme.muted),
          SizedBox(height: 16),
          Text(
            title ?? (q.isEmpty ? 'Nothing found' : 'Nothing found for "$q"'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: SpotterfyTheme.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 8),
          Text(
            message ?? 'Check the spelling or try a different search.',
            textAlign: TextAlign.center,
            style: TextStyle(color: SpotterfyTheme.muted, fontSize: 13),
          ),
          if (actionLabel != null && onAction != null) ...[
            SizedBox(height: 20),
            TextButton.icon(
              onPressed: onAction,
              icon: Icon(Icons.clear, color: SpotterfyTheme.primary, size: 18),
              label: Text(
                actionLabel!,
                style: TextStyle(color: SpotterfyTheme.primary),
              ),
            ),
          ],
        ],
      ),
    );
    return Center(
      child: scrollable ? SingleChildScrollView(child: panel) : panel,
    );
  }
}
