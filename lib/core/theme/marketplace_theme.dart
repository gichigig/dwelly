import 'package:flutter/material.dart';

class MarketplaceGradients {
  static Gradient hero(ColorScheme scheme) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        scheme.primary.withValues(alpha: 0.22),
        scheme.secondary.withValues(alpha: 0.2),
        scheme.tertiary.withValues(alpha: 0.18),
      ],
    );
  }

  static Gradient sectionHeader(ColorScheme scheme) {
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        scheme.primary.withValues(alpha: 0.14),
        scheme.secondary.withValues(alpha: 0.1),
      ],
    );
  }

  static Gradient cardAccent(ColorScheme scheme) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        scheme.primary.withValues(alpha: 0.16),
        scheme.primary.withValues(alpha: 0.02),
      ],
    );
  }

  static Gradient cta(ColorScheme scheme) {
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [scheme.primary, scheme.secondary],
    );
  }
}
