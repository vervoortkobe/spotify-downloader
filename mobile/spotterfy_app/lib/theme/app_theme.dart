import 'package:flutter/material.dart';

/// A selectable palette.
class AppPalette {
  final String name;

  /// Accent for primary actions and active states.
  final Color primary;
  final Color primaryDark;

  /// True-black surfaces for OLED panels.
  final bool amoled;

  const AppPalette({
    required this.name,
    required this.primary,
    required this.primaryDark,
    this.amoled = false,
  });
}

class SpotterfyTheme {
  // Spotify color palette.
  //
  // These were `static const`, which made a runtime theme impossible: a const is
  // frozen at compile time, so an accent change after launch could never reach
  // the hundreds of call sites that read them. They are mutable statics now, and
  // ThemeController repaints the tree whenever one changes. Read sites are
  // unchanged - they were already just reading these names.
  static Color primary = const Color(0xFF1DB954); // Spotify green
  static Color primaryDark = const Color(0xFF1ED760);
  static Color background = const Color(0xFF191414); // Spotify dark background
  static Color surface = const Color(0xFF1E1E1E); // Card background
  static Color card = const Color(0xFF282828); // Elevated surface
  static Color text = const Color(0xFFFFFFFF); // Pure white
  static Color muted = const Color(0xFFB3B3B3); // Spotify muted text
  static Color mutedDark = const Color(0xFF6A6A6A);

  /// 10% accent wash, derived so it follows the accent instead of going stale.
  static Color get primaryBg =>
      Color.alphaBlend(primary.withValues(alpha: 0.10), background);

  /// Accents offered by the theme page. Each is checked for legibility against
  /// the dark surfaces - a prettier accent that hurts readability is not one.
  static const List<AppPalette> palettes = [
    AppPalette(
      name: 'Spotify green',
      primary: Color(0xFF1DB954),
      primaryDark: Color(0xFF1ED760),
    ),
    AppPalette(
      name: 'Emerald',
      primary: Color(0xFF10B981),
      primaryDark: Color(0xFF34D399),
    ),
    AppPalette(
      name: 'Sky',
      primary: Color(0xFF38BDF8),
      primaryDark: Color(0xFF7DD3FC),
    ),
    AppPalette(
      name: 'Violet',
      primary: Color(0xFFA78BFA),
      primaryDark: Color(0xFFC4B5FD),
    ),
    AppPalette(
      name: 'Rose',
      primary: Color(0xFFF472B6),
      primaryDark: Color(0xFFFB9DC8),
    ),
    AppPalette(
      name: 'Amber',
      primary: Color(0xFFFBBF24),
      primaryDark: Color(0xFFFCD34D),
    ),
  ];

  /// True when the app is currently on OLED black.
  static bool get isAmoled => background == const Color(0xFF000000);

  /// Points every colour at [palette]. Called by ThemeController before it asks
  /// the tree to rebuild, so anything reading a colour during build sees it.
  static void apply(AppPalette palette) {
    primary = palette.primary;
    primaryDark = palette.primaryDark;
    if (palette.amoled) {
      background = const Color(0xFF000000);
      surface = const Color(0xFF0A0A0A);
      card = const Color(0xFF141414);
    } else {
      background = const Color(0xFF191414);
      surface = const Color(0xFF1E1E1E);
      card = const Color(0xFF282828);
    }
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: primary,
        surface: surface,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: text,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: muted.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted.withValues(alpha: 0.5)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              500,
            ), // Pill-shaped buttons like Spotify
          ),
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ), // Spotify uses 8px radius
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      textTheme: TextTheme(
        displayLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: text,
        ),
        displayMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: text,
        ),
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        headlineMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        titleMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: text,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.normal,
          color: text,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.normal,
          color: text,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.normal,
          color: muted,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: muted,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: muted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(fontSize: 12),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        iconTheme: IconThemeData(color: text),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(color: text, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: primary.withValues(alpha: 0.5)),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(color: card, thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: primary.withValues(alpha: 0.3),
        labelStyle: TextStyle(color: text, fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return muted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primary.withValues(alpha: 0.5);
          }
          return muted.withValues(alpha: 0.3);
        }),
      ),
    );
  }
}
