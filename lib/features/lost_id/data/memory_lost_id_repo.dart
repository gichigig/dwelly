import '../domain/lost_id_item.dart';
import 'lost_id_repo.dart';

class MemoryLostIdRepo implements LostIdRepo {
  final List<LostIdItem> _db = [];

  @override
  Future<List<LostIdItem>> search(String? query) async {
    if (query == null || query.trim().isEmpty) {
      return _db.where((item) => !item.isClaimed).toList();
    }
    final q = query.toLowerCase();
    return _db.where((item) {
      if (item.isClaimed) return false;
      return item.name.toLowerCase().contains(q) ||
          item.idNumber.toLowerCase().contains(q) ||
          item.foundLocation.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Future<LostIdItem?> getById(String id) async {
    try {
      return _db.firstWhere((x) => x.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> add(LostIdItem item) async {
    _db.insert(0, item);
  }

  @override
  Future<void> markClaimed(String id) async {
    final idx = _db.indexWhere((x) => x.id == id);
    if (idx != -1) {
      _db[idx] = _db[idx].copyWith(isClaimed: true);
    }
  }
}

