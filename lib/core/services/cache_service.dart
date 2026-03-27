/// Generic in-memory cache with TTL support for API responses.
/// Reduces redundant network calls for frequently accessed data.
class CacheEntry<T> {
  final T data;
  final DateTime cachedAt;
  final Duration ttl;

  CacheEntry({
    required this.data,
    required this.ttl,
  }) : cachedAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(cachedAt) > ttl;
  bool get isValid => !isExpired;
}

/// LRU-style in-memory cache with configurable TTL and max size.
class MemoryCache<T> {
  final Duration ttl;
  final int maxSize;
  final Map<String, CacheEntry<T>> _cache = {};

  MemoryCache({
    required this.ttl,
    this.maxSize = 100,
  });

  /// Get cached value if valid, or null if expired/missing.
  T? get(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _cache.remove(key);
      return null;
    }
    return entry.data;
  }

  /// Store a value in cache.
  void set(String key, T value) {
    // Evict oldest entries if at capacity
    if (_cache.length >= maxSize && !_cache.containsKey(key)) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }
    _cache[key] = CacheEntry(data: value, ttl: ttl);
  }

  /// Remove a specific key.
  void remove(String key) => _cache.remove(key);

  /// Clear all cached entries.
  void clear() => _cache.clear();

  /// Check if a valid (non-expired) entry exists.
  bool has(String key) {
    final entry = _cache[key];
    if (entry == null) return false;
    if (entry.isExpired) {
      _cache.remove(key);
      return false;
    }
    return true;
  }

  int get size => _cache.length;
}

/// Singleton cache manager for the app.
/// Provides named caches for different data types.
class CacheManager {
  CacheManager._();

  /// Clear all caches (e.g. on logout).
  static void clearAll() {
    savedRentalIds.clear();
    savedRentals.clear();
    rentalById.clear();
    popularAreas.clear();
    areaSearch.clear();
    conversations.clear();
  }

  // --- Saved Rentals ---
  /// Cached set of saved rental IDs — avoids re-fetching on every explore page load.
  static final _savedIdsCache = _SingleValueCache<Set<int>>(
    ttl: const Duration(minutes: 10),
  );
  static _SingleValueCache<Set<int>> get savedRentalIds => _savedIdsCache;

  /// Cached full saved rentals list.
  static final _savedRentalsCache = _SingleValueCache<List<dynamic>>(
    ttl: const Duration(minutes: 5),
  );
  static _SingleValueCache<List<dynamic>> get savedRentals => _savedRentalsCache;

  // --- Rentals ---
  /// LRU cache for individual rental lookups by ID.
  static final rentalById = MemoryCache<dynamic>(
    ttl: const Duration(minutes: 5),
    maxSize: 50,
  );

  /// Cached popular areas (rarely changes).
  static final popularAreas = MemoryCache<List<dynamic>>(
    ttl: const Duration(minutes: 30),
    maxSize: 10,
  );

  /// LRU cache for area search autocomplete results.
  static final areaSearch = MemoryCache<List<dynamic>>(
    ttl: const Duration(minutes: 10),
    maxSize: 30,
  );

  // --- Conversations ---
  /// Cached conversations list for inbox.
  static final _conversationsCache = _SingleValueCache<List<dynamic>>(
    ttl: const Duration(minutes: 1),
  );
  static _SingleValueCache<List<dynamic>> get conversations => _conversationsCache;
}

/// Cache for a single value (not keyed), with TTL.
class _SingleValueCache<T> {
  final Duration ttl;
  CacheEntry<T>? _entry;

  _SingleValueCache({required this.ttl});

  T? get value {
    if (_entry == null || _entry!.isExpired) {
      _entry = null;
      return null;
    }
    return _entry!.data;
  }

  void set(T data) {
    _entry = CacheEntry(data: data, ttl: ttl);
  }

  void clear() => _entry = null;

  bool get hasValid => _entry != null && _entry!.isValid;
}
