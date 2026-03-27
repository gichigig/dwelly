import 'package:flutter/material.dart';

import '../../../core/navigation/app_tab_navigator.dart';
import '../../../core/services/app_notification_center.dart';
import '../domain/notification_model.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: AppNotificationCenter.unreadCount,
            builder: (context, unreadCount, _) {
              if (unreadCount <= 0) return const SizedBox.shrink();
              return TextButton(
                onPressed: AppNotificationCenter.markAllAsRead,
                child: const Text('Mark all read'),
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<List<NotificationModel>>(
        valueListenable: AppNotificationCenter.notifications,
        builder: (context, list, _) {
          if (list.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final notification = list[index];
              return Dismissible(
                key: ValueKey(notification.id),
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                direction: DismissDirection.endToStart,
                onDismissed: (_) =>
                    AppNotificationCenter.delete(notification.id),
                child: ListTile(
                  leading: Icon(
                    notification.isRead
                        ? Icons.notifications_outlined
                        : Icons.notifications_active,
                    color: notification.isRead
                        ? Colors.grey
                        : Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(notification.title),
                  subtitle: Text(notification.message),
                  trailing: Text(
                    _formatTime(notification.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  onTap: () => _openNotification(context, notification),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openNotification(BuildContext context, NotificationModel notification) {
    AppNotificationCenter.markAsRead(notification.id);

    switch (notification.targetRoute) {
      case '/inbox':
        AppTabNavigator.openTab(2);
        Navigator.of(context).pop();
        break;
      case '/account':
        AppTabNavigator.openTab(3);
        Navigator.of(context).pop();
        break;
      default:
        break;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}
