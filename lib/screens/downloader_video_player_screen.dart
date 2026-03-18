import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:video_player/video_player.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/media_item.dart';
import '../models/download_status.dart';
import '../providers/download_manager_provider.dart';
import '../services/log_service.dart';
import '../theme/premium_theme.dart';

class DownloaderVideoPlayerScreen extends StatefulWidget {
  final List<MediaItem> mediaItems;
  final String? playlistTitle;
  final DownloadManagerProvider downloadProvider;
  final int initialIndex;

  const DownloaderVideoPlayerScreen({
    super.key,
    required this.mediaItems,
    required this.downloadProvider,
    this.playlistTitle,
    required this.initialIndex,
  });

  @override
  State<DownloaderVideoPlayerScreen> createState() =>
      _DownloaderVideoPlayerScreenState();
}

class _DownloaderVideoPlayerScreenState
    extends State<DownloaderVideoPlayerScreen> {
  YoutubePlayerController? _youtubeController;
  VideoPlayerController? _localController;
  ChewieController? _chewieController;
  late int _currentIndex;
  late final List<MediaItem> _playableMedia;
  final Map<int, bool> _downloadedMap = {};

  bool _isFullScreen = false;

  // Visual feedback for seek
  bool _showSeekFeedback = false;
  bool _isForwardSeek = true;
  Timer? _seekFeedbackTimer;

  @override
  void initState() {
    super.initState();
    _playableMedia = widget.mediaItems.toList();

    _currentIndex = (widget.initialIndex >= 0 &&
            widget.initialIndex < _playableMedia.length)
        ? widget.initialIndex
        : 0;

    _checkDownloads();
    if (_playableMedia.isNotEmpty) {
      _initializePlayer(_currentIndex);
    }
    // Prevent screen from sleeping
    WakelockPlus.enable();

    // Lock to portrait initially unless in fullscreen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    LogService.i("Initialized Video Player Screen with ${_playableMedia.length} items");
  }

  Future<void> _checkDownloads() async {
    for (int i = 0; i < _playableMedia.length; i++) {
        final path = await widget.downloadProvider.getDownloadedFilePath(_playableMedia[i]);
        final bool isDownloaded = path != null && path.isNotEmpty;
        _downloadedMap[i] = isDownloaded;
    }
    if (mounted) setState(() {});
  }

  Future<void> _initializePlayer(int index) async {
    final MediaItem currentMedia = _playableMedia[index];
    final localPath = await widget.downloadProvider.getDownloadedFilePath(currentMedia);

    _localController?.dispose();
    _chewieController?.dispose();
    _localController = null;
    _chewieController = null;

    if (localPath != null && localPath.isNotEmpty) {
      // Local Playback
      _localController = VideoPlayerController.file(File(localPath));
    } else {
      // Network Playback
      final videoUrl = currentMedia.sourceUrl;
      final videoId = YoutubePlayer.convertUrlToId(videoUrl) ?? '';

      if (videoId.isNotEmpty) {
        if (_youtubeController == null) {
          _youtubeController = YoutubePlayerController(
            initialVideoId: videoId,
            flags: const YoutubePlayerFlags(autoPlay: true, mute: false),
          );
          _youtubeController!.addListener(() {
            if (_youtubeController!.value.isFullScreen != _isFullScreen) {
              setState(() {
                _isFullScreen = _youtubeController!.value.isFullScreen;
              });
            }
            if (mounted) setState(() {});
          });
        } else {
          _youtubeController!.load(videoId);
        }
        setState(() {});
        return;
      } else if (videoUrl.isNotEmpty) {
        _youtubeController?.dispose();
        _youtubeController = null;
        _localController =
            VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      }
    }

    if (_localController != null) {
      await _localController!.initialize();
      _setupChewie();
    }
    setState(() {});
  }

  void _setupChewie() {
    if (_localController == null) return;

    final theme = Theme.of(context);
    final premiumTheme = theme.extension<PremiumTheme>() ??
        (theme.brightness == Brightness.dark
            ? PremiumTheme.dark
            : PremiumTheme.light);

    _chewieController = ChewieController(
      videoPlayerController: _localController!,
      autoPlay: true,
      looping: false,
      aspectRatio: _localController!.value.aspectRatio,
      showControls: true,
      playbackSpeeds: [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0],
      deviceOrientationsOnEnterFullScreen: [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
      deviceOrientationsAfterFullScreen: [
        DeviceOrientation.portraitUp,
      ],
      materialProgressColors: ChewieProgressColors(
        playedColor: premiumTheme.primaryBlue,
        handleColor: premiumTheme.primaryBlue,
        bufferedColor: premiumTheme.textSecondary.withValues(alpha: 0.3),
        backgroundColor: premiumTheme.glassColor,
      ),
      allowFullScreen: true,
      allowMuting: true,
      allowPlaybackSpeedChanging: true,
    );

    _chewieController!.addListener(() {
      if (_chewieController!.isFullScreen != _isFullScreen) {
        setState(() {
          _isFullScreen = _chewieController!.isFullScreen;
        });
      }
    });
  }

  void _changeVideo(int index) async {
    if (_currentIndex == index) {
      if (_youtubeController != null) {
        _youtubeController!.value.isPlaying
            ? _youtubeController!.pause()
            : _youtubeController!.play();
      } else if (_localController != null) {
        _localController!.value.isPlaying
            ? _localController!.pause()
            : _localController!.play();
      }
      return;
    }
    _currentIndex = index;
    await _initializePlayer(index);
    setState(() {});
  }

  void _showSeekIndicator(bool isForward) {
    setState(() {
      _showSeekFeedback = true;
      _isForwardSeek = isForward;
    });
    _seekFeedbackTimer?.cancel();
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showSeekFeedback = false);
    });
  }

  @override
  void dispose() {
    _seekFeedbackTimer?.cancel();
    _youtubeController?.dispose();
    _localController?.dispose();
    _chewieController?.dispose();

    // Allow screen to sleep again
    WakelockPlus.disable();

    // Reset to app default orientations
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  YoutubePlayer _buildRawYoutubePlayer(PremiumTheme premiumTheme) {
    return YoutubePlayer(
      controller: _youtubeController!,
      showVideoProgressIndicator: true,
      progressIndicatorColor: premiumTheme.primaryBlue,
      onEnded: (metaData) {
        if (_currentIndex + 1 < _playableMedia.length) {
          _changeVideo(_currentIndex + 1);
        }
      },
    );
  }

  Widget _buildVideoPlayer(PremiumTheme premiumTheme, bool isLandscape) {
    final height = isLandscape
        ? MediaQuery.of(context).size.height
        : MediaQuery.of(context).size.width * (9 / 16);

    if (_playableMedia.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
            child: Text("No videos available",
                style: TextStyle(color: premiumTheme.textSecondary))),
      );
    }

    Widget playerWidget;

    if (_chewieController != null &&
        _chewieController!.videoPlayerController.value.isInitialized) {
      playerWidget = Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Chewie(controller: _chewieController!),

            // Double Tap to Seek Layer
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onDoubleTap: () {
                      final pos = _localController!.value.position;
                      _localController!
                          .seekTo(pos - const Duration(seconds: 5));
                      _showSeekIndicator(false);
                    },
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onDoubleTap: () {
                      final pos = _localController!.value.position;
                      _localController!
                          .seekTo(pos + const Duration(seconds: 5));
                      _showSeekIndicator(true);
                    },
                  ),
                ),
              ],
            ),

            // Visual Seek Feedback
            if (_showSeekFeedback)
              IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isForwardSeek
                            ? Icons.fast_forward_rounded
                            : Icons.fast_rewind_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isForwardSeek ? "+5s" : "-5s",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
                    .animate()
                    .scale(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut)
                    .fadeOut(delay: const Duration(milliseconds: 400)),
              ),
          ],
        ),
      );
    } else if (_youtubeController != null) {
      playerWidget = _buildRawYoutubePlayer(premiumTheme);
    } else {
      playerWidget = Container(
        color: Colors.black,
        child: Center(
            child: CircularProgressIndicator(color: premiumTheme.primaryBlue)),
      );
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: playerWidget,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final premiumTheme = theme.extension<PremiumTheme>() ?? PremiumTheme.dark;
    final isDark = theme.brightness == Brightness.dark;

    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    if (_playableMedia.isEmpty) {
      return Scaffold(
        backgroundColor: premiumTheme.scaffoldBg,
        body: Center(
          child: Text("No videos available",
              style: TextStyle(color: premiumTheme.textSecondary)),
        ),
      );
    }

    final currentMedia = _playableMedia[_currentIndex];

    Widget content = Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F172A) : const Color(0xFFF8F9FA),
      body: isLandscape
          ? Center(child: _buildVideoPlayer(premiumTheme, isLandscape))
          : SafeArea(
              child: Column(
                children: [
                  _buildCustomHeader(currentMedia, isDark, premiumTheme),
                  Expanded(
                    child: DefaultTabController(
                      length: 2, // Changed length to 2
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildVideoPlayer(premiumTheme, isLandscape),
                            _buildMediaMetadata(
                                currentMedia, isDark, premiumTheme),
                            _buildMediaTabs(currentMedia, isDark, premiumTheme),
                            SizedBox(
                              height: 480,
                              child: TabBarView(
                                children: [
                                  _buildQueueTab(currentMedia, premiumTheme),
                                  _buildVideoInfoTab(currentMedia, premiumTheme),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar:
          isLandscape ? null : _buildBottomNav(isDark, premiumTheme),
    );

    // YouTube requires wrapping the Scaffold in YoutubePlayerBuilder
    if (_youtubeController != null) {
      return YoutubePlayerBuilder(
        player: _buildRawYoutubePlayer(premiumTheme),
        builder: (context, player) {
          return Scaffold(
            backgroundColor: premiumTheme.scaffoldBg,
            body: isLandscape
                ? player
                : SafeArea(
                    child: Column(
                      children: [
                        _buildCustomHeader(currentMedia, isDark, premiumTheme),
                        Expanded(
                          child: DefaultTabController(
                            length: 2, // Changed length to 2
                            child: SingleChildScrollView(
                              physics: const ClampingScrollPhysics(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Stack(
                                    children: [
                                      SizedBox(
                                          width: double.infinity,
                                          height: MediaQuery.of(context)
                                                  .size
                                                  .width *
                                              (9 / 16),
                                          child: player),
                                      if (_downloadedMap[_currentIndex] == true)
                                        Positioned(
                                          top: 10,
                                          right: 10,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withAlpha(178), // 0.7 * 255
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                  color: Colors.greenAccent
                                                      .withAlpha(127)), // 0.5 * 255
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                    Icons.cloud_done_rounded,
                                                    color: Colors.greenAccent,
                                                    size: 14),
                                                const SizedBox(width: 6),
                                                Text(
                                                  "Offline Playback",
                                                  style: GoogleFonts.inter(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  _buildMediaMetadata(
                                      currentMedia, isDark, premiumTheme),
                                  _buildMediaTabs(
                                      currentMedia, isDark, premiumTheme),
                                  SizedBox(
                                    height: 500,
                                    child: TabBarView(
                                      children: [
                                        _buildQueueTab(currentMedia, premiumTheme),
                                        _buildVideoInfoTab(currentMedia, premiumTheme),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            bottomNavigationBar:
                isLandscape ? null : _buildBottomNav(isDark, premiumTheme),
          );
        },
      );
    }

    return content;
  }

  Widget _buildCustomHeader(
      MediaItem item, bool isDark, PremiumTheme premiumTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F172A).withAlpha(204)
            : Colors.white.withAlpha(204),
        border: Border(
          bottom: BorderSide(
              color:
                  isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.playlistTitle ?? "NOW PLAYING",
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: premiumTheme.primaryBlue,
                    letterSpacing: 2.0,
                  ),
                ),
                Text(
                  item.title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: premiumTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 48), // Balancing back button
        ],
      ),
    );
  }

  Widget _buildMediaMetadata(
      MediaItem item, bool isDark, PremiumTheme premiumTheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: isDark ? const Color(0xFF0F172A) : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: premiumTheme.primaryBlue.withAlpha(25),
                  border: Border.all(
                      color: premiumTheme.primaryBlue.withAlpha(25), width: 2),
                ),
                child: Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    color: premiumTheme.primaryBlue,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: premiumTheme.textPrimary,
                      ),
                    ),
                    Text(
                      item.platformName ?? "Direct Source",
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: premiumTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildDownloadBannerButton(item, premiumTheme),
        ],
      ),
    );
  }

  Widget _buildDownloadBannerButton(MediaItem item, PremiumTheme premiumTheme) {
    return ValueListenableBuilder<DownloadStatus>(
      valueListenable: widget.downloadProvider.getDownloadStatusNotifier(item.id),
      builder: (context, status, child) {
        String label = "Download Media";
        IconData icon = Icons.file_download_outlined;
        bool isDownloading = status == DownloadStatus.downloading;

        return ValueListenableBuilder<double>(
          valueListenable:
              widget.downloadProvider.getDownloadProgressNotifier(item.id),
          builder: (context, progress, _) {
            if (status == DownloadStatus.downloaded) {
              label = "Media Downloaded";
              icon = Icons.cloud_done_rounded;
            } else if (isDownloading) {
              final pct = (progress * 100).toInt();
              label = "Downloading ($pct%)...";
              icon = Icons.sync;
            }

            return InkWell(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Please download from the Home screen to select quality")),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: isDownloading
                      ? premiumTheme.primaryBlue.withAlpha(178)
                      : premiumTheme.primaryBlue,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: premiumTheme.primaryBlue.withAlpha(51),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isDownloading)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          value: progress > 0 ? progress : null,
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else
                      Icon(icon, color: Colors.white, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (isDownloading) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.close_rounded,
                          color: Colors.white70, size: 16),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMediaTabs(
      MediaItem item, bool isDark, PremiumTheme premiumTheme) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        border: Border(
          bottom: BorderSide(
              color:
                  isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
        ),
      ),
      child: TabBar(
        isScrollable: true,
        labelColor: premiumTheme.primaryBlue,
        unselectedLabelColor: premiumTheme.textSecondary,
        indicatorColor: premiumTheme.primaryBlue,
        indicatorWeight: 3,
        tabAlignment: TabAlignment.start,
        labelStyle:
            GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: "Queue / Downloads"),
          Tab(text: "Video Info"),
        ],
      ),
    );
  }

  Widget _buildVideoInfoTab(MediaItem item, PremiumTheme premiumTheme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (item.description != null && item.description!.isNotEmpty) ...[
          Text(
            "Description",
            style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: premiumTheme.textPrimary),
          ),
          const SizedBox(height: 12),
          Text(
            item.description!,
            style: GoogleFonts.inter(
                fontSize: 14, height: 1.6, color: premiumTheme.textSecondary),
          ),
          const SizedBox(height: 24),
        ],
        Text(
          "Metadata",
          style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: premiumTheme.textPrimary),
        ),
        const SizedBox(height: 12),
        _buildInfoRow("Resolution", item.resolution ?? "Unknown", premiumTheme),
        _buildInfoRow("File Size", item.fileSize ?? "Unknown", premiumTheme),
        _buildInfoRow("Duration", item.duration ?? "Unknown", premiumTheme),
        _buildInfoRow("Platform", item.platformName ?? "Direct", premiumTheme),
        _buildInfoRow("Source URL", item.sourceUrl, premiumTheme, isLink: true),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, PremiumTheme theme, {bool isLink = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isLink ? FontWeight.w500 : FontWeight.w600,
                color: isLink ? theme.primaryBlue : theme.textPrimary,
                decoration: isLink ? TextDecoration.underline : TextDecoration.none,
                decorationColor: theme.primaryBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueTab(MediaItem currentMedia, PremiumTheme premiumTheme) {
    return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        itemCount: _playableMedia.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final isSelected = index == _currentIndex;
          final queueItem = _playableMedia[index];

          return SizedBox(
              height: 90,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  color: isSelected
                      ? premiumTheme.glassColor
                      : premiumTheme.cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isSelected
                          ? premiumTheme.primaryBlue
                          : premiumTheme.glassBorder,
                      width: isSelected ? 1.5 : 0.5),
                  boxShadow: isSelected ? premiumTheme.glassShadow : [],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    splashColor: premiumTheme.primaryBlue.withAlpha(25),
                    onTap: () => _changeVideo(index),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          AnimatedScale(
                            duration: const Duration(milliseconds: 250),
                            scale: isSelected ? 1.1 : 1.0,
                            curve: Curves.easeInOut,
                            child: Icon(
                              isSelected
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_fill,
                              color: isSelected
                                  ? premiumTheme.primaryBlue
                                  : premiumTheme.textSecondary,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  queueItem.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    color: isSelected
                                        ? premiumTheme.textPrimary
                                        : premiumTheme.textSecondary,
                                  ),
                                ),
                                ValueListenableBuilder<DownloadStatus>(
                                  valueListenable: widget.downloadProvider.getDownloadStatusNotifier(queueItem.id),
                                  builder: (context, status, _) {
                                    if (status != DownloadStatus.downloaded) return const SizedBox.shrink();
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6.0),
                                      child: Row(
                                        children: [
                                          Icon(Icons.cloud_done_rounded,
                                              color: premiumTheme.primaryBlue,
                                              size: 18),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Downloaded',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: premiumTheme.primaryBlue,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                )
                              ],
                            ),
                          ),
                          _buildDownloadIconOnly(queueItem, premiumTheme),
                        ],
                      ),
                    ),
                  ),
                ),
              ));
        });
  }

  Widget _buildDownloadIconOnly(MediaItem item, PremiumTheme premiumTheme) {
    return ValueListenableBuilder<DownloadStatus>(
      valueListenable: widget.downloadProvider.getDownloadStatusNotifier(item.id),
      builder: (context, status, child) {
        if (status == DownloadStatus.downloading) {
          return ValueListenableBuilder<double>(
            valueListenable:
                widget.downloadProvider.getDownloadProgressNotifier(item.id),
            builder: (context, progress, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      value: progress > 0 ? progress : null,
                      strokeWidth: 2,
                      color: premiumTheme.primaryBlue,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 16, color: Colors.redAccent),
                    onPressed: () {
                      widget.downloadProvider.cancelDownload(item);
                    },
                  ),
                ],
              );
            },
          );
        } else if (status == DownloadStatus.downloaded) {
          return IconButton(
            icon: Icon(Icons.delete_outline, color: premiumTheme.textSecondary),
            onPressed: () {
              widget.downloadProvider.deleteDownload(item);
            },
          );
        } else {
          return IconButton(
            icon: Icon(Icons.download_for_offline_outlined,
                color: premiumTheme.textSecondary),
            onPressed: () {
              // Show message to download from home
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Please download from the Home screen to select quality")),
              );
            },
          );
        }
      },
    );
  }

  Widget _buildBottomNav(bool isDark, PremiumTheme premiumTheme) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F172A).withAlpha(204)
            : Colors.white.withAlpha(204),
        border: Border(
            top: BorderSide(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFE2E8F0))),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildFunctionalNavItem(
                  Icons.home_outlined, Icons.home, "Home", 0, premiumTheme),
              _buildFunctionalNavItem(Icons.download_done_rounded,
                  Icons.download, "Downloads", 1, premiumTheme),
              _buildFunctionalNavItem(Icons.settings_outlined, Icons.settings,
                  "Settings", 2, premiumTheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFunctionalNavItem(IconData icon, IconData activeIcon,
      String label, int index, PremiumTheme theme) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        // Placeholder for navigation
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: theme.textSecondary,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: theme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
