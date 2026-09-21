import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Shared effect instances, attached to the player's AudioPipeline in
// PlayerProvider. Singletons so UI and player always drive the same objects.
final androidEqualizer = AndroidEqualizer();
final androidLoudnessEnhancer = AndroidLoudnessEnhancer();

/// 5-band presets in dB, mapped fractionally onto however many bands the
/// device reports (usually 5).
class EqualizerProvider extends ChangeNotifier {
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

  bool get enabled => _enabled;
  List<double> get gains => List.unmodifiable(_gains);
  bool get bassBoost => _bassBoost;
  double get bassStrength => _bassStrength;
  String get preset => _preset;
  bool get ready => _ready;
  AndroidEqualizerParameters? get params => _params;

  EqualizerProvider() {
    _load();
    // Applies once the platform exposes the device bands (after first play).
    _applyWhenReady();
  }

  Future<void> _applyWhenReady() async {
    try {
      _params = await androidEqualizer.parameters;
      _ready = true;
      if (_gains.length != _params!.bands.length) {
        _gains = List<double>.filled(_params!.bands.length, 0.0);
      }
      await _applyAll();
    } catch (e) {
      debugPrint('[EQ] parameters unavailable: $e');
    }
  }

  double _effectiveGain(int index) {
    if (_params == null || index >= _params!.bands.length) return 0.0;
    var g = index < _gains.length ? _gains[index] : 0.0;
    if (_bassBoost && _params!.bands[index].centerFrequency < 250) {
      g += _bassStrength;
    }
    return g.clamp(_params!.minDecibels, _params!.maxDecibels);
  }

  Future<void> _applyAll() async {
    if (!_ready || _params == null) return;
    try {
      await androidEqualizer.setEnabled(_enabled);
      for (var i = 0; i < _params!.bands.length; i++) {
        await _params!.bands[i].setGain(_effectiveGain(i));
      }
      // Loudness enhancer follows the master switch (flat target gain — the
      // audible shaping comes from the bands, incl. bass boost).
      await androidLoudnessEnhancer.setEnabled(_enabled && _bassBoost);
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
    _gains = List<double>.generate(n, (i) => p[(i * p.length / n).floor().clamp(0, p.length - 1)]);
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
      await prefs.setStringList('eq_gains', _gains.map((g) => g.toString()).toList());
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
