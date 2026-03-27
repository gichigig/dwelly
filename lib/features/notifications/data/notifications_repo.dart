import '../domain/notification_model.dart';

abstract class NotificationsRepo {
  Future<List<NotificationModel>> getAll();
  Future<void> add(NotificationModel notification);
  Future<void> markAsRead(String id);
  Future<void> markAllAsRead();
  Future<void> delete(String id);
}

