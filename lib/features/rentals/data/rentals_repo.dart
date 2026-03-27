import '../domain/rental_listing.dart';
import '../domain/rental_filters.dart';

abstract class RentalsRepo {
  Future<List<RentalListing>> search(RentalFilters filters);
  Future<RentalListing?> getById(String id);
  Future<void> add(RentalListing listing);
}
