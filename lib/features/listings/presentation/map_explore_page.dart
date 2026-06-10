import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/models/rental.dart';
import '../../../core/services/device_location_service.dart';
import '../../../core/services/rental_service.dart';
import '../../../core/services/rental_service.dart';
import 'rental_detail_page.dart';

class MapExplorePage extends StatefulWidget {
  const MapExplorePage({super.key});

  @override
  State<MapExplorePage> createState() => _MapExplorePageState();
}

class _MapExplorePageState extends State<MapExplorePage> {
  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();
  
  List<Rental> _rentals = [];
  bool _isLoading = true;
  DeviceLocationResult? _deviceLocation;
  
  // Radar state
  bool _isRadarActive = false;
  double? _currentHeading;
  StreamSubscription<CompassEvent>? _compassSubscription;
  
  // Constants for the radar cone
  static const double radarDistanceMeters = 5000; // 5km
  static const double radarAngleDegrees = 60; // 30 degrees left/right

  @override
  void initState() {
    super.initState();
    _initMap();
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initMap() async {
    try {
      final loc = await DeviceLocationService.getCurrentLocation();
      if (loc.hasLocationData && mounted) {
        setState(() {
          _deviceLocation = loc;
        });
        await _loadRentals(loc.latitude!, loc.longitude!);
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRentals(double lat, double lng) async {
    try {
      // Load nearby rentals (using a large radius or smart location search)
      // For the radar to be impressive, we need a decent number of rentals around the user.
      final result = await RentalService.smartLocationSearch(
        latitude: lat,
        longitude: lng,
        sortByDistance: true,
        page: 0,
        size: 50, // fetch plenty for the radar
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
  }

  void _toggleRadar() {
    setState(() {
      _isRadarActive = !_isRadarActive;
      if (_isRadarActive) {
        _startCompass();
      } else {
        _stopCompass();
      }
    });
  }

  void _startCompass() {
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      if (event.heading != null) {
        setState(() {
          _currentHeading = event.heading;
        });
      }
    });
  }

  void _stopCompass() {
    _compassSubscription?.cancel();
    _compassSubscription = null;
    setState(() {
      _currentHeading = null;
    });
  }

  // --- Math Helpers for the Cone ---

  /// Calculate a destination coordinate given start lat/lng, distance (m) and bearing (deg)
  LatLng _calculateDestination(double lat, double lng, double distanceMeters, double bearingDeg) {
    const R = 6371e3; // Earth radius in meters
    final d = distanceMeters;
    
    final lat1 = lat * math.pi / 180;
    final lng1 = lng * math.pi / 180;
    final brng = bearingDeg * math.pi / 180;

    final lat2 = math.asin(
      math.sin(lat1) * math.cos(d / R) +
      math.cos(lat1) * math.sin(d / R) * math.cos(brng)
    );

    final lng2 = lng1 + math.atan2(
      math.sin(brng) * math.sin(d / R) * math.cos(lat1),
      math.cos(d / R) - math.sin(lat1) * math.sin(lat2)
    );

    return LatLng(lat2 * 180 / math.pi, lng2 * 180 / math.pi);
  }

  /// Check if a rental is inside the radar cone
  bool _isRentalInCone(Rental rental) {
    if (!_isRadarActive || _currentHeading == null || _deviceLocation == null) return true;
    if (rental.latitude == null || rental.longitude == null) return false;

    final devLat = _deviceLocation!.latitude!;
    final devLng = _deviceLocation!.longitude!;

    final distance = Geolocator.distanceBetween(
      devLat, devLng,
      rental.latitude!, rental.longitude!
    );

    if (distance > radarDistanceMeters) return false;

    final bearingToRental = Geolocator.bearingBetween(
      devLat, devLng,
      rental.latitude!, rental.longitude!
    );

    // Normalize bearings to 0-360
    var b1 = _currentHeading! % 360;
    if (b1 < 0) b1 += 360;
    
    var b2 = bearingToRental % 360;
    if (b2 < 0) b2 += 360;

    // Calculate shortest angular difference
    var diff = (b1 - b2).abs();
    if (diff > 180) diff = 360 - diff;

    // If within half the cone angle, it's inside
    return diff <= (radarAngleDegrees / 2);
  }

  // --- Map Rendering ---

  Set<Polygon> _buildPolygons() {
    if (!_isRadarActive || _currentHeading == null || _deviceLocation == null) return {};

    final lat = _deviceLocation!.latitude!;
    final lng = _deviceLocation!.longitude!;
    
    final leftBearing = _currentHeading! - (radarAngleDegrees / 2);
    final rightBearing = _currentHeading! + (radarAngleDegrees / 2);

    final pLeft = _calculateDestination(lat, lng, radarDistanceMeters, leftBearing);
    final pRight = _calculateDestination(lat, lng, radarDistanceMeters, rightBearing);
    // Add some intermediate points for a smooth curve (optional, but a triangle is fine for now)
    final pCenter = _calculateDestination(lat, lng, radarDistanceMeters, _currentHeading!);

    return {
      Polygon(
        polygonId: const PolygonId('radar_cone'),
        points: [
          LatLng(lat, lng),
          pLeft,
          pCenter,
          pRight,
        ],
        fillColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
        strokeColor: Theme.of(context).colorScheme.primary.withOpacity(0.5),
        strokeWidth: 2,
      )
    };
  }

  void _showRentalPreview(Rental r) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r.imageUrls.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 150,
                      width: double.infinity,
                      child: Image.network(
                        r.imageUrls.first,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  r.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'KES ${r.price}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context); // close bottom sheet
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => RentalDetailPage(rental: r))
                      );
                    },
                    child: const Text('View Full Details'),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Set<Marker> _buildMarkers() {
    return _rentals
        .where((r) => r.latitude != null && r.longitude != null)
        .where(_isRentalInCone)
        .map((r) {
          final isPremium = r.hasVideo == true; // Example rule: highlight premium
          
          return Marker(
            markerId: MarkerId(r.id.toString()),
            position: LatLng(r.latitude!, r.longitude!),
            onTap: () => _showRentalPreview(r),
            icon: isPremium ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow) : BitmapDescriptor.defaultMarker,
          );
        }).toSet();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_deviceLocation == null || !_deviceLocation!.hasLocationData) {
      return Scaffold(
        appBar: AppBar(title: const Text('Map Explore')),
        body: const Center(
          child: Text('Location permission is required to use the map.'),
        ),
      );
    }

    final initialPos = CameraPosition(
      target: LatLng(_deviceLocation!.latitude!, _deviceLocation!.longitude!),
      zoom: 14.0,
    );

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: initialPos,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            compassEnabled: false,
            zoomControlsEnabled: false,
            markers: _buildMarkers(),
            polygons: _buildPolygons(),
            onMapCreated: (controller) {
              _controller.complete(controller);
            },
          ),
          
          // Radar Overlay UI
          if (_isRadarActive && _currentHeading != null)
            Positioned(
              top: 60,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.radar, color: Colors.greenAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Radar Active: Heading ${_currentHeading!.toStringAsFixed(0)}°\nRevealing nearby rentals in your direction.',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
          // Back Button
          Positioned(
            top: 50,
            left: 16,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleRadar,
        backgroundColor: _isRadarActive ? Colors.redAccent : Theme.of(context).colorScheme.primary,
        icon: Icon(_isRadarActive ? Icons.stop : Icons.radar),
        label: Text(_isRadarActive ? 'Stop Radar' : 'Premium Radar'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
