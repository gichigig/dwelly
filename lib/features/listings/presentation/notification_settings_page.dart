import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../../../core/services/notification_preferences_service.dart';
import '../../../core/services/notification_service.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _loading = true;
  bool _saving = false;
  NotificationPreferences _preferences = const NotificationPreferences();
  NotificationSettings? _permissionSettings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final prefs = await NotificationPreferencesService.syncFromServer();
      final permission = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (!mounted) return;
      setState(() {
        _preferences = prefs;
        _permissionSettings = permission;
        _loading = false;
      });
    } catch (_) {
      final cached = await NotificationPreferencesService.getCachedOrDefault();
      if (!mounted) return;
      setState(() {
        _preferences = cached;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = await NotificationPreferencesService.updateServer(
        _preferences,
      );
      await NotificationService.syncPreferences();
      if (!mounted) return;
      setState(() {
        _preferences = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification settings saved')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _pickTime({required bool start}) async {
    final initial =
        _parseTime(
          start ? _preferences.quietHoursStart : _preferences.quietHoursEnd,
        ) ??
        TimeOfDay.now();
    final selected = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (selected == null) return;
    final formatted = _timeToString(selected);
    setState(() {
      _preferences = _preferences.copyWith(
        quietHoursStart: start ? formatted : _preferences.quietHoursStart,
        quietHoursEnd: start ? _preferences.quietHoursEnd : formatted,
      );
    });
  }

  String _permissionLabel() {
    final status = _permissionSettings?.authorizationStatus;
    switch (status) {
      case AuthorizationStatus.authorized:
        return 'Allowed';
      case AuthorizationStatus.provisional:
        return 'Provisional';
      case AuthorizationStatus.denied:
        return 'Denied';
      case AuthorizationStatus.notDetermined:
      default:
        return 'Not decided';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: const Text('Permission status'),
                    subtitle: Text(_permissionLabel()),
                    trailing: TextButton(
                      onPressed: () async {
                        await FirebaseMessaging.instance.requestPermission(
                          alert: true,
                          badge: true,
                          sound: true,
                        );
                        await _load();
                      },
                      child: const Text('Request'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _preferences.pushEnabled,
                  title: const Text('Push notifications'),
                  subtitle: const Text(
                    'Master switch for all push notifications',
                  ),
                  onChanged: (value) {
                    setState(() {
                      _preferences = _preferences.copyWith(pushEnabled: value);
                    });
                  },
                ),
                SwitchListTile(
                  value: _preferences.rentalAlertsEnabled,
                  title: const Text('Rental alerts'),
                  subtitle: const Text('New matching rental notifications'),
                  onChanged: (value) {
                    setState(() {
                      _preferences = _preferences.copyWith(
                        rentalAlertsEnabled: value,
                      );
                    });
                  },
                ),
                SwitchListTile(
                  value: _preferences.messageEnabled,
                  title: const Text('Message alerts'),
                  subtitle: const Text('New chat message notifications'),
                  onChanged: (value) {
                    setState(() {
                      _preferences = _preferences.copyWith(
                        messageEnabled: value,
                      );
                    });
                  },
                ),
                SwitchListTile(
                  value: _preferences.reportUpdatesEnabled,
                  title: const Text('Report updates'),
                  subtitle: const Text('Moderation updates on your reports'),
                  onChanged: (value) {
                    setState(() {
                      _preferences = _preferences.copyWith(
                        reportUpdatesEnabled: value,
                      );
                    });
                  },
                ),
                SwitchListTile(
                  value: _preferences.emailEnabled,
                  title: const Text('Email notifications'),
                  subtitle: const Text('Allow email notification delivery'),
                  onChanged: (value) {
                    setState(() {
                      _preferences = _preferences.copyWith(emailEnabled: value);
                    });
                  },
                ),
                SwitchListTile(
                  value: _preferences.marketingEnabled,
                  title: const Text('Marketing notifications'),
                  subtitle: const Text('Promotions and feature announcements'),
                  onChanged: (value) {
                    setState(() {
                      _preferences = _preferences.copyWith(
                        marketingEnabled: value,
                      );
                    });
                  },
                ),
                const Divider(height: 32),
                const Text(
                  'Quiet Hours',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bedtime_outlined),
                  title: const Text('Start'),
                  subtitle: Text(_preferences.quietHoursStart ?? 'Not set'),
                  trailing: TextButton(
                    onPressed: () => _pickTime(start: true),
                    child: const Text('Set'),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.wb_sunny_outlined),
                  title: const Text('End'),
                  subtitle: Text(_preferences.quietHoursEnd ?? 'Not set'),
                  trailing: TextButton(
                    onPressed: () => _pickTime(start: false),
                    child: const Text('Set'),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _preferences = NotificationPreferences(
                        pushEnabled: _preferences.pushEnabled,
                        rentalAlertsEnabled: _preferences.rentalAlertsEnabled,
                        messageEnabled: _preferences.messageEnabled,
                        reportUpdatesEnabled: _preferences.reportUpdatesEnabled,
                        emailEnabled: _preferences.emailEnabled,
                        marketingEnabled: _preferences.marketingEnabled,
                        timezone: _preferences.timezone,
                      );
                    });
                  },
                  child: const Text('Clear quiet hours'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save settings'),
                  ),
                ),
              ],
            ),
    );
  }

  TimeOfDay? _parseTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _timeToString(TimeOfDay value) {
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
}
