import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/equalizer_provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';

class EqualizerScreen extends StatelessWidget {
  const EqualizerScreen({super.key});

  String _freqLabel(double hz) {
    if (hz < 1000) return '${hz.round()} Hz';
    final k = hz / 1000;
    return '${k >= 10 ? k.round() : k.toStringAsFixed(1)} kHz';
  }

  @override
  Widget build(BuildContext context) {
    final eq = context.watch<EqualizerProvider>();
    return SwipeBackWrapper(
      child: Scaffold(
        backgroundColor: SpotterfyTheme.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('Equalizer', style: TextStyle(color: SpotterfyTheme.text, fontWeight: FontWeight.bold, fontSize: 22)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _card(Row(
                children: [
                  const Icon(Icons.graphic_eq, color: SpotterfyTheme.primary, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Equalizer', style: TextStyle(color: SpotterfyTheme.text, fontSize: 15, fontWeight: FontWeight.w700)),
                      Text('Android only', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
                    ]),
                  ),
                  Switch(
                    value: eq.enabled,
                    activeThumbColor: SpotterfyTheme.primary,
                    onChanged: (v) => context.read<EqualizerProvider>().setEnabled(v),
                  ),
                ],
              )),
              const SizedBox(height: 16),
              if (!eq.ready)
                _card(const Row(children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Expanded(child: Text('Play something once to initialize the device equalizer.', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 13))),
                ]))
              else ...[
                const Text('Presets', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: EqualizerProvider.presets.keys.map((name) {
                    final selected = eq.preset == name;
                    return ChoiceChip(
                      label: Text(name),
                      selected: selected,
                      onSelected: (_) => context.read<EqualizerProvider>().applyPreset(name),
                      selectedColor: SpotterfyTheme.primary.withValues(alpha: 0.25),
                      labelStyle: TextStyle(color: selected ? SpotterfyTheme.primary : SpotterfyTheme.text, fontSize: 12, fontWeight: FontWeight.w600),
                      backgroundColor: SpotterfyTheme.surface,
                      side: BorderSide(color: selected ? SpotterfyTheme.primary : SpotterfyTheme.card),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                _card(Column(
                  children: [
                    for (var i = 0; i < (eq.params?.bands.length ?? 0); i++)
                      _bandRow(context, eq, i),
                  ],
                )),
                const SizedBox(height: 16),
                _card(Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.speaker, color: SpotterfyTheme.primary, size: 22),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Bass boost', style: TextStyle(color: SpotterfyTheme.text, fontSize: 15, fontWeight: FontWeight.w700)),
                          Text('Extra gain below 250 Hz', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
                        ]),
                      ),
                      Switch(
                        value: eq.bassBoost,
                        activeThumbColor: SpotterfyTheme.primary,
                        onChanged: (v) => context.read<EqualizerProvider>().setBassBoost(v),
                      ),
                    ]),
                    Row(children: [
                      const Text('Strength', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: eq.bassStrength.clamp(0.0, 12.0),
                          min: 0,
                          max: 12,
                          divisions: 12,
                          label: '+${eq.bassStrength.toStringAsFixed(0)} dB',
                          activeColor: SpotterfyTheme.primary,
                          onChanged: (v) => context.read<EqualizerProvider>().setBassStrength(v),
                        ),
                      ),
                      SizedBox(
                        width: 56,
                        child: Text('+${eq.bassStrength.toStringAsFixed(0)} dB',
                            textAlign: TextAlign.end,
                            style: const TextStyle(color: SpotterfyTheme.text, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
                      ),
                    ]),
                  ],
                )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: SpotterfyTheme.surface, borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  Widget _bandRow(BuildContext context, EqualizerProvider eq, int index) {
    final params = eq.params!;
    final band = params.bands[index];
    final gain = index < eq.gains.length ? eq.gains[index] : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 64,
          child: Text(_freqLabel(band.centerFrequency),
              style: const TextStyle(color: SpotterfyTheme.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Slider(
            value: gain.clamp(params.minDecibels, params.maxDecibels),
            min: params.minDecibels,
            max: params.maxDecibels,
            label: '${gain.toStringAsFixed(1)} dB',
            activeColor: SpotterfyTheme.primary,
            onChanged: (v) => context.read<EqualizerProvider>().setBandGain(index, v),
          ),
        ),
        SizedBox(
          width: 64,
          child: Text('${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
              textAlign: TextAlign.end,
              style: const TextStyle(color: SpotterfyTheme.text, fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
        ),
      ]),
    );
  }
}
