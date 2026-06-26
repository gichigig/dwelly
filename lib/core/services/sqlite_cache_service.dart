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
  static const int _dbVersion = 2;

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
  }

  static String generateSignature(RentalFilters? filters, int size) {
    if (filters == null) return 'default_$size';
    final params = <String, dynamic>{
      if (filters.area != null) 'area': filters.area,
      if (filters.constituency != null) 'constituency': filters.constituency,
      if (filters.minPrice != null) 'minPrice': filters.minPrice,
      if (filters.maxPrice != null) 'maxPrice': filters.maxPrice,
      if (filters.bedrooms != null) 'bedrooms': filters.bedrooms,
      if (filters.bathrooms != null) 'bathrooms': filters.bathrooms,
      if (filters.propertyType != null) 'propertyType': filters.propertyType,
      if (filters.expandedBedrooms != null) 'expandedBedrooms': filters.expandedBedrooms,
      if (filters.nearbyAreas != null) 'nearbyAreas': filters.nearbyAreas,
    };
    if (params.isEmpty) return 'default_$size';
    
    final sortedKeys = params.keys.toList()..sort();
    final sorted = <String, dynamic>{};
    for (final key in sortedKeys) {
      sorted[key] = params[key];
    }
    return 'filters_${jsonEncode(sorted)}_$size';
  }

  Future<void> savePaginatedFeed(String signature, int page, PaginatedRentals data) async {
    final db = await database;
    
    final payload = {
      'totalElements': data.totalElements,
      'totalPages': data.totalPages,
      'currentPage': data.currentPage,
      'hasMore': data.hasMore,
      'rentals': data.rentals.map((r) => r.toJson()).toList(),
    };

    await db.insert(
      'feed_cache',
      {
        'signature': signature,
        'page': page,
        'data': jsonEncode(payload),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<PaginatedRentals?> getPaginatedFeed(String signature, int page) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'feed_cache',
      where: 'signature = ? AND page = ?',
      whereArgs: [signature, page],
    );

    if (maps.isEmpty) return null;

    try {
      final dataStr = maps.first['data'] as String;
      final payload = jsonDecode(dataStr) as Map<String, dynamic>;
      
      final rentalsRaw = (payload['rentals'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>();
      final rentals = rentalsRaw.map(Rental.fromJson).toList();

      return PaginatedRentals(
        rentals: rentals,
        totalElements: payload['totalElements'] as int? ?? 0,
        totalPages: payload['totalPages'] as int? ?? 0,
        currentPage: payload['currentPage'] as int? ?? page,
        hasMore: payload['hasMore'] as bool? ?? false,
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> clearCache() async {
    final db = await database;
    await db.delete('feed_cache');
    await db.delete('chat_cache');
  }

  // --- Chat Cache Helpers ---

  Future<void> saveChatCache(String key, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'chat_cache',
      {
        'cache_key': key,
        'data': jsonEncode(data),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getChatCache(String key) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'chat_cache',
      where: 'cache_key = ?',
      whereArgs: [key],
    );
    if (maps.isEmpty) return null;
    try {
      final dataStr = maps.first['data'] as String;
      return jsonDecode(dataStr) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }
}
