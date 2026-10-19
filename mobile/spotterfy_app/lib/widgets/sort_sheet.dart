import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// One choice in a sort sheet.
class SortSheetOption<T> {
  final T value;
  final String label;
  final IconData icon;

  const SortSheetOption({
    required this.value,
    required this.label,
    required this.icon,
  });
}

/// The app-wide sort picker.
///
/// Extracted from the library's sort sheet so every list (playlists, downloads,
/// admin) keeps the same header, active-row tint and check mark instead of each
/// screen hand-rolling its own RadioListTile sheet.
Future<T?> showAppSortSheet<T>({
  required BuildContext context,
  required String scope,
  required List<SortSheetOption<T>> options,
  required T current,
  String title = 'Sort by',
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<T>(
    context: context,
    // Above the mini player: it is a sibling of the tab navigators inside
    // MainScreen's Stack, so a sheet on a tab's own navigator would render
    // underneath it and its lowest options would not be tappable.
    useRootNavigator: true,
    backgroundColor: SpotterfyTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: SpotterfyTheme.overlay(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: SpotterfyTheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.swap_vert_rounded,
                      size: 18,
                      color: SpotterfyTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: SpotterfyTheme.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          scope,
                          style: TextStyle(
                            color: SpotterfyTheme.mutedDark,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            for (final option in options) _option(sheetCtx, option, current),
          ],
        ),
      ),
    ),
  );
}

Widget _option<T>(BuildContext sheetCtx, SortSheetOption<T> option, T current) {
  final selected = option.value == current;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Material(
      color: selected
          ? SpotterfyTheme.accentSurface
          : SpotterfyTheme.overlay(0.04),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.pop(sheetCtx, option.value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(
                option.icon,
                size: 18,
                color: selected ? SpotterfyTheme.primary : SpotterfyTheme.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  option.label,
                  style: TextStyle(
                    color: selected
                        ? SpotterfyTheme.primary
                        : SpotterfyTheme.text,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_rounded,
                  size: 18,
                  color: SpotterfyTheme.primary,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
