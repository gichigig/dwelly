import '../domain/lost_id_item.dart';

abstract class LostIdRepo {
  Future<List<LostIdItem>> search(String? query);
  Future<LostIdItem?> getById(String id);
  Future<void> add(LostIdItem item);
  Future<void> markClaimed(String id);
}

