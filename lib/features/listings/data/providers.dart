import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'memory_listings_repo.dart';
import 'listings_repo.dart';

final listingsRepoProvider = Provider<ListingsRepo>((ref) {
  return MemoryListingsRepo();
});
