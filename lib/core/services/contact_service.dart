import 'dart:convert';
import 'api_service.dart';
import 'auth_service.dart';
import 'package:flutter/foundation.dart';

class SavedContact {
  final int id;
  final int contactUserId;
  final String customName;
  final String? defaultUsername;
  final String? defaultFirstName;
  final String? defaultLastName;
  final String? avatarUrl;

  SavedContact({
    required this.id,
    required this.contactUserId,
    required this.customName,
    this.defaultUsername,
    this.defaultFirstName,
    this.defaultLastName,
    this.avatarUrl,
  });

  factory SavedContact.fromJson(Map<String, dynamic> json) {
    return SavedContact(
      id: json['id'],
      contactUserId: json['contactUserId'],
      customName: json['customName'],
      defaultUsername: json['defaultUsername'],
      defaultFirstName: json['defaultFirstName'],
      defaultLastName: json['defaultLastName'],
      avatarUrl: json['avatarUrl'],
    );
  }
}

class ContactService {
  static final ValueNotifier<List<SavedContact>> contacts = ValueNotifier([]);
  static final Map<int, SavedContact> _contactMap = {};

  static Future<void> loadContacts() async {
    if (!AuthService.isLoggedIn) return;

    try {
      final response = await ApiService.timedGet(
        Uri.parse('${ApiService.baseUrl}/contacts'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final loadedContacts = data
            .map((json) => SavedContact.fromJson(json))
            .toList();
        contacts.value = loadedContacts;

        _contactMap.clear();
        for (var contact in loadedContacts) {
          _contactMap[contact.contactUserId] = contact;
        }
      }
    } catch (e) {
      debugPrint('Error loading contacts: $e');
    }
  }

  static Future<SavedContact?> saveContact({
    required int userId,
    required String customName,
    String? username,
  }) async {
    try {
      final response = await ApiService.timedPost(
        Uri.parse('${ApiService.baseUrl}/contacts'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${AuthService.token}',
        },
        body: json.encode({'contactUserId': userId, 'customName': customName}),
      );

      if (response.statusCode == 200) {
        final newContact = SavedContact.fromJson(json.decode(response.body));

        // Update local state
        final current = List<SavedContact>.from(contacts.value);
        final index = current.indexWhere((c) => c.contactUserId == userId);
        if (index >= 0) {
          current[index] = newContact;
        } else {
          current.add(newContact);
        }
        contacts.value = current;
        _contactMap[userId] = newContact;

        return newContact;
      }
    } catch (e) {
      debugPrint('Error saving contact: $e');
    }
    return null;
  }

  static String getDisplayName(
    int userId,
    String? fallbackName, {
    String? username,
  }) {
    final contact = _contactMap[userId];
    if (contact != null) {
      return contact.customName;
    }
    if (fallbackName != null && fallbackName.isNotEmpty) {
      return fallbackName;
    }
    if (username != null && username.isNotEmpty) {
      return '@$username';
    }
    return 'User $userId';
  }
}
