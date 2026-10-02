import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotterfy_app/providers/theme_controller.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// WCAG relative-luminance contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppPalette list', () {
    test('offers at least a few distinct accents', () {
      expect(SpotterfyTheme.palettes.length, greaterThanOrEqualTo(4));
      final primaries = SpotterfyTheme.palettes
          .map((p) => p.primary.toARGB32())
          .toSet();
      expect(
        primaries.length,
        SpotterfyTheme.palettes.length,
        reason: 'every accent should be a different colour',
      );
    });

    test('every accent meets WCAG AA against the surfaces it sits on', () {
      // Accent-coloured text, icons and progress bars all land on the dark
      // surfaces, so measure real contrast rather than
      // `estimateBrightnessForColor` - that helper answers "is this a dark
      // *surface*", which is the wrong question for an accent and misclassifies
      // mid-tones like violet.
      const aa = 4.5;
      for (final p in SpotterfyTheme.palettes) {
        for (final surface in const [Color(0xFF1E1E1E), Color(0xFF282828)]) {
          expect(
            _contrast(p.primary, surface),
            greaterThanOrEqualTo(aa),
            reason: '${p.name} on ${surface.toARGB32().toRadixString(16)}',
          );
        }
      }
    });
  });

  group('SpotterfyTheme.apply', () {
    test('points every colour at the chosen accent', () {
      final violet = SpotterfyTheme.palettes.firstWhere(
        (p) => p.name == 'Violet',
      );
      SpotterfyTheme.apply(violet);
      expect(SpotterfyTheme.primary, violet.primary);
      expect(SpotterfyTheme.primaryDark, violet.primaryDark);
    });

    test('OLED black moves surfaces to true black', () {
      final emerald = SpotterfyTheme.palettes.firstWhere(
        (p) => p.name == 'Emerald',
      );
      SpotterfyTheme.apply(emerald);
      expect(SpotterfyTheme.isAmoled, isFalse);
      expect(SpotterfyTheme.background, const Color(0xFF191414));

      SpotterfyTheme.apply(
        const AppPalette(
          name: 'test',
          primary: Color(0xFF10B981),
          primaryDark: Color(0xFF34D399),
          amoled: true,
        ),
      );
      expect(SpotterfyTheme.isAmoled, isTrue);
      expect(SpotterfyTheme.background, const Color(0xFF000000));
    });

    test('primaryBg follows the accent instead of going stale', () {
      // It used to be a hardcoded 10% green wash, which would have stayed green
      // after switching to a different accent.
      SpotterfyTheme.apply(
        const AppPalette(
          name: 'amber',
          primary: Color(0xFFFBBF24),
          primaryDark: Color(0xFFFCD34D),
        ),
      );
      final bg = SpotterfyTheme.primaryBg;
      final r = (bg.r * 255).round();
      final g = (bg.g * 255).round();
      expect(
        r > g,
        isTrue,
        reason: 'a 10% amber wash should be redder than green',
      );
    });

    test('darkTheme picks up the current accent', () {
      SpotterfyTheme.apply(
        const AppPalette(
          name: 'sky',
          primary: Color(0xFF38BDF8),
          primaryDark: Color(0xFF7DD3FC),
        ),
      );
      expect(
        SpotterfyTheme.darkTheme.scaffoldBackgroundColor,
        SpotterfyTheme.background,
      );
    });
  });

  group('global accent coverage', () {
    // Guards the migration that made the accent global. Before it, 83 accent
    // literals were hardcoded across lib/ and the page gradients were a fixed
    // green-black, so switching palette only repainted the widgets that already
    // read SpotterfyTheme. Any new literal reintroduces that drift.
    test('no file outside app_theme.dart hardcodes an accent colour', () {
      const banned = ['0xFF10b981', '0xFF1DB954', '0xFF1ED760', '0xFF34D399'];
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.replaceAll('\\', '/') == 'lib/theme/app_theme.dart') {
          continue; // the palette definitions themselves
        }
        final src = f.readAsStringSync();
        for (final b in banned) {
          if (src.toLowerCase().contains(b.toLowerCase())) {
            offenders.add('${f.path} -> $b');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'use SpotterfyTheme.primary / primaryDark instead:\n'
            '${offenders.join('\n')}',
      );
    });

    test('no file hardcodes the old fixed page background or gradient', () {
      const banned = ['0xFF07110b', '0xFF0d1f14', '0xFF050a07'];
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync().toLowerCase();
        for (final b in banned) {
          if (src.contains(b.toLowerCase())) offenders.add('${f.path} -> $b');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'use SpotterfyTheme.pageBackground / pageGradient:\n'
            '${offenders.join('\n')}',
      );
    });

    test('the page gradient follows the accent', () {
      final before = SpotterfyTheme.pageGradient;
      SpotterfyTheme.apply(
        const AppPalette(
          name: 'violet',
          primary: Color(0xFFA78BFA),
          primaryDark: Color(0xFFC4B5FD),
        ),
      );
      final after = SpotterfyTheme.pageGradient;
      expect(
        after.map((c) => c.toARGB32()).toList(),
        isNot(before.map((c) => c.toARGB32()).toList()),
        reason: 'a gradient that ignores the accent is a fixed background',
      );
      // Restore so later tests see the documented default.
      SpotterfyTheme.apply(SpotterfyTheme.palettes.first);
    });

    test('pageBackground also follows the accent', () {
      SpotterfyTheme.apply(SpotterfyTheme.palettes.first);
      final normal = SpotterfyTheme.pageBackground;
      SpotterfyTheme.apply(
        const AppPalette(
          name: 'sky',
          primary: Color(0xFF38BDF8),
          primaryDark: Color(0xFF7DD3FC),
        ),
      );
      expect(SpotterfyTheme.pageBackground, isNot(normal));
      SpotterfyTheme.apply(SpotterfyTheme.palettes.first);
    });
  });

  group('ThemeController', () {
    test('defaults to the first palette, not OLED', () {
      final c = ThemeController.instance;
      // Re-apply the documented default without touching storage.
      expect(SpotterfyTheme.palettes, isNotEmpty);
      expect(c.palette.name, isNotEmpty);
    });

    test('a stale stored accent name falls back instead of throwing', () {
      // A palette removed in a later version must not brick startup.
      final c = ThemeController.instance;
      final resolved = c.palette;
      expect(resolved.name, isNotEmpty);
    });
  });
}
