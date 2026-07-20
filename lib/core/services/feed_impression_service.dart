import 'package:sqflite/sqflite.dart';
import 'sqlite_cache_service.dart';

/// Tracks per-listing feed impressions and clicks locally in SQLite.
///
/// This enables X/Twitter-style feed behaviour:
/// - Visually mark clicked listings ("Viewed ✓")
/// - Suppress listings scrolled past many times without clicking
/// - Suppress viewed/clicked listings after a higher threshold
/// - Recycle suppressed listings when fresh content runs out
class FeedImpressionService {
  static FeedImpressionService? _instance;
  late Database _db;

  /// Minimum gap (ms) between two impressions of the same listing
  /// to count as a separate session (5 minutes).
  static const int _sessionGapMs = 5 * 60 * 1000;

  /// Thresholds for UNCLICKED listings (scrolled past without tapping).
  static const int _suppressImpressionThreshold = 5;
  static const int _suppressSessionThreshold = 3;

  /// Thresholds for CLICKED/VIEWED listings (user already saw detail page).
  /// More lenient since the user showed interest, but still suppress eventually.
  static const int _viewedSuppressImpressionThreshold = 8;
  static const int _viewedSuppressSessionThreshold = 4;

  FeedImpressionService._();

  static Future<FeedImpressionService> getInstance() async {
    if (_instance != null) return _instance!;
    _instance = FeedImpressionService._();
    await _instance!._init();
    return _instance!;
  }

  Future<void> _init() async {
    _db = await SqliteCacheService.instance.database;
    try {
      await _db.execute(
        'ALTER TABLE feed_impressions ADD COLUMN last_viewed_at INTEGER',
      );
    } catch (_) {
      // Column already exists
    }
  }

  /// Record that a listing appeared in the user's viewport.
  ///
  /// Increments `impression_count`. If the last impression was more than
  /// [_sessionGapMs] ago, also increments `session_count`.
  Future<void> recordImpression(int rentalId) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    final existing = await _db.query(
      'feed_impressions',
      where: 'rental_id = ?',
      whereArgs: [rentalId],
      limit: 1,
    );

    if (existing.isEmpty) {
      await _db.insert('feed_impressions', {
        'rental_id': rentalId,
        'impression_count': 1,
        'session_count': 1,
        'clicked': 0,
        'suppressed': 0,
        'last_seen_at': now,
      });
    } else {
      final row = existing.first;
      final lastSeenAt = row['last_seen_at'] as int? ?? 0;
      final isNewSession = (now - lastSeenAt) > _sessionGapMs;

      await _db.update(
        'feed_impressions',
        {
          'impression_count': (row['impression_count'] as int? ?? 0) + 1,
          if (isNewSession)
            'session_count': (row['session_count'] as int? ?? 0) + 1,
          'last_seen_at': now,
        },
        where: 'rental_id = ?',
        whereArgs: [rentalId],
      );
    }
  }

  /// Record that the user meaningfully viewed a listing (tapped into detail OR dwelled >= 3.5s).
  Future<void> recordView(int rentalId) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    final existing = await _db.query(
      'feed_impressions',
      where: 'rental_id = ?',
      whereArgs: [rentalId],
      limit: 1,
    );

    if (existing.isEmpty) {
      await _db.insert('feed_impressions', {
        'rental_id': rentalId,
        'impression_count': 1,
        'session_count': 1,
        'clicked': 1,
        'suppressed': 0,
        'last_seen_at': now,
        'clicked_at': now,
        'last_viewed_at': now,
      });
    } else {
      await _db.update(
        'feed_impressions',
        {'clicked': 1, 'clicked_at': now, 'last_viewed_at': now},
        where: 'rental_id = ?',
        whereArgs: [rentalId],
      );
    }
  }

  /// Record that the user tapped into a listing's detail page.
  Future<void> recordClick(int rentalId) async {
    return recordView(rentalId);
  }

  /// Check whether a specific listing has been clicked.
  Future<bool> isClicked(int rentalId) async {
    final result = await _db.query(
      'feed_impressions',
      columns: ['clicked'],
      where: 'rental_id = ?',
      whereArgs: [rentalId],
      limit: 1,
    );
    if (result.isEmpty) return false;
    return (result.first['clicked'] as int? ?? 0) == 1;
  }

  /// Batch-fetch all clicked rental IDs.
  Future<Set<int>> getClickedIds() async {
    final result = await _db.query(
      'feed_impressions',
      columns: ['rental_id'],
      where: 'clicked = 1',
    );
    return result.map((row) => row['rental_id'] as int).toSet();
  }

  /// Batch-fetch timestamps when listings were last viewed or clicked.
  Future<Map<int, int>> getViewedTimestamps() async {
    final result = await _db.query(
      'feed_impressions',
      columns: ['rental_id', 'last_viewed_at', 'clicked_at'],
      where: 'clicked = 1 OR last_viewed_at IS NOT NULL',
    );
    final map = <int, int>{};
    for (final row in result) {
      final id = row['rental_id'] as int;
      final viewedAt =
          (row['last_viewed_at'] as int?) ?? (row['clicked_at'] as int?) ?? 0;
      if (viewedAt > 0) {
        map[id] = viewedAt;
      }
    }
    return map;
  }

  /// Get IDs of listings that should be suppressed from the primary feed.
  ///
  /// Two-tier suppression:
  /// 1. Unclicked listings: suppress after 5 impressions / 3 sessions
  /// 2. Clicked/viewed listings: suppress after 8 impressions / 4 sessions
  Future<Set<int>> getSuppressedIds() async {
    // Unclicked listings — stricter threshold
    final unclickedResult = await _db.query(
      'feed_impressions',
      columns: ['rental_id'],
      where: 'clicked = 0 AND impression_count >= ? AND session_count >= ?',
      whereArgs: [_suppressImpressionThreshold, _suppressSessionThreshold],
    );

    // Clicked/viewed listings — more lenient threshold
    final clickedResult = await _db.query(
      'feed_impressions',
      columns: ['rental_id'],
      where: 'clicked = 1 AND impression_count >= ? AND session_count >= ?',
      whereArgs: [
        _viewedSuppressImpressionThreshold,
        _viewedSuppressSessionThreshold,
      ],
    );

    final ids = <int>{};
    for (final row in unclickedResult) {
      ids.add(row['rental_id'] as int);
    }
    for (final row in clickedResult) {
      ids.add(row['rental_id'] as int);
    }
    return ids;
  }

  /// Reset suppression for ALL listings (both clicked and unclicked).
  /// Used when the feed is fully exhausted and we need to recycle
  /// previously hidden listings back into the feed.
  Future<void> unsuppressAll() async {
    await _db.update('feed_impressions', {
      'suppressed': 0,
      'impression_count': 0,
      'session_count': 0,
    });
  }

  /// Delete impression records older than [daysOld] days.
  Future<void> pruneOldEntries(int daysOld) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: daysOld))
        .millisecondsSinceEpoch;
    await _db.delete(
      'feed_impressions',
      where: 'last_seen_at < ?',
      whereArgs: [cutoff],
    );
  }
}
