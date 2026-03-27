import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/notifications_repo.dart';
import '../data/memory_notifications_repo.dart';
import '../domain/notification_model.dart';

final notificationsRepoProvider = Provider<NotificationsRepo>((ref) {
  return MemoryNotificationsRepo();
});

final notificationsProvider = FutureProvider<List<NotificationModel>>((ref) {
  return ref.watch(notificationsRepoProvider).getAll();
});

final unreadCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationsProvider);
  return notifications.when(
    data: (list) => list.where((n) => !n.isRead).length,
    loading: () => 0,
    error: (_, __) => 0,
  );
});

