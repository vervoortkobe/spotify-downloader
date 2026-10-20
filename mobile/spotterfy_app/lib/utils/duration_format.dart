/// The app's single duration style, used for song lengths, playlist totals and
/// playback positions alike.
///
/// Durations under one hour use `mm:ss`; longer durations use `hh:mm:ss`.
String formatDuration(Duration d) {
  final total = d.isNegative ? Duration.zero : d;
  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60);
  final seconds = total.inSeconds.remainder(60);
  if (hours == 0) return '${_pad(total.inMinutes)}:${_pad(seconds)}';
  return '${_pad(hours)}:${_pad(minutes)}:${_pad(seconds)}';
}

/// [milliseconds] rendered as `mm:ss` or `hh:mm:ss` depending on its length.
String formatDurationMs(int milliseconds) =>
    formatDuration(Duration(milliseconds: milliseconds));

String _pad(int value) => value.toString().padLeft(2, '0');
