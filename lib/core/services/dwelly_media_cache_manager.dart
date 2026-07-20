import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class DwellyMediaCacheManager {
  DwellyMediaCacheManager._();

  static final CacheManager instance = CacheManager(
    Config(
      'dwellyMediaCacheV2',
      stalePeriod: const Duration(days: 14),
      maxNrOfCacheObjects: 250,
    ),
  );
}
