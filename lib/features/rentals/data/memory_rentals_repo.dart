import '../domain/rental_filters.dart';
import '../domain/rental_listing.dart';
import 'rentals_repo.dart';

class MemoryRentalsRepo implements RentalsRepo {
  final List<RentalListing> _db = [];

  @override
  Future<void> add(RentalListing listing) async {
    _db.insert(0, listing);
  }

  @override
  Future<RentalListing?> getById(String id) async {
    try {
      return _db.firstWhere((x) => x.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<RentalListing>> search(RentalFilters filters) async {
    return _db.where((l) {
      // Check FYP terms if provided
      if (filters.fypTerms != null && filters.fypTerms!.isNotEmpty) {
        final hay = '${l.county} ${l.area} ${l.location}'.toLowerCase();
        final matchesFyp = filters.fypTerms!.any((term) => hay.contains(term.toLowerCase()));
        if (!matchesFyp) return false;
      } else {
        // Fall back to regular location query
        final q = (filters.locationQuery ?? '').trim().toLowerCase();
        if (q.isNotEmpty) {
          final hay = '${l.county} ${l.area}'.toLowerCase();
          if (!hay.contains(q)) return false;
        }
      }
      if (filters.unitType != null && l.unitType != filters.unitType) return false;
      if (filters.minPrice != null && l.rentKsh < filters.minPrice!) return false;
      if (filters.maxPrice != null && l.rentKsh > filters.maxPrice!) return false;
      return l.isActive;
    }).toList();
  }
}
