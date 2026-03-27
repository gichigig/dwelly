import 'package:flutter/material.dart';

class TelegramFragmentItem {
  final String id;
  final String label;
  final IconData icon;
  final int badgeCount;

  const TelegramFragmentItem({
    required this.id,
    required this.label,
    required this.icon,
    this.badgeCount = 0,
  });
}
