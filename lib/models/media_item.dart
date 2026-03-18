class MediaItem {
  final String id;
  final String title;
  final String sourceUrl;
  final String? localFilePath;
  final String? thumbnailPath;
  final String? duration; // e.g. "12:34"
  final String? platformName; // e.g. "YouTube", "Direct Link"

  // Additional metadata
  final String? resolution;
  final String? fileSize;
  final String? description;

  MediaItem({
    required this.id,
    required this.title,
    required this.sourceUrl,
    this.localFilePath,
    this.thumbnailPath,
    this.duration,
    this.platformName,
    this.resolution,
    this.fileSize,
    this.description,
  });

  MediaItem copyWith({
    String? id,
    String? title,
    String? sourceUrl,
    String? localFilePath,
    String? thumbnailPath,
    String? duration,
    String? platformName,
    String? resolution,
    String? fileSize,
    String? description,
  }) {
    return MediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      localFilePath: localFilePath ?? this.localFilePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      duration: duration ?? this.duration,
      platformName: platformName ?? this.platformName,
      resolution: resolution ?? this.resolution,
      fileSize: fileSize ?? this.fileSize,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'sourceUrl': sourceUrl,
      'localFilePath': localFilePath,
      'thumbnailPath': thumbnailPath,
      'duration': duration,
      'platformName': platformName,
      'resolution': resolution,
      'fileSize': fileSize,
      'description': description,
    };
  }

  factory MediaItem.fromMap(Map<String, dynamic> map) {
    return MediaItem(
      id: map['id'],
      title: map['title'],
      sourceUrl: map['sourceUrl'],
      localFilePath: map['localFilePath'],
      thumbnailPath: map['thumbnailPath'],
      duration: map['duration'],
      platformName: map['platformName'],
      resolution: map['resolution'],
      fileSize: map['fileSize'],
      description: map['description'],
    );
  }
}
