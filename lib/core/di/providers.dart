import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/rentals/data/memory_rentals_repo.dart';
import '../../features/rentals/data/rentals_repo.dart';
import '../../features/lost_id/data/lost_id_repo.dart';
import '../../features/lost_id/data/memory_lost_id_repo.dart';
import '../../features/notifications/data/memory_notifications_repo.dart';
import '../../features/notifications/data/notifications_repo.dart';
import '../services/rental_service.dart';

final rentalsRepoProvider = Provider<RentalsRepo>((ref) => MemoryRentalsRepo());
final lostIdRepoProvider = Provider<LostIdRepo>((ref) => MemoryLostIdRepo());
final notificationsRepoProvider =
    Provider<NotificationsRepo>((ref) => MemoryNotificationsRepo());

// Rental service provider wrapper
class RentalServiceWrapper {
  Future<List<dynamic>> getAll() => RentalService.getAll();
  Future<dynamic> getRentalById(int id) => RentalService.getById(id);
}

final rentalServiceProvider = Provider<RentalServiceWrapper>((ref) => RentalServiceWrapper());
