import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// Owns the selected palette and repaints the app when it changes.
///
/// The colours themselves live in [SpotterfyTheme] because ~450 call sites read
/// them as plain statics. Changing one of those statics does *not* repaint
/// anything on its own - a plain field is not an inherited widget - so this
/// notifies and `main.dart` rebuilds the tree below the `MaterialApp`, which
/// makes every `build()` re-read the colours.
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const _accentKey = 'theme_accent';
  static const _oledKey = 'theme_oled_black';

  /// Name of the chosen accent, matching an entry in [SpotterfyTheme.palettes].
  String _accent = SpotterfyTheme.palettes.first.name;

  /// AMOLED black on top of the accent.
  bool _oled = false;

  String get accent => _accent;
  bool get oled => _oled;

  /// The palette currently in effect.
  AppPalette get palette => _paletteFor(_accent, _oled);

  /// Accent name plus the OLED variant, since those are chosen independently.
  bool _loaded = false;

  /// Whether the stored choice has been read back yet.
  bool get isLoaded => _loaded;

  static AppPalette _paletteFor(String accent, bool oled) {
    final base = SpotterfyTheme.palettes.firstWhere(
      (p) => p.name == accent,
      // A stale stored name must not brick startup.
      orElse: () => SpotterfyTheme.palettes.first,
    );
    return oled
        ? AppPalette(
            name: base.name,
            primary: base.primary,
            primaryDark: base.primaryDark,
            amoled: true,
          )
        : base;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _accent = prefs.getString(_accentKey) ?? _accent;
      _oled = prefs.getBool(_oledKey) ?? _oled;
    } catch (_) {
      // Preferences unavailable: keep the defaults rather than failing startup.
    }
    _loaded = true;
    _publish();
  }

  Future<void> setAccent(String name) async {
    if (_accent == name) return;
    _accent = name;
    await _persist();
    _publish();
  }

  Future<void> setOled(bool value) async {
    if (_oled == value) return;
    _oled = value;
    await _persist();
    _publish();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accentKey, _accent);
      await prefs.setBool(_oledKey, _oled);
    } catch (_) {
      // Not being able to remember the choice must not break switching it.
    }
  }

  /// Points the colours at the current palette, then asks for a repaint.
  void _publish() {
    SpotterfyTheme.apply(palette);
    notifyListeners();
  }
}
