import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/models/rental.dart';
import '../../../core/services/device_location_service.dart';
import '../../../core/services/rental_service.dart';
import 'rental_detail_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;

class MapExplorePage extends StatefulWidget {
  const MapExplorePage({super.key});

  @override
  State<MapExplorePage> createState() => _MapExplorePageState();
}

class _MapExplorePageState extends State<MapExplorePage> {
  final MapController _mapController = MapController();
  
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
        await _loadRentals(loc.latitude, loc.longitude);
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRentals(double lat, double lng) async {
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

  LatLng _calculateDestination(double lat, double lng, double distanceMeters, double bearingDeg) {
    const R = 6371e3;
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

  bool _isRentalInCone(Rental rental) {
    if (!_isRadarActive || _currentHeading == null || _deviceLocation == null) return true;
    if (rental.latitude == null || rental.longitude == null) return false;

    final devLat = _deviceLocation!.latitude;
    final devLng = _deviceLocation!.longitude;

    final distance = Geolocator.distanceBetween(
      devLat, devLng,
      rental.latitude!, rental.longitude!
    );

    if (distance > radarDistanceMeters) return false;

    final bearingToRental = Geolocator.bearingBetween(
      devLat, devLng,
      rental.latitude!, rental.longitude!
    );

    var b1 = _currentHeading! % 360;
    if (b1 < 0) b1 += 360;
    
    var b2 = bearingToRental % 360;
    if (b2 < 0) b2 += 360;

    var diff = (b1 - b2).abs();
    if (diff > 180) diff = 360 - diff;

    return diff <= (radarAngleDegrees / 2);
  }

  List<Polygon> _buildPolygons() {
    if (!_isRadarActive || _currentHeading == null || _deviceLocation == null) return [];

    final lat = _deviceLocation!.latitude;
    final lng = _deviceLocation!.longitude;
    
    final leftBearing = _currentHeading! - (radarAngleDegrees / 2);
    final rightBearing = _currentHeading! + (radarAngleDegrees / 2);

    final pLeft = _calculateDestination(lat, lng, radarDistanceMeters, leftBearing);
    final pRight = _calculateDestination(lat, lng, radarDistanceMeters, rightBearing);
    final pCenter = _calculateDestination(lat, lng, radarDistanceMeters, _currentHeading!);

    return [
      Polygon(
        points: [
          LatLng(lat, lng),
          pLeft,
          pCenter,
          pRight,
        ],
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
        borderColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
        borderStrokeWidth: 2,
      )
    ];
  }

  Future<void> _getDirections(Rental r) async {
    if (r.latitude == null || r.longitude == null) return;
    final lat = r.latitude!;
    final lng = r.longitude!;
    
    // Create URLs for Apple Maps and Google Maps
    final appleMapsUrl = Uri.parse('http://maps.apple.com/?daddr=$lat,$lng');
    final googleMapsUrl = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');

    if (Platform.isIOS) {
      if (await canLaunchUrl(appleMapsUrl)) {
        await launchUrl(appleMapsUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      }
    } else {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      }
    }
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
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => RentalDetailPage(rental: r))
                          );
                        },
                        icon: const Icon(Icons.info_outline),
                        label: const Text('Details'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _getDirections(r);
                        },
                        icon: const Icon(Icons.directions),
                        label: const Text('Directions'),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  List<Marker> _buildMarkers() {
    return _rentals
        .where((r) => r.latitude != null && r.longitude != null)
        .where(_isRentalInCone)
        .map((r) {
          final isPremium = r.hasVideo == true; 
          
          return Marker(
            point: LatLng(r.latitude!, r.longitude!),
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: () => _showRentalPreview(r),
              child: Icon(
                Icons.location_on,
                size: 40,
                color: isPremium ? Colors.yellow : Colors.red,
              ),
            ),
          );
        }).toList();
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

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(_deviceLocation!.latitude, _deviceLocation!.longitude),
              initialZoom: 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.bluvberry.dwelly',
              ),
              PolygonLayer(
                polygons: _buildPolygons(),
              ),
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  maxClusterRadius: 45,
                  size: const Size(40, 40),
                  markers: _buildMarkers(),
                  builder: (context, markers) {
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      child: Center(
                        child: Text(
                          markers.length.toString(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
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
