import 'dart:io';

void main() {
  var file = File('lib/features/listings/presentation/map_explore_page.dart');
  var content = file.readAsStringSync();

  // 1. Update _loadRentals
  content = content.replaceAll(
    '''  Future<void> _loadRentals(double lat, double lng) async {
    try {
      final result = await RentalService.smartLocationSearch(
        latitude: lat,
        longitude: lng,
        sortByDistance: true,
        page: 0,
        size: 50,
      );
      if (mounted) {
        setState(() {
          _rentals = result.rentals.rentals;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }''',
    '''  Timer? _debounceTimer;

  Future<void> _loadRentals(double lat, double lng) async {
    try {
      final results = await RentalService.getMapRadarListings(lat, lng, radiusMeters: 1500);
      if (mounted) {
        setState(() {
          _rentals = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }'''
  );

  // 2. Update radarDistanceMeters
  content = content.replaceAll(
    'static const double radarDistanceMeters = 5000; // 5km',
    'static const double radarDistanceMeters = 1500; // 1.5km'
  );

  // 3. Update _isRentalInCone to return true (so all dots show in the circle)
  content = content.replaceAll(
    'return diff <= (radarAngleDegrees / 2);',
    'return true; // Show all dots in the circular radar'
  );

  // 4. Update MapOptions to use onPositionChanged
  content = content.replaceAll(
    '''              initialZoom: 14.0,
              onLongPress: (tapPosition, point) {''',
    '''              initialZoom: 14.0,
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && position.center != null) {
                  _debounceTimer?.cancel();
                  _debounceTimer = Timer(const Duration(milliseconds: 600), () {
                    if (mounted) {
                      setState(() {
                        _deviceLocation = DeviceLocationResult(
                          latitude: position.center!.latitude,
                          longitude: position.center!.longitude,
                          success: true,
                        );
                      });
                      _loadRentals(position.center!.latitude, position.center!.longitude);
                    }
                  });
                }
              },
              onLongPress: (tapPosition, point) {'''
  );

  // 5. Update _showRentalPreview to fetch details
  content = content.replaceAll(
    '''  void _showRentalPreview(Rental r) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {''',
    '''  void _showRentalPreview(Rental lightweightRental) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return FutureBuilder<Rental?>(
          future: RentalService.getById(lightweightRental.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                height: 200,
                child: const Center(child: CircularProgressIndicator()),
              );
            }
            final r = snapshot.data ?? lightweightRental;
            '''
  );

  // Add the closing brace for FutureBuilder
  content = content.replaceAll(
    '''                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }''',
    '''                  ],
                )
              ],
            ),
          ),
        );
          },
        );
      },
    );
  }'''
  );

  file.writeAsStringSync(content);
  print('Patched map explore page');
}
