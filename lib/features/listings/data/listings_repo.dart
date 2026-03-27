import '../domain/listing.dart';

class ListingsQuery {
  final String? county;
  final String? area;
  final UnitType? unitType;
  final int? minRent;
  final int? maxRent;

  const ListingsQuery({
    this.county,
    this.area,
    this.unitType,
    this.minRent,
    this.maxRent,
  });
}

abstract class ListingsRepo {
  Future<List<Listing>> search(ListingsQuery query);
  Future<Listing?> getById(String id);
  Future<void> add(Listing listing);
  Future<void> markTaken(String id, bool taken);
}
