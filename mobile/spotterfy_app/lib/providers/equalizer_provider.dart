import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Shared effect instances, attached to the player's AudioPipeline in
// PlayerProvider. Singletons so UI and player always drive the same objects.
// A crossfade's secondary player owns its own instances (an effect can only
// be attached to one player at a time); see [bindEffects].
final androidEqualizer = AndroidEqualizer();
final androidLoudnessEnhancer = AndroidLoudnessEnhancer();

/// 5-band presets in dB, mapped fractionally onto however many bands the
/// device reports (usually 5).
class EqualizerProvider extends ChangeNotifier {
  /// The live provider instance, set by its constructor.
  ///
  /// PlayerProvider uses this to hand the current primary player's effect
  /// instances to (and take them back from) the provider, since a crossfade
  /// swaps the primary player and the effect instances must follow.
  static EqualizerProvider? current;

  static const Map<String, List<double>> presets = {
    'Flat': [0, 0, 0, 0, 0],
    'Bass': [7, 5, 2, -1, -3],
    'Treble': [-4, -2, 1, 4, 6],
    'Vocal': [-3, -1, 3, 4, 2],
    'Rock': [5, 3, -1, 3, 5],
    'Pop': [2, 4, 1, 2, 3],
    'Jazz': [3, 2, 0, 2, 4],
    'Classical': [4, 3, -1, 3, 4],
    'Dance': [6, 2, 0, 2, 5],
    'Hip-Hop': [6, 4, 0, 1, 3],
  };

  bool _enabled = false;
  List<double> _gains = [];
  bool _bassBoost = false;
  double _bassStrength = 6.0;
  String _preset = 'Flat';
  AndroidEqualizerParameters? _params;
  bool _ready = false;

  /// Effect instances of the *current* primary player.
  ///
  /// Starts as the singletons but is re-pointed at a crossfade's secondary
  /// player when it takes over playback, since that player owns its own
  /// instances and the outgoing player's die with it.
  List<AndroidAudioEffect> _activeEffects = [
    androidEqualizer,
    androidLoudnessEnhancer,
  ];

  AndroidEqualizer? get _equalizer {
    for (final e in _activeEffects) {
      if (e is AndroidEqualizer) return e;
    }
    return null;
  }

  AndroidLoudnessEnhancer? get _loudness {
    for (final e in _activeEffects) {
      if (e is AndroidLoudnessEnhancer) return e;
    }
    return null;
  }

  bool get enabled => _enabled;
  List<double> get gains => List.unmodifiable(_gains);
  bool get bassBoost => _bassBoost;
  double get bassStrength => _bassStrength;
  String get preset => _preset;
  bool get ready => _ready;
  AndroidEqualizerParameters? get params => _params;

  EqualizerProvider() {
    current = this;
    _load();
    // Applies once the platform exposes the device bands (after first play).
    _applyWhenReady();
  }

  Future<void> _applyWhenReady() async {
    try {
      final eq = _equalizer;
      if (eq == null) return;
      _params = await eq.parameters;
      _ready = true;
      if (_gains.length != _params!.bands.length) {
        _gains = List<double>.filled(_params!.bands.length, 0.0);
      }
      await _applyAll();
    } catch (e) {
      debugPrint('[EQ] parameters unavailable: $e');
    }
  }

  /// Points the provider at a different set of effect instances and
  /// re-applies the stored settings to them.
  ///
  /// Called when a crossfade hands playback to the secondary player, which
  /// owns its own instances. Must only be called once that player is active,
  /// so its [AndroidEqualizer.parameters] are available.
  Future<void> bindEffects(List<AndroidAudioEffect> effects) async {
    _activeEffects = effects;
    _params = null;
    _ready = false;
    await _applyWhenReady();
  }

  /// Configures a fresh set of effect instances with the current EQ state,
  /// without making them the active set.
  ///
  /// Used for a crossfade's secondary player so the incoming track sounds
  /// the same as the outgoing one during the fade; [bindEffects] then takes
  /// over once that player becomes the primary.
  Future<void> applyTo(List<AndroidAudioEffect> effects) async {
    AndroidEqualizer? eq;
    AndroidLoudnessEnhancer? loudness;
    for (final e in effects) {
      if (e is AndroidEqualizer) eq = e;
      if (e is AndroidLoudnessEnhancer) loudness = e;
    }
    if (eq == null || loudness == null) return;
    try {
      final params = await eq.parameters;
      await eq.setEnabled(_enabled);
      for (var i = 0; i < params.bands.length && i < _gains.length; i++) {
        await params.bands[i].setGain(_effectiveGain(i, params));
      }
      await loudness.setEnabled(_enabled && _bassBoost);
    } catch (e) {
      debugPrint('[EQ] applyTo failed: $e');
    }
  }

  double _effectiveGain(int index, [AndroidEqualizerParameters? params]) {
    final p = params ?? _params;
    if (p == null || index >= p.bands.length) return 0.0;
    var g = index < _gains.length ? _gains[index] : 0.0;
    if (_bassBoost && p.bands[index].centerFrequency < 250) {
      g += _bassStrength;
    }
    return g.clamp(p.minDecibels, p.maxDecibels);
  }

  Future<void> _applyAll() async {
    if (!_ready || _params == null) return;
    final eq = _equalizer;
    final loudness = _loudness;
    if (eq == null || loudness == null) return;
    try {
      await eq.setEnabled(_enabled);
      for (var i = 0; i < _params!.bands.length; i++) {
        await _params!.bands[i].setGain(_effectiveGain(i));
      }
      // Loudness enhancer follows the master switch (flat target gain — the
      // audible shaping comes from the bands, incl. bass boost).
      await loudness.setEnabled(_enabled && _bassBoost);
    } catch (e) {
      debugPrint('[EQ] apply failed: $e');
    }
    await _persist();
    notifyListeners();
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    await _applyAll();
  }

  Future<void> setBandGain(int index, double gain) async {
    if (index < 0) return;
    while (_gains.length <= index) {
      _gains.add(0.0);
    }
    _gains[index] = gain;
    _preset = 'Custom';
    await _applyAll();
  }

  Future<void> applyPreset(String name) async {
    final p = presets[name];
    if (p == null || _params == null) return;
    final n = _params!.bands.length;
    _gains = List<double>.generate(
      n,
      (i) => p[(i * p.length / n).floor().clamp(0, p.length - 1)],
    );
    _preset = name;
    await _applyAll();
  }

  Future<void> setBassBoost(bool v) async {
    _bassBoost = v;
    await _applyAll();
  }

  Future<void> setBassStrength(double v) async {
    _bassStrength = v.clamp(0.0, 12.0);
    await _applyAll();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('eq_enabled', _enabled);
      await prefs.setStringList(
        'eq_gains',
        _gains.map((g) => g.toString()).toList(),
      );
      await prefs.setBool('eq_bass', _bassBoost);
      await prefs.setDouble('eq_bass_strength', _bassStrength);
      await prefs.setString('eq_preset', _preset);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('eq_enabled') ?? false;
      _gains = (prefs.getStringList('eq_gains') ?? [])
          .map((s) => double.tryParse(s) ?? 0.0)
          .toList();
      _bassBoost = prefs.getBool('eq_bass') ?? false;
      _bassStrength = prefs.getDouble('eq_bass_strength') ?? 6.0;
      _preset = prefs.getString('eq_preset') ?? 'Flat';
    } catch (_) {}
    notifyListeners();
  }
}
