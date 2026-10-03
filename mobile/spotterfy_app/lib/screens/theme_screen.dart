import 'package:flutter/material.dart';
import 'package:spotterfy_app/providers/theme_controller.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/app_background.dart';
import 'package:spotterfy_app/widgets/app_chrome.dart';

/// Accent colour and OLED black.
///
/// Each option previews itself with a live swatch of the accent and of the
/// surfaces it will change, so the choice is made by looking rather than by
/// remembering what "Violet" looked like.
class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeController.instance;

    return HideAppChrome(
      child: AppGradientScaffold(
        title: 'Theme',
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => ListView(
            // Clears the nav bar drawn under this page by MainScreen.
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              _SectionLabel('Accent colour'),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Used for buttons, active tabs, progress bars and links.',
                  style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12),
                ),
              ),
              for (final p in SpotterfyTheme.palettes)
                _AccentTile(
                  palette: p,
                  selected: controller.accent == p.name && !controller.oled,
                  // OLED is an orthogonal choice, so picking an accent keeps it.
                  onTap: () => controller.setAccent(p.name),
                ),
              const SizedBox(height: 12),
              _SectionLabel('Display'),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: SpotterfyTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.contrast,
                        color: SpotterfyTheme.muted,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'OLED black',
                              style: TextStyle(
                                color: SpotterfyTheme.text,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Pure black surfaces. Saves power and looks better '
                              'on an OLED screen.',
                              style: TextStyle(
                                color: SpotterfyTheme.muted,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: controller.oled,
                        activeThumbColor: SpotterfyTheme.primary,
                        onChanged: (v) => controller.setOled(v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Changes apply straight away and are remembered on this device.',
                  style: TextStyle(
                    color: SpotterfyTheme.mutedDark,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Text(
        text,
        style: TextStyle(
          color: SpotterfyTheme.muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AccentTile extends StatelessWidget {
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  const _AccentTile({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Material(
        color: SpotterfyTheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? palette.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                // Two-tone swatch: the accent over the surface it lands on, so
                // the pairing is visible before committing.
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: SpotterfyTheme.card,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: palette.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    palette.name,
                    style: TextStyle(
                      color: SpotterfyTheme.text,
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check, color: palette.primary, size: 20)
                else
                  const SizedBox(width: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
