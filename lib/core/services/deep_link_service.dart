import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/rental.dart';
import 'api_service.dart';
import 'notification_service.dart';
import '../../features/listings/presentation/rental_detail_page.dart';
import 'package:realestate/core/widgets/dwelly_orbiting_loader.dart';

class DeepLinkService extends WidgetsBindingObserver {
  static final DeepLinkService instance = DeepLinkService._internal();
  DeepLinkService._internal();

  bool _initialized = false;
  String? _lastHandledLink;

  static void init() {
    if (instance._initialized) return;
    instance._initialized = true;
    WidgetsBinding.instance.addObserver(instance);

    // Check initial route / cold start link
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initialRoute = PlatformDispatcher.instance.defaultRouteName;
      if (initialRoute.isNotEmpty && initialRoute != '/') {
        instance._handleLinkString(initialRoute);
      }
    });
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final location = routeInformation.uri.toString();
    if (location.isNotEmpty && location != '/') {
      _handleLinkString(location);
    }
    return super.didPushRouteInformation(routeInformation);
  }

  void _handleLinkString(String link) {
    if (link == _lastHandledLink) return;
    _lastHandledLink = link;

    debugPrint('DeepLinkService: Processing link -> $link');

    // Match https://ishinadwelly.com/listing/123 or dwelly://listing/123 or intent://listing/123
    final listingMatch = RegExp(r'listing/(\d+)').firstMatch(link);
    if (listingMatch != null) {
      final idStr = listingMatch.group(1);
      if (idStr != null && idStr.isNotEmpty) {
        debugPrint('DeepLinkService: Extracted listing ID -> $idStr');
        navigateToListingById(idStr);
      }
    }
  }

  static Future<void> navigateToListingById(String idStr) async {
    final navigator = NotificationService.navigatorKey.currentState;
    if (navigator == null) {
      // Retry shortly if navigator isn't mounted yet
      Future.delayed(
        const Duration(milliseconds: 600),
        () => navigateToListingById(idStr),
      );
      return;
    }

    final context = navigator.context;

    // Show loading indicator dialog while fetching the full rental details
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DwellyOrbitingLoader(),
                SizedBox(height: 16),
                Text(
                  'Opening listing...',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final response = await ApiService.timedGet(
        Uri.parse('${ApiService.baseUrl}/rentals/$idStr'),
      );

      if (navigator.mounted) {
        Navigator.pop(context); // close loading dialog
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rental = Rental.fromJson(data);
        if (navigator.mounted) {
          navigator.push(
            MaterialPageRoute(builder: (_) => RentalDetailPage(rental: rental)),
          );
        }
      } else {
        if (navigator.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not open listing. It may have been removed.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (navigator.mounted) {
        Navigator.pop(context); // close loading dialog
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading listing: $e')));
      }
    }
  }
}
