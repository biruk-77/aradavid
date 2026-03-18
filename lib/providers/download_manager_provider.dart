import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/fetched_media.dart';
import '../models/media_item.dart';
import '../models/download_status.dart';
import '../models/download_option.dart';
import '../services/database_service.dart';
import '../services/log_service.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloadManagerProvider extends ChangeNotifier {
  final Map<String, ValueNotifier<DownloadStatus>> _statusNotifiers = {};
  final Map<String, ValueNotifier<double>> _progressNotifiers = {};
  final Map<String, CancelToken> _cancelTokens = {};
  final YoutubeExplode _yt = YoutubeExplode();
  final Dio _dio = Dio();
  final DatabaseService _db = DatabaseService();

  // Previously downloaded or queued items
  List<MediaItem> _queue = [];
  List<MediaItem> get queue => _queue;

  DownloadManagerProvider() {
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    try {
      _queue = await _db.getAllMediaItems();
      for (var item in _queue) {
        if (item.localFilePath != null && File(item.localFilePath!).existsSync()) {
          getDownloadStatusNotifier(item.id).value = DownloadStatus.downloaded;
        }
      }
      LogService.i("Loaded ${_queue.length} items from database");
      notifyListeners();
    } catch (e) {
      LogService.e("Error loading queue from database", e);
    }
  }

  @override
  void dispose() {
    _yt.close();
    for (var token in _cancelTokens.values) {
      token.cancel("Provider disposed");
    }
    super.dispose();
  }

  void addToQueue(MediaItem item) async {
    if (!_queue.any((e) => e.id == item.id)) {
      _queue.add(item);
      await _db.insertMediaItem(item);
      LogService.d("Added to queue and persisted: ${item.title}");
      notifyListeners();
    }
  }

  ValueNotifier<DownloadStatus> getDownloadStatusNotifier(String mediaId) {
    _statusNotifiers.putIfAbsent(
        mediaId, () => ValueNotifier<DownloadStatus>(DownloadStatus.notDownloaded));
    return _statusNotifiers[mediaId]!;
  }

  ValueNotifier<double> getDownloadProgressNotifier(String mediaId) {
    _progressNotifiers.putIfAbsent(mediaId, () => ValueNotifier<double>(0.0));
    return _progressNotifiers[mediaId]!;
  }

  Future<FetchedMedia?> fetchVideoMetadata(String url) async {
    LogService.i("Fetching metadata for: $url");
    try {
      if (url.contains("tiktok.com")) {
        final data = await _callTikTokApi(url);
        return _parseTikTokMetadata(data, url);
      } else if (url.contains("instagram.com") || url.contains("instagr.am")) {
        final result = await fetchInstagramAll(url);
        return result.media;
      } else {
        // Assume YouTube
        final video = await _yt.videos.get(url);
        LogService.d("Fetched video: ${video.title}");
        return FetchedMedia(
          id: video.id.value,
          title: video.title,
          author: video.author,
          thumbnailUrl: video.thumbnails.highResUrl,
          url: url,
          platform: 'YouTube',
          duration: video.duration,
          description: video.description,
        );
      }
    } catch (e) {
      LogService.e("Error fetching metadata", e);
      throw Exception(e.toString().replaceAll("Exception: ", ""));
    }
  }
  // ========== TikTok: Single API call, cached result ==========
  Map<String, dynamic>? _cachedTikTokResponse;
  String? _cachedTikTokUrl;

  Future<Map<String, dynamic>> _callTikTokApi(String url, {int retryCount = 0}) async {
    // Return cached response if same URL
    if (_cachedTikTokUrl == url && _cachedTikTokResponse != null) {
      LogService.d("TikTok: Using cached API response");
      return _cachedTikTokResponse!;
    }

    LogService.i("TikTok: Calling tikwm API for: $url (attempt ${retryCount + 1})");
    final response = await http.post(
      Uri.parse('https://www.tikwm.com/api/'),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'Accept': 'application/json',
      },
      body: {'url': url, 'count': '12', 'cursor': '0', 'web': '1', 'hd': '1'},
    );

    LogService.i("TikTok API HTTP status: ${response.statusCode}");

    if (response.statusCode != 200) {
      throw Exception("TikTok API returned HTTP ${response.statusCode}");
    }

    final data = jsonDecode(response.body);
    final code = data['code'];
    final msg = data['msg'] ?? 'No message';
    LogService.i("TikTok API response code: $code (type: ${code.runtimeType}), msg: $msg");

    // Rate limited — retry after delay
    if (code == -1 && retryCount < 3) {
      LogService.w("TikTok: Rate limited, retrying in 2 seconds... (attempt ${retryCount + 1}/3)");
      await Future.delayed(const Duration(seconds: 2));
      return _callTikTokApi(url, retryCount: retryCount + 1);
    }

    // Success
    if (code == 0 || code == '0') {
      final info = data['data'];
      if (info != null && info is Map) {
        LogService.d("TikTok data keys: ${info.keys.toList()}");
        _cachedTikTokResponse = data;
        _cachedTikTokUrl = url;
        return data;
      }
    }

    LogService.e("TikTok API error - code: $code, msg: $msg");
    throw Exception("TikTok error: $msg (code: $code)");
  }

  FetchedMedia _parseTikTokMetadata(Map<String, dynamic> data, String url) {
    final info = data['data'];

    // Use origin_cover (TikTok CDN) instead of cover (tikwm CDN which 403s)
    String coverUrl = (info['origin_cover'] ?? info['ai_dynamic_cover'] ?? info['cover'] ?? '').toString();
    if (coverUrl.isNotEmpty && !coverUrl.startsWith('http')) {
      coverUrl = 'https://www.tikwm.com$coverUrl';
    }
    LogService.d("TikTok cover URL: $coverUrl");

    return FetchedMedia(
      id: info['id'].toString(),
      title: (info['title'] ?? 'TikTok Video').toString(),
      author: info['author']?['nickname']?.toString() ?? 'Unknown',
      thumbnailUrl: coverUrl,
      url: url,
      platform: 'TikTok',
    );
  }

  String _fixTikTokUrl(dynamic rawValue) {
    if (rawValue == null) return '';
    String rawUrl = rawValue.toString();
    if (rawUrl.isEmpty || rawUrl == 'null') return '';
    if (!rawUrl.startsWith('http')) return 'https://www.tikwm.com$rawUrl';
    return rawUrl;
  }

  List<DownloadOption> _parseTikTokOptions(Map<String, dynamic> data) {
    final info = data['data'];
    final options = <DownloadOption>[];

    // Log raw values for debugging
    LogService.d("TikTok raw URLs - play: ${info['play']}, hdplay: ${info['hdplay']}, wmplay: ${info['wmplay']}, music: ${info['music']}");

    final playUrl = _fixTikTokUrl(info['play']);
    final hdPlayUrl = _fixTikTokUrl(info['hdplay']);
    final wmPlayUrl = _fixTikTokUrl(info['wmplay']);
    final musicUrl = _fixTikTokUrl(info['music']);

    LogService.d("TikTok fixed URLs - play: '$playUrl', hd: '$hdPlayUrl', wm: '$wmPlayUrl', music: '$musicUrl'");

    if (playUrl.isNotEmpty) {
      options.add(DownloadOption(
        id: "${info['id']}_nowm",
        label: "Video (No Watermark)",
        quality: "SD",
        extension: "mp4",
        type: DownloadType.videoWithAudio,
        directUrl: playUrl,
      ));
    }
    if (hdPlayUrl.isNotEmpty) {
      options.add(DownloadOption(
        id: "${info['id']}_hd",
        label: "Video HD (No Watermark)",
        quality: "HD",
        extension: "mp4",
        type: DownloadType.videoWithAudio,
        directUrl: hdPlayUrl,
      ));
    }
    if (wmPlayUrl.isNotEmpty) {
      options.add(DownloadOption(
        id: "${info['id']}_wm",
        label: "Video (Watermark)",
        quality: "SD",
        extension: "mp4",
        type: DownloadType.videoWithAudio,
        directUrl: wmPlayUrl,
      ));
    }
    if (musicUrl.isNotEmpty) {
      options.add(DownloadOption(
        id: "${info['id']}_music",
        label: "Audio Only",
        quality: "128kbps",
        extension: "mp3",
        type: DownloadType.audioOnly,
        directUrl: musicUrl,
      ));
    }

    LogService.i("TikTok: Found ${options.length} download options");
    return options;
  }

  /// Fetches both metadata and options in a SINGLE API call for TikTok
  /// Get download options for YouTube URLs
  Future<List<DownloadOption>> getDownloadOptions(String url) async {
    LogService.i("Getting download options for: $url");
    try {
      final videoIdObj = VideoId.parseVideoId(url);
      if (videoIdObj == null) throw Exception("Invalid YouTube URL");
      final manifest = await _yt.videos.streamsClient.getManifest(videoIdObj);
      final options = <DownloadOption>[];

      for (final stream in manifest.muxed) {
        options.add(DownloadOption(
          id: "${videoIdObj}_muxed_${stream.qualityLabel}",
          label: "Video + Audio",
          quality: stream.qualityLabel,
          extension: "mp4",
          size: stream.size.toString(),
          type: DownloadType.videoWithAudio,
          streamInfo: stream,
        ));
      }

      for (final stream in manifest.audioOnly) {
        options.add(DownloadOption(
          id: "${videoIdObj}_audio_${stream.bitrate}",
          label: "Audio Only",
          quality: "${(stream.bitrate.bitsPerSecond / 1000).toInt()}kbps",
          extension: stream.container.name,
          size: stream.size.toString(),
          type: DownloadType.audioOnly,
          streamInfo: stream,
        ));
      }

      LogService.d("Found ${options.length} download options");
      return options;
    } catch (e) {
      LogService.e("Error getting options", e);
      return [];
    }
  }

  // ========== Instagram: Cobalt API integration ==========

  /// Fetches both metadata and options in a SINGLE API call for Instagram via Cobalt
  Future<({FetchedMedia media, List<DownloadOption> options})> fetchInstagramAll(String url) async {
    LogService.i("Instagram: Calling Cobalt API for: $url");
    try {
      final response = await http.post(
        Uri.parse('https://api.cobalt.tools/api/json'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        },
        body: jsonEncode({
          'url': url,
          'videoQuality': '1080',
        }),
      );

      if (response.statusCode != 200) {
        throw Exception("Cobalt API returned HTTP ${response.statusCode}");
      }

      final data = jsonDecode(response.body);
      final status = data['status'];

      if (status == 'error') {
        throw Exception("Cobalt error: ${data['text'] ?? 'Unknown error'}");
      }

      // 1. Extract Metadata
      String title = data['filename']?.toString() ?? 'Instagram Media';
      if (title.endsWith('.mp4') || title.endsWith('.jpg')) {
         title = title.substring(0, title.lastIndexOf('.'));
      }

      final media = FetchedMedia(
        id: "ig_${DateTime.now().millisecondsSinceEpoch}",
        title: title,
        author: 'Instagram User',
        thumbnailUrl: '', // Cobalt doesn't reliably return thumbnails
        url: url,
        platform: 'Instagram',
      );

      // 2. Extract Options
      final options = <DownloadOption>[];

      if (status == 'stream') {
        final downloadUrl = data['url'].toString();
        options.add(DownloadOption(
          id: "${media.id}_1080",
          label: "Video (High Quality)",
          quality: "1080p",
          extension: "mp4",
          type: DownloadType.videoWithAudio,
          directUrl: downloadUrl,
        ));
      } else if (status == 'picker') {
        final picker = data['picker'] as List;
        for (int i = 0; i < picker.length; i++) {
          final item = picker[i];
          final type = item['type']?.toString() ?? 'video';
          final itemUrl = item['url'].toString();
          
          options.add(DownloadOption(
            id: "${media.id}_$i",
            label: "${type[0].toUpperCase()}${type.substring(1)} Part ${i + 1}",
            quality: "Original",
            extension: type == 'video' ? "mp4" : "jpg",
            type: DownloadType.videoWithAudio,
            directUrl: itemUrl,
          ));
        }
      }

      return (media: media, options: options);
    } catch (e) {
      LogService.e("Instagram integration error", e);
      throw Exception("Instagram error: $e");
    }
  }

  /// Fetches both metadata and options in a SINGLE API call for TikTok
  Future<({FetchedMedia media, List<DownloadOption> options})> fetchTikTokAll(String url) async {
    final data = await _callTikTokApi(url);
    final media = _parseTikTokMetadata(data, url);
    final options = _parseTikTokOptions(data);
    return (media: media, options: options);
  }

  Future<void> startDownload(MediaItem item, DownloadOption option) async {
    LogService.i("Starting download for: ${item.title} (${option.quality})");
    final statusNotifier = getDownloadStatusNotifier(item.id);
    final progressNotifier = getDownloadProgressNotifier(item.id);

    if (statusNotifier.value == DownloadStatus.downloading) {
      LogService.w("Download already in progress for: ${item.id}");
      return;
    }

    statusNotifier.value = DownloadStatus.downloading;
    progressNotifier.value = 0.0;
    
    final cancelToken = CancelToken();
    _cancelTokens[item.id] = cancelToken;

    try {
      // Request Storage Permissions
      if (Platform.isAndroid) {
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
        
        // For Android 11+
        var manageStatus = await Permission.manageExternalStorage.status;
        if (!manageStatus.isGranted) {
           manageStatus = await Permission.manageExternalStorage.request();
        }

        if (!status.isGranted && !manageStatus.isGranted) {
          LogService.e("Storage permission denied.", Exception("Permission Denied"));
          statusNotifier.value = DownloadStatus.failed;
          return;
        }
      }

      Directory? saveDir;
      if (Platform.isAndroid) {
        saveDir = Directory('/storage/emulated/0/Download');
        if (!await saveDir.exists()) {
          saveDir = await getExternalStorageDirectory();
        }
      } else {
        saveDir = await getApplicationDocumentsDirectory();
      }
      
      final finalDir = Directory('${saveDir!.path}/PremiumDownloader');
      if (!await finalDir.exists()) {
        await finalDir.create(recursive: true);
      }

      final fileName = "${item.title.replaceAll(RegExp(r'[^\w\s\-]'), '')}_${option.quality}.${option.extension}";
      final savePath = "${finalDir.path}/$fileName";

      LogService.d("Saving to: $savePath");

      final downloadUrl = option.directUrl ?? option.streamInfo.url.toString();

      // Build headers — add Referer for tikwm URLs (required to avoid 403)
      final headers = <String, dynamic>{
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
      };
      if (downloadUrl.contains('tikwm.com')) {
        headers['Referer'] = 'https://www.tikwm.com/';
      }

      await _dio.download(
        downloadUrl,
        savePath,
        cancelToken: cancelToken,
        options: Options(headers: headers),
        onReceiveProgress: (received, total) {
          if (total != -1) {
             final progress = received / total;
             progressNotifier.value = progress;
          }
        },
      );

      final downloadedItem = item.copyWith(
        localFilePath: savePath,
        resolution: option.quality,
        fileSize: option.size,
      );

      statusNotifier.value = DownloadStatus.downloaded;
      addToQueue(downloadedItem);
      LogService.i("Download complete: ${item.title}");
    } catch (e) {
      if (CancelToken.isCancel(e as DioException)) {
        LogService.w("Download cancelled: ${item.id}");
      } else {
        LogService.e("Download error for: ${item.id}", e);
        statusNotifier.value = DownloadStatus.failed;
      }
      progressNotifier.value = 0.0;
    } finally {
      _cancelTokens.remove(item.id);
    }
  }

  void cancelDownload(MediaItem item) {
    LogService.w("Cancelling download: ${item.id}");
    final token = _cancelTokens[item.id];
    if (token != null) {
      token.cancel("User cancelled");
    }
    
    final statusNotifier = getDownloadStatusNotifier(item.id);
    final progressNotifier = getDownloadProgressNotifier(item.id);

    statusNotifier.value = DownloadStatus.notDownloaded;
    progressNotifier.value = 0.0;
  }

  Future<void> deleteDownload(MediaItem item) async {
    LogService.w("Deleting download: ${item.title}");
    final statusNotifier = getDownloadStatusNotifier(item.id);
    final progressNotifier = getDownloadProgressNotifier(item.id);

    if (item.localFilePath != null) {
      final file = File(item.localFilePath!);
      if (await file.exists()) {
        await file.delete();
        LogService.d("Deleted file: ${item.localFilePath}");
      }
    }

    await _db.deleteMediaItem(item.id);
    statusNotifier.value = DownloadStatus.notDownloaded;
    progressNotifier.value = 0.0;
    _queue.removeWhere((e) => e.id == item.id);
    notifyListeners();
  }

  Future<String?> getDownloadedFilePath(MediaItem item) async {
    final statusNotifier = getDownloadStatusNotifier(item.id);
    if (statusNotifier.value == DownloadStatus.downloaded) {
      return item.localFilePath;
    }
    return null;
  }

  // Stats for Dashboard
  int get totalDownloads => _queue.where((item) => item.localFilePath != null).length;

  String get totalSpaceSaved {
    double totalBytes = 0;
    for (var item in _queue) {
      if (item.fileSize != null) {
        // Simple heuristic to extract bytes from size string (e.g., "12.5 MB")
        final parts = item.fileSize!.split(' ');
        if (parts.length >= 2) {
          double value = double.tryParse(parts[0]) ?? 0;
          String unit = parts[1].toUpperCase();
          if (unit.contains('KB')) {
            totalBytes += value * 1024;
          } else if (unit.contains('MB')) {
            totalBytes += value * 1024 * 1024;
          } else if (unit.contains('GB')) {
            totalBytes += value * 1024 * 1024 * 1024;
          } else {
            totalBytes += value;
          }
        }
      }
    }
    
    if (totalBytes < 1024 * 1024) return "${(totalBytes / 1024).toStringAsFixed(1)} KB";
    if (totalBytes < 1024 * 1024 * 1024) return "${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    return "${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB";
  }
}

