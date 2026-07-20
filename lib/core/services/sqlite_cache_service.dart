import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/rental.dart';
import 'rental_service.dart';

class SqliteCacheService {
  SqliteCacheService._();
  static final SqliteCacheService instance = SqliteCacheService._();

  static Database? _database;
  static const String _dbName = 'dwelly_cache.db';
  static const int _dbVersion = 3;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _dbName);
    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE feed_cache(
        signature TEXT,
        page INTEGER,
        data TEXT,
        updated_at INTEGER,
        PRIMARY KEY (signature, page)
      )
    ''');
    await db.execute('''
      CREATE TABLE chat_cache(
        cache_key TEXT PRIMARY KEY,
        data TEXT,
        updated_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE feed_impressions(
        rental_id INTEGER PRIMARY KEY,
        impression_count INTEGER DEFAULT 0,
        session_count INTEGER DEFAULT 0,
        clicked INTEGER DEFAULT 0,
        suppressed INTEGER DEFAULT 0,
        last_seen_at INTEGER,
        clicked_at INTEGER,
        last_viewed_at INTEGER
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE chat_cache(
          cache_key TEXT PRIMARY KEY,
          data TEXT,
          updated_at INTEGER
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE feed_impressions(
          rental_id INTEGER PRIMARY KEY,
          impression_count INTEGER DEFAULT 0,
          session_count INTEGER DEFAULT 0,
          clicked INTEGER DEFAULT 0,
          suppressed INTEGER DEFAULT 0,
          last_seen_at INTEGER,
          clicked_at INTEGER,
          last_viewed_at INTEGER
        )
      ''');
    }
  }

  static String generateSignature(
    RentalFilters? filters,
    int size, {
    String? viewerKey,
  }) {
    final normalizedViewerKey = (viewerKey == null || viewerKey.trim().isEmpty)
        ? 'anon'
        : viewerKey.trim();
    if (filters == null) return 'default_${size}_$normalizedViewerKey';
    final params = <String, dynamic>{
      if (filters.area != null) 'area': filters.area,
      if (filters.constituency != null) 'constituency': filters.constituency,
      if (filters.minPrice != null) 'minPrice': filters.minPrice,
      if (filters.maxPrice != null) 'maxPrice': filters.maxPrice,
      if (filters.bedrooms != null) 'bedrooms': filters.bedrooms,
      if (filters.bathrooms != null) 'bathrooms': filters.bathrooms,
      if (filters.propertyType != null) 'propertyType': filters.propertyType,
      if (filters.expandedBedrooms != null)
        'expandedBedrooms': filters.expandedBedrooms,
      if (filters.nearbyAreas != null) 'nearbyAreas': filters.nearbyAreas,
    };
    if (params.isEmpty) return 'default_$size';

    final sortedKeys = params.keys.toList()..sort();
    final sorted = <String, dynamic>{};
    for (final key in sortedKeys) {
      sorted[key] = params[key];
    }
    return 'filters_${jsonEncode(sorted)}_${size}_$normalizedViewerKey';
  }

  Future<void> pruneFeedCache(
    String signature,
    int currentPage, {
    int window = 1,
  }) async {
    try {
      final db = await database;
      final minPage = currentPage - window;
      final maxPage = currentPage + window;
      await db.delete(
        'feed_cache',
        where: 'signature = ? AND (page < ? OR page > ?)',
        whereArgs: [signature, minPage, maxPage],
      );
    } catch (e) {
      print('[SqliteCache] pruneFeedCache failed safely: $e');
    }
  }

  Future<void> savePaginatedFeed(
    String signature,
    int page,
    PaginatedRentals data,
  ) async {
    try {
      final db = await database;

      final payload = {
        'totalElements': data.totalElements,
        'totalPages': data.totalPages,
        'currentPage': data.currentPage,
        'hasMore': data.hasMore,
        'rentals': data.rentals.map((r) => r.toJson()).toList(),
      };

      await db.insert('feed_cache', {
        'signature': signature,
        'page': page,
        'data': jsonEncode(payload),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Auto-prune to strictly maintain [previous 30, current 10, next 30] sliding window (window = 3 pages around current)
      await pruneFeedCache(signature, page, window: 3);
      await pruneOldSignatures();
    } catch (e) {
      print('[SqliteCache] savePaginatedFeed failed safely: $e');
    }
  }

  /// Automatically deletes old search/filter signatures across SQLite older than 3 days
  /// so stale past search results never accumulate over months.
  Future<void> pruneOldSignatures({
    Duration maxAge = const Duration(days: 3),
  }) async {
    try {
      final db = await database;
      final cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
      await db.delete(
        'feed_cache',
        where: 'updated_at < ?',
        whereArgs: [cutoff],
      );
    } catch (e) {
      print('[SqliteCache] pruneOldSignatures failed safely: $e');
    }
  }

  /// Scans active SQLite feed slices for a specific rental listing ID.
  /// Allows instant ($0ms) detail views even when completely offline and not opened before!
  Future<Rental?> getRentalFromFeedCache(int id) async {
    try {
      final db = await database;
      final maps = await db.query('feed_cache');
      for (final map in maps) {
        final dataStr = map['data'] as String?;
        if (dataStr == null) continue;
        final payload = jsonDecode(dataStr) as Map<String, dynamic>?;
        if (payload == null) continue;
        final rentalsRaw = (payload['rentals'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>();
        for (final rMap in rentalsRaw) {
          if (rMap['id'] == id || rMap['id'].toString() == id.toString()) {
            return Rental.fromJson(rMap);
          }
        }
      }
    } catch (e) {
      print('[SqliteCache] getRentalFromFeedCache failed safely: $e');
    }
    return null;
  }

  Future<PaginatedRentals?> getPaginatedFeed(String signature, int page) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'feed_cache',
        where: 'signature = ? AND page = ?',
        whereArgs: [signature, page],
      );

      if (maps.isEmpty) return null;

      final dataStr = maps.first['data'] as String;
      final payload = jsonDecode(dataStr) as Map<String, dynamic>;

      final rentalsRaw = (payload['rentals'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>();
      final rentals = rentalsRaw.map(Rental.fromJson).toList();

      return PaginatedRentals(
        rentals: rentals,
        totalElements: payload['totalElements'] as int? ?? 0,
        totalPages: payload['totalPages'] as int? ?? 0,
        currentPage: payload['currentPage'] as int? ?? page,
        hasMore: payload['hasMore'] as bool? ?? false,
      );
    } catch (e) {
      print('[SqliteCache] getPaginatedFeed failed safely: $e');
      return null;
    }
  }

  Future<void> clearCache() async {
    try {
      final db = await database;
      await db.delete('feed_cache');
      await db.delete('chat_cache');
    } catch (e) {
      print('[SqliteCache] clearCache failed safely: $e');
    }
  }

  // --- Chat Cache Helpers ---

  Future<void> saveChatCache(String key, Map<String, dynamic> data) async {
    try {
      final db = await database;
      await db.insert('chat_cache', {
        'cache_key': key,
        'data': jsonEncode(data),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      print('[SqliteCache] saveChatCache failed safely: $e');
    }
  }

  Future<Map<String, dynamic>?> getChatCache(String key) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'chat_cache',
        where: 'cache_key = ?',
        whereArgs: [key],
      );
      if (maps.isEmpty) return null;
      final dataStr = maps.first['data'] as String;
      return jsonDecode(dataStr) as Map<String, dynamic>;
    } catch (e) {
      print('[SqliteCache] getChatCache failed safely: $e');
      return null;
    }
  }

  Future<void> removeChatCache(String key) async {
    try {
      final db = await database;
      await db.delete('chat_cache', where: 'cache_key = ?', whereArgs: [key]);
    } catch (e) {
      print('[SqliteCache] removeChatCache failed safely: $e');
    }
  }
}
