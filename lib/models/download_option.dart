// import 'package:youtube_explode_dart/youtube_explode_dart.dart';

enum DownloadType { videoWithAudio, videoOnly, audioOnly }

class DownloadOption {
  final String id;
  final String label;
  final String quality;
  final String extension;
  final String? size;
  final DownloadType type;
  final dynamic streamInfo; // Can be Youtube's StreamInfo
  final String? directUrl; // Used for TikTok, Instagram direct MP4 links

  DownloadOption({
    required this.id,
    required this.label,
    required this.quality,
    required this.extension,
    this.size,
    required this.type,
    this.streamInfo,
    this.directUrl,
  });
}
