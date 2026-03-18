import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/media_item.dart';
import 'log_service.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'video_downloader.db');

    LogService.i("Initializing database at $path");

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        LogService.i("Creating media_items table");
        return db.execute(
          '''
          CREATE TABLE media_items(
            id TEXT PRIMARY KEY,
            title TEXT,
            sourceUrl TEXT,
            localFilePath TEXT,
            thumbnailPath TEXT,
            duration TEXT,
            platformName TEXT,
            resolution TEXT,
            fileSize TEXT,
            description TEXT
          )
          ''',
        );
      },
    );
  }

  Future<void> insertMediaItem(MediaItem item) async {
    final db = await database;
    LogService.d("Inserting media item: ${item.title}");
    await db.insert(
      'media_items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MediaItem>> getAllMediaItems() async {
    final db = await database;
    LogService.d("Fetching all media items");
    final List<Map<String, dynamic>> maps = await db.query('media_items');
    return List.generate(maps.length, (i) {
      return MediaItem.fromMap(maps[i]);
    });
  }

  Future<void> deleteMediaItem(String id) async {
    final db = await database;
    LogService.w("Deleting media item with id: $id");
    await db.delete(
      'media_items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
