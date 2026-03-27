import '../domain/notification_model.dart';
import 'notifications_repo.dart';

class MemoryNotificationsRepo implements NotificationsRepo {
  final List<NotificationModel> _db = [];

  @override
  Future<List<NotificationModel>> getAll() async {
    return List.from(_db);
  }

  @override
  Future<void> add(NotificationModel notification) async {
    _db.insert(0, notification);
  }

  @override
  Future<void> markAsRead(String id) async {
    final idx = _db.indexWhere((n) => n.id == id);
    if (idx != -1) {
      _db[idx] = _db[idx].copyWith(isRead: true);
    }
  }

  @override
  Future<void> markAllAsRead() async {
    for (var i = 0; i < _db.length; i++) {
      _db[i] = _db[i].copyWith(isRead: true);
    }
  }

  @override
  Future<void> delete(String id) async {
    _db.removeWhere((n) => n.id == id);
  }
}

