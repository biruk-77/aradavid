class FetchedMedia {
  final String id;
  final String title;
  final String author;
  final String thumbnailUrl;
  final Duration? duration;
  final String url;
  final String platform; // e.g. "YouTube", "TikTok", "Instagram"
  final String? description;

  FetchedMedia({
    required this.id,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    required this.url,
    required this.platform,
    this.duration,
    this.description,
  });
}
