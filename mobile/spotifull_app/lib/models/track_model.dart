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

  TrackModel copyWith({String? sourceUrl}) => TrackModel(
    id: id, title: title, artists: artists, album: album,
    cover: cover, releaseDate: releaseDate,
    sourceUrl: sourceUrl ?? this.sourceUrl, durationMs: durationMs,
  );
}
