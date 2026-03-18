import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/fetched_media.dart';
import '../models/media_item.dart';
import '../models/download_option.dart';
import '../models/download_status.dart';
import '../providers/download_manager_provider.dart';
import '../theme/premium_theme.dart';
import '../services/log_service.dart';
import 'downloader_video_player_screen.dart';

class VideoDownloaderHome extends StatefulWidget {
  const VideoDownloaderHome({super.key});

  @override
  State<VideoDownloaderHome> createState() => _VideoDownloaderHomeState();
}

class _VideoDownloaderHomeState extends State<VideoDownloaderHome> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false;
  FetchedMedia? _fetchedMedia;
  List<DownloadOption> _options = [];
  String? _error;

  Future<void> _fetchVideoInfo() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    LogService.i("User requested analysis for: $url");
    setState(() {
      _isLoading = true;
      _error = null;
      _fetchedMedia = null;
      _options = [];
    });

    final provider = context.read<DownloadManagerProvider>();
    
    try {
      if (url.contains("tiktok.com")) {
        // TikTok: Single API call returns both metadata + options
        final result = await provider.fetchTikTokAll(url);
        setState(() {
          _isLoading = false;
          _fetchedMedia = result.media;
          _options = result.options;
        });
      } else if (url.contains("instagram.com") || url.contains("instagr.am")) {
        // Instagram: Cobalt returns metadata + options
        final result = await provider.fetchInstagramAll(url);
        setState(() {
          _isLoading = false;
          _fetchedMedia = result.media;
          _options = result.options;
        });
      } else {
        // YouTube / others: Parallelize fetching for speed
        final results = await Future.wait([
          provider.fetchVideoMetadata(url),
          provider.getDownloadOptions(url),
        ]);

        final video = results[0] as FetchedMedia?;
        final options = results[1] as List<DownloadOption>?;

        if (video == null) {
          LogService.w("Failed to fetch video info for: $url");
          setState(() {
            _isLoading = false;
            _error = "Could not fetch video info. Please check the URL.";
          });
          return;
        }

        setState(() {
          _isLoading = false;
          _fetchedMedia = video;
          _options = options ?? [];
        });
      }
    } catch (e) {
      LogService.e("General error in _fetchVideoInfo", e);
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceAll("Exception: ", "");
      });
    }
  }


  void _startDownload(DownloadOption option) {
    if (_fetchedMedia == null) return;
    LogService.i("User selected option: ${option.label} (${option.quality})");

    final theme = Theme.of(context);
    final premiumTheme = theme.extension<PremiumTheme>() ?? PremiumTheme.dark;

    final mediaItem = MediaItem(
      id: option.id,
      title: _fetchedMedia!.title,
      sourceUrl: _urlController.text.trim(),
      thumbnailPath: _fetchedMedia!.thumbnailUrl,
      duration: _fetchedMedia!.duration?.toString() ?? "00:00",
      platformName: _fetchedMedia!.platform,
      description: _fetchedMedia!.description,
    );

    context.read<DownloadManagerProvider>().startDownload(mediaItem, option);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Downloading: ${mediaItem.title} (${option.quality})"),
        backgroundColor: premiumTheme.primaryBlue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  int _bottomNavIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final premiumTheme = theme.extension<PremiumTheme>() ?? PremiumTheme.dark;

    return Scaffold(
      backgroundColor: premiumTheme.scaffoldBg,
      bottomNavigationBar: _buildBottomNav(premiumTheme),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.8, -0.6),
              radius: 1.2,
              colors: [
                premiumTheme.primaryBlue.withAlpha(15),
                premiumTheme.scaffoldBg,
              ],
            ),
          ),
          child: IndexedStack(
            index: _bottomNavIndex,
            children: [
              _buildHomeTab(premiumTheme),
              _buildLibraryTab(premiumTheme),
              _buildTrendsTab(premiumTheme),
              _buildSettingsTab(premiumTheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeTab(PremiumTheme premiumTheme) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            _buildTopBar(premiumTheme),
            
            const SizedBox(height: 32),
            _buildDashboard(premiumTheme),

            const SizedBox(height: 40),
            Text(
              "Download Media",
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: premiumTheme.textPrimary,
              ),
            ).animate().fadeIn(duration: 600.ms).slideX(begin: -0.1),
            
            const SizedBox(height: 20),
            _buildUrlInput(premiumTheme),
            
            const SizedBox(height: 16),
            _buildAnalyzeButton(premiumTheme),
            
            if (_error != null) ...[
              const SizedBox(height: 20),
              _buildErrorBox(_error!),
            ],

            if (_fetchedMedia != null) ...[
              const SizedBox(height: 32),
              _buildFetchedVideoCard(premiumTheme),
              const SizedBox(height: 24),
              _buildIntegratedOptionsList(premiumTheme),
            ],

            const SizedBox(height: 40),
            _buildDiscoverySection(premiumTheme),

            const SizedBox(height: 48),
            _buildHistorySection(premiumTheme, isHome: true),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildLibraryTab(PremiumTheme premiumTheme) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            _buildHistorySection(premiumTheme, isHome: false),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendsTab(PremiumTheme premiumTheme) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text(
              "Trending NOW",
              style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w900, color: premiumTheme.textPrimary),
            ),
            const SizedBox(height: 32),
            _buildDiscoverySection(premiumTheme),
            const SizedBox(height: 64),
            Center(
              child: Column(
                children: [
                  Icon(Icons.local_fire_department_rounded, size: 64, color: Colors.orangeAccent.withAlpha(150)),
                  const SizedBox(height: 16),
                  Text(
                    "Trending videos will appear here soon!",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: premiumTheme.textSecondary),
                  ),
                ],
              ).animate().fadeIn(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTab(PremiumTheme premiumTheme) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text(
              "Settings",
              style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w900, color: premiumTheme.textPrimary),
            ),
            const SizedBox(height: 32),
            _buildSettingsToggle(premiumTheme, "Dark Mode", Icons.dark_mode_rounded, true, (val) {}),
            const SizedBox(height: 16),
            _buildSettingsButton(premiumTheme, "Clear Download History", Icons.delete_sweep_rounded, Colors.redAccent, () async {
                final provider = context.read<DownloadManagerProvider>();
                if (provider.queue.isEmpty) return;
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: premiumTheme.scaffoldBg,
                    title: Text("Clear History?", style: TextStyle(color: premiumTheme.textPrimary)),
                    content: Text("This will remove all downloaded files and records.", style: TextStyle(color: premiumTheme.textSecondary)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                      TextButton(onPressed: () async {
                        Navigator.pop(ctx);
                        final items = provider.queue.toList();
                        for (var item in items) {
                          await provider.deleteDownload(item);
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: const Text("History cleared!"),
                            backgroundColor: premiumTheme.primaryBlue,
                          ));
                        }
                      }, child: const Text("Clear", style: TextStyle(color: Colors.redAccent))),
                    ],
                  )
                );
            }),
            const SizedBox(height: 16),
            _buildSettingsButton(premiumTheme, "About Developer", Icons.person_rounded, premiumTheme.primaryBlue, () {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text("Built with ❤️ using Flutter & AI"),
                  backgroundColor: premiumTheme.primaryBlue,
               ));
            }),
          ]
        )
      )
    );
  }

  Widget _buildSettingsToggle(PremiumTheme premiumTheme, String title, IconData icon, bool value, Function(bool) onChanged) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: premiumTheme.glassColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: premiumTheme.primaryBlue.withAlpha(25)),
      ),
      child: Row(
        children: [
           Icon(icon, color: premiumTheme.primaryBlue),
           const SizedBox(width: 16),
           Expanded(child: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: premiumTheme.textPrimary))),
           Switch(
             value: value,
             onChanged: onChanged,
             activeThumbColor: premiumTheme.primaryBlue,
             trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
           ),
        ]
      )
    );
  }

  Widget _buildSettingsButton(PremiumTheme premiumTheme, String title, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: premiumTheme.glassColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: premiumTheme.primaryBlue.withAlpha(25)),
        ),
        child: Row(
          children: [
             Icon(icon, color: color),
             const SizedBox(width: 16),
             Expanded(child: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: premiumTheme.textPrimary))),
             Icon(Icons.chevron_right_rounded, color: premiumTheme.textSecondary),
          ]
        )
      ),
    );
  }

  Widget _buildTopBar(PremiumTheme premiumTheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Welcome back,",
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: premiumTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                "Premium User",
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: premiumTheme.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        _buildHeroHeader(premiumTheme),
      ],
    );
  }

  Widget _buildDashboard(PremiumTheme premiumTheme) {
    return Consumer<DownloadManagerProvider>(
      builder: (context, provider, _) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                premiumTheme.primaryBlue,
                premiumTheme.primaryBlue.withBlue(255).withGreen(150),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: premiumTheme.primaryBlue.withAlpha(76),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Overview",
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withAlpha(204),
                    ),
                  ),
                  const Icon(Icons.analytics_outlined, color: Colors.white70),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  _buildStatItem("Downloads", provider.totalDownloads.toString(), Icons.cloud_download_rounded),
                  const SizedBox(width: 40),
                  _buildStatItem("Space Saved", provider.totalSpaceSaved, Icons.storage_rounded),
                ],
              ),
            ],
          ),
        ).animate().fadeIn(duration: 800.ms).scale(begin: const Offset(0.95, 0.95));
      },
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white.withAlpha(178),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildDiscoverySection(PremiumTheme premiumTheme) {
    final categories = ["Music", "Shorts", "Movies", "Podcasts", "Kids"];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Quick Categories",
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: premiumTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text("Category: ${categories[index]} (Trending Soon!)"),
                    backgroundColor: premiumTheme.primaryBlue,
                    behavior: SnackBarBehavior.floating,
                  ));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: premiumTheme.glassColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: premiumTheme.primaryBlue.withAlpha(25)),
                ),
                alignment: Alignment.center,
                  child: Text(
                    categories[index],
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: premiumTheme.textPrimary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ).animate().fadeIn(delay: 400.ms);
  }

  Widget _buildBottomNav(PremiumTheme premiumTheme) {
    return Container(
      decoration: BoxDecoration(
        color: premiumTheme.scaffoldBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _bottomNavIndex,
        onTap: (idx) => setState(() => _bottomNavIndex = idx),
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: premiumTheme.primaryBlue,
        unselectedItemColor: premiumTheme.textSecondary,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.library_books_rounded), label: "Library"),
          BottomNavigationBarItem(icon: Icon(Icons.trending_up_rounded), label: "Trends"),
          BottomNavigationBarItem(icon: Icon(Icons.settings_suggest_rounded), label: "Settings"),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(PremiumTheme premiumTheme) {
    return Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: premiumTheme.primaryBlue.withAlpha(25),
              border: Border.all(color: premiumTheme.primaryBlue.withAlpha(51), width: 2),
            ),
            child: const Text(
              "🚀",
              style: TextStyle(fontSize: 48),
            ),
          ).animate().scale(duration: 800.ms, curve: Curves.elasticOut),
          const SizedBox(height: 16),
          Text(
            "PREMIUM DOWNLOADER",
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: premiumTheme.primaryBlue,
              letterSpacing: 4.0,
            ),
          ).animate().fadeIn(delay: 400.ms),
        ],
      ),
    );
  }

  Widget _buildUrlInput(PremiumTheme premiumTheme) {
    return Container(
      decoration: BoxDecoration(
        color: premiumTheme.glassColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: premiumTheme.primaryBlue.withAlpha(51)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.link_rounded, color: premiumTheme.primaryBlue),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _urlController,
              style: GoogleFonts.inter(color: premiumTheme.textPrimary),
              decoration: InputDecoration(
                hintText: "Paste link (YT, TikTok, Instagram)...",
                hintStyle: GoogleFonts.inter(color: premiumTheme.textSecondary.withAlpha(127)),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _fetchVideoInfo(),
            ),
          ),
          if (_urlController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_rounded, size: 20),
              onPressed: () => setState(() => _urlController.clear()),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 600.ms, delay: 200.ms).slideY(begin: 0.2);
  }

  Widget _buildAnalyzeButton(PremiumTheme premiumTheme) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _fetchVideoInfo,
        style: ElevatedButton.styleFrom(
          backgroundColor: premiumTheme.primaryBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: _isLoading 
          ? const SizedBox(
              width: 24, 
              height: 24, 
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
            )
          : Text(
              "Analyze Video",
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16),
            ),
      ),
    ).animate().fadeIn(duration: 600.ms, delay: 300.ms).slideY(begin: 0.2);
  }

  Widget _buildErrorBox(String msg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withAlpha(51)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              msg,
              style: GoogleFonts.inter(color: Colors.red, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ).animate().shake();
  }

  Widget _buildFetchedVideoCard(PremiumTheme premiumTheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: premiumTheme.glassColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: premiumTheme.primaryBlue.withAlpha(25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              _fetchedMedia!.thumbnailUrl,
              width: 100,
              height: 100,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: premiumTheme.glassColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.video_library_rounded, color: premiumTheme.primaryBlue, size: 40),
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fetchedMedia!.title,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: premiumTheme.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _fetchedMedia!.author,
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
    ).animate().fadeIn().scale(begin: const Offset(0.9, 0.9));
  }

  Widget _buildIntegratedOptionsList(PremiumTheme premiumTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.file_download_outlined, size: 20, color: Colors.blueAccent),
            const SizedBox(width: 8),
            Text(
              "Download Options",
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: premiumTheme.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _options.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final option = _options[index];
            final isAudio = option.type == DownloadType.audioOnly;
            
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: premiumTheme.glassColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isAudio ? Colors.orange.withAlpha(51) : premiumTheme.primaryBlue.withAlpha(51)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isAudio ? Colors.orange.withAlpha(25) : premiumTheme.primaryBlue.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isAudio ? Icons.music_note_rounded : Icons.video_library_rounded,
                      color: isAudio ? Colors.orange : premiumTheme.primaryBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.label,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            color: premiumTheme.textPrimary,
                          ),
                        ),
                        Text(
                          "${option.quality} • ${option.size ?? 'Unknown size'}",
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: premiumTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildDownloadButton(option, premiumTheme),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDownloadButton(DownloadOption option, PremiumTheme premiumTheme) {
    final provider = context.watch<DownloadManagerProvider>();
    final statusNotifier = provider.getDownloadStatusNotifier(option.id);
    final progressNotifier = provider.getDownloadProgressNotifier(option.id);

    return ValueListenableBuilder<DownloadStatus>(
      valueListenable: statusNotifier,
      builder: (context, status, _) {
        if (status == DownloadStatus.downloading) {
          return ValueListenableBuilder<double>(
            valueListenable: progressNotifier,
            builder: (context, progress, _) {
              final pct = (progress * 100).toInt();
              return SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      backgroundColor: premiumTheme.primaryBlue.withAlpha(25),
                      color: premiumTheme.primaryBlue,
                      strokeWidth: 4,
                    ).animate(onPlay: (controller) => controller.repeat()).shimmer(duration: 2.seconds),
                    Text(
                      "$pct%",
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: premiumTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        }

        if (status == DownloadStatus.downloaded) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.greenAccent.withAlpha(51)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline_rounded, size: 16, color: Colors.greenAccent),
                const SizedBox(width: 4),
                Text(
                  "Saved",
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.greenAccent,
                  ),
                ),
              ],
            ),
          );
        }

        return ElevatedButton(
          onPressed: () => _startDownload(option),
          style: ElevatedButton.styleFrom(
            backgroundColor: option.type == DownloadType.audioOnly ? Colors.orange : premiumTheme.primaryBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            elevation: 0,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.download_rounded, size: 16),
              SizedBox(width: 4),
              Text("Download", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistorySection(PremiumTheme premiumTheme, {bool isHome = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.history_rounded, size: 20, color: Colors.greenAccent),
                const SizedBox(width: 8),
                Text(
                  isHome ? "Recent Downloads" : "Download History",
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: premiumTheme.textPrimary,
                  ),
                ),
              ],
            ),
            if (isHome)
              TextButton(
                onPressed: () {
                  setState(() => _bottomNavIndex = 1);
                },
                child: Text("View All", style: TextStyle(color: premiumTheme.primaryBlue)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Consumer<DownloadManagerProvider>(
          builder: (context, provider, child) {
            if (provider.queue.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    "No downloads yet",
                    style: TextStyle(color: premiumTheme.textSecondary, fontStyle: FontStyle.italic),
                  ),
                ),
              );
            }
            // If isHome is true, show only the 3 most recent downloads
            final reversedQueue = provider.queue.reversed.toList();
            final displayQueue = isHome ? reversedQueue.take(3).toList() : reversedQueue;
            
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayQueue.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final item = displayQueue[index];
                return _buildHistoryListItem(item, provider, premiumTheme);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildHistoryListItem(MediaItem item, DownloadManagerProvider provider, PremiumTheme premiumTheme) {
    final statusNotifier = provider.getDownloadStatusNotifier(item.id);
    final progressNotifier = provider.getDownloadProgressNotifier(item.id);

    return Container(
      decoration: BoxDecoration(
        color: premiumTheme.glassColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: premiumTheme.glassBorder),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: item.thumbnailPath != null 
                  ? Image.network(item.thumbnailPath!, width: 64, height: 64, fit: BoxFit.cover)
                  : Container(width: 64, height: 64, color: Colors.grey.withAlpha(51)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: premiumTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.resolution ?? "Processing...",
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: premiumTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<DownloadStatus>(
                valueListenable: statusNotifier,
                builder: (context, status, _) {
                  if (status == DownloadStatus.downloaded) {
                    return IconButton(
                      icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.greenAccent, size: 28),
                      onPressed: () {
                         final idx = provider.queue.indexOf(item);
                         Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => DownloaderVideoPlayerScreen(
                              mediaItems: provider.queue,
                              downloadProvider: provider,
                              initialIndex: idx,
                            ),
                          ),
                        );
                      },
                    );
                  }
                  if (status == DownloadStatus.downloading) {
                     return IconButton(
                       icon: const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 24),
                       onPressed: () => provider.cancelDownload(item),
                     );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
          ValueListenableBuilder<DownloadStatus>(
            valueListenable: statusNotifier,
            builder: (context, status, _) {
              if (status == DownloadStatus.downloading) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Column(
                    children: [
                      ValueListenableBuilder<double>(
                        valueListenable: progressNotifier,
                        builder: (context, progress, _) {
                          final pct = (progress * 100).toInt();
                          return Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("Downloading...", style: GoogleFonts.inter(fontSize: 11, color: premiumTheme.textSecondary)),
                                  Text("$pct%", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w900, color: premiumTheme.primaryBlue)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: progress,
                                backgroundColor: premiumTheme.primaryBlue.withAlpha(25),
                                color: premiumTheme.primaryBlue,
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }
}

// Global dynamic helpers to match user code patterns if they exist
dynamic roundedRectangleCircular(double r) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
const boxCover = BoxFit.cover;
