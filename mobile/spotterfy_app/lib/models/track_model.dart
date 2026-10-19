class TrackModel {
  final String id;
  final String title;
  final String artists;
  final String album;
  final String cover;
  final String releaseDate;
  final String sourceUrl;
  final int durationMs;

  TrackModel({
    required this.id,
    required this.title,
    required this.artists,
    this.album = '',
    this.cover = '',
    this.releaseDate = '',
    this.sourceUrl = '',
    this.durationMs = 0,
  });

  factory TrackModel.fromJson(Map<String, dynamic> json) => TrackModel(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    artists: json['artists'] as String? ?? '',
    album: json['album'] as String? ?? '',
    cover: json['cover'] as String? ?? '',
    releaseDate: json['releaseDate'] as String? ?? '',
    sourceUrl: json['sourceUrl'] as String? ?? '',
    durationMs: json['durationMs'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artists': artists,
    'album': album,
    'cover': cover,
    'releaseDate': releaseDate,
    'sourceUrl': sourceUrl,
    'durationMs': durationMs,
  };

  /// Artwork URL to display for this track.
  ///
  /// Falls back to YouTube's own thumbnail for `yt_`-prefixed tracks: the flat
  /// yt-dlp search behind `/search-tracks` does not always return thumbnails,
  /// which left those rows (and the recently-played list) showing the blank
  /// note placeholder even though the artwork exists at a predictable URL.
  String get artwork {
    if (cover.isNotEmpty) return cover;
    if (id.startsWith('yt_')) {
      final videoId = id.substring(3);
      if (videoId.isNotEmpty) {
        return 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
      }
    }
    return '';
  }

  TrackModel copyWith({String? sourceUrl, int? durationMs}) => TrackModel(
    id: id,
    title: title,
    artists: artists,
    album: album,
    cover: cover,
    releaseDate: releaseDate,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    durationMs: durationMs ?? this.durationMs,
  );
}
