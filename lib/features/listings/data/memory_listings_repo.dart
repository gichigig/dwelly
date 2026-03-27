import '../domain/listing.dart';
import 'listings_repo.dart';

class MemoryListingsRepo implements ListingsRepo {
  final List<Listing> _db = [];

  @override
  Future<void> add(Listing listing) async {
    _db.insert(0, listing);
  }

  @override
  Future<Listing?> getById(String id) async {
    try {
      return _db.firstWhere((x) => x.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> markTaken(String id, bool taken) async {
    final idx = _db.indexWhere((x) => x.id == id);
    if (idx == -1) return;
    _db[idx] = _db[idx].copyWith(isTaken: taken);
  }

  @override
  Future<List<Listing>> search(ListingsQuery query) async {
    return _db.where((l) {
      if (query.county != null && query.county!.isNotEmpty) {
        if (l.county.toLowerCase() != query.county!.toLowerCase()) {
          return false;
        }
      }

      if (query.area != null && query.area!.isNotEmpty) {
        if (!l.area.toLowerCase().contains(query.area!.toLowerCase())) {
          return false;
        }
      }

      if (query.unitType != null) {
        if (l.unitType != query.unitType) return false;
      }

      if (query.minRent != null && l.rentKsh < query.minRent!) {
        return false;
      }

      if (query.maxRent != null && l.rentKsh > query.maxRent!) {
        return false;
      }

      return !l.isTaken;
    }).toList();
  }
}
