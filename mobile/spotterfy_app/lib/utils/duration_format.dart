/// The app's single duration style, used for song lengths, playlist totals and
/// playback positions alike.
///
/// `hh:mm:ss`, zero padded, hours always present. The old mix switched shape at
/// the hour mark (`03:45`, `1h 05:32`, `1 hr 05 min`), so the same number of
/// seconds read differently depending on where it was shown, and columns of
/// track lengths did not line up.
String formatDuration(Duration d) {
  final total = d.isNegative ? Duration.zero : d;
  final hours = total.inHours;
  final minutes = total.inMinutes.remainder(60);
  final seconds = total.inSeconds.remainder(60);
  return '${_pad(hours)}:${_pad(minutes)}:${_pad(seconds)}';
}

/// [milliseconds] rendered as `hh:mm:ss`.
String formatDurationMs(int milliseconds) =>
    formatDuration(Duration(milliseconds: milliseconds));

String _pad(int value) => value.toString().padLeft(2, '0');
