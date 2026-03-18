import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/download_manager_provider.dart';
import 'theme/premium_theme.dart';
import 'screens/video_downloader_home.dart';
import 'models/media_item.dart';
import 'screens/downloader_video_player_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DownloadManagerProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Premium Downloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6)),
        useMaterial3: true,
        extensions: const <ThemeExtension<dynamic>>[
          PremiumTheme.light,
        ],
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3B82F6), brightness: Brightness.dark),
        useMaterial3: true,
        extensions: const <ThemeExtension<dynamic>>[
          PremiumTheme.dark,
        ],
      ),
      themeMode: ThemeMode.system,
      home: const VideoDownloaderHome(),
    );
  }
}

class TestPlayerScreen extends StatefulWidget {
  const TestPlayerScreen({super.key});

  @override
  State<TestPlayerScreen> createState() => _TestPlayerScreenState();
}

class _TestPlayerScreenState extends State<TestPlayerScreen> {
  late List<MediaItem> _mockItems;

  @override
  void initState() {
    super.initState();
    // Some mock data to test the player
    _mockItems = [
      MediaItem(
        id: '1',
        title: 'Big Buck Bunny (Network)',
        sourceUrl:
            'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
        duration: '09:56',
        platformName: 'Direct MP4',
        description:
            'Big Buck Bunny tells the story of a giant rabbit with a heart bigger than himself.',
        resolution: '1080p',
        fileSize: '158 MB',
      ),
      MediaItem(
        id: '2',
        title: 'Elephant Dream (Network)',
        sourceUrl:
            'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
        duration: '10:53',
        platformName: 'Direct MP4',
        description: 'The first computer-generated animated short film.',
        resolution: '720p',
        fileSize: '85 MB',
      ),
      MediaItem(
        id: '3',
        title: 'Flutter Forward (YouTube)',
        sourceUrl: 'https://www.youtube.com/watch?v=zKQKGugkGz4',
        duration: 'Unknown',
        platformName: 'YouTube',
        description: 'Flutter Forward keynote.',
        resolution: 'Auto',
        fileSize: 'Stream',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Just wrap it in a scaffold so it can easily test out our player screen
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => DownloaderVideoPlayerScreen(
                  mediaItems: _mockItems,
                  playlistTitle: 'TEST PLAYLIST',
                  initialIndex: 0,
                  downloadProvider:
                      Provider.of<DownloadManagerProvider>(context, listen: false),
                ),
              ),
            );
          },
          child: const Text('Open Video Player'),
        ),
      ),
    );
  }
}
