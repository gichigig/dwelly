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
  bool _isRefreshingLocation = false;
  DeviceLocationResult? _deviceLocation;
  
  // Radar state
  bool _isRadarActive = false;
  double? _currentHeading;
  StreamSubscription<CompassEvent>? _compassSubscription;
  
  // Constants for the radar cone
  static const double radarDistanceMeters = 1500; // 1.5km
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
      if (mounted) {
        setState(() {
          _deviceLocation = loc;
          _isLoading = false;
        });
      }
      if (loc.success && mounted) {
        await _loadRentals(loc.latitude, loc.longitude);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshLocation() async {
    if (_isRefreshingLocation) return;
    setState(() {
      _isRefreshingLocation = true;
    });
    
    try {
      final loc = await DeviceLocationService.getCurrentLocation();
      if (mounted) {
        setState(() {
          _deviceLocation = loc;
          _isRefreshingLocation = false;
        });
        if (loc.success) {
          _mapController.move(LatLng(loc.latitude, loc.longitude), 14.0);
          await _loadRentals(loc.latitude, loc.longitude);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('📍 Location & nearby rentals refreshed!'),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not detect location: ${loc.errorMessage ?? "Unknown error"}'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRefreshingLocation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to refresh location. Please check your GPS permissions.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Timer? _debounceTimer;

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
      if (event.heading != null && !event.heading!.isNaN) {
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
    if (!_isRadarActive || _currentHeading == null || _currentHeading!.isNaN || _deviceLocation == null) return true;
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

    var b1 = _currentHeading! % 360;
    if (b1 < 0) b1 += 360;
    
    var b2 = bearingToRental % 360;
    if (b2 < 0) b2 += 360;

    var diff = (b1 - b2).abs();
    if (diff > 180) diff = 360 - diff;

    return true; // Show all dots in the circular radar
  }

  List<Polygon> _buildPolygons() {
    if (!_isRadarActive || _currentHeading == null || _currentHeading!.isNaN || _deviceLocation == null) return [];

    final lat = _deviceLocation!.latitude!;
    final lng = _deviceLocation!.longitude!;
    
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

  void _showRentalPreview(Rental lightweightRental) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final r = lightweightRental;
        bool isNavigating = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                        onPressed: isNavigating ? null : () async {
                          setState(() => isNavigating = true);
                          try {
                            final fullRental = await RentalService.getById(r.id!)
                                .timeout(const Duration(seconds: 10));
                            if (!context.mounted) return;
                            Navigator.pop(context); // pop bottom sheet
                            if (fullRental != null) {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => RentalDetailPage(rental: fullRental))
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              setState(() => isNavigating = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Failed to load details. Please try again.')),
                              );
                            }
                          }
                        },
                        icon: isNavigating 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.info_outline),
                        label: Text(isNavigating ? 'Loading...' : 'Details'),
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
    },
  );
}

  List<Marker> _buildMarkers() {
    return _rentals
        .where((r) => r.latitude != null && r.longitude != null && !r.latitude!.isNaN && !r.longitude!.isNaN)
        .where(_isRentalInCone)
        .map((r) {
          final isPremium = r.hasVideo == true; 
          String labelText = r.propertyType;
          if ((r.propertyType.toUpperCase() == 'APARTMENT' || r.propertyType.toUpperCase() == 'HOUSE') && r.bedrooms > 0) {
             labelText = '${r.bedrooms} bedroom';
          } else if (r.bedrooms == 0 && r.propertyType.toUpperCase() == 'APARTMENT') {
             labelText = 'Bedsitter';
          }
          
          return Marker(
            point: LatLng(r.latitude!, r.longitude!),
            width: 120,
            height: 60,
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () => _showRentalPreview(r),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isPremium ? Colors.yellow : Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      labelText,
                      style: TextStyle(
                        color: isPremium ? Colors.black : Colors.white, 
                        fontSize: 10, 
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.location_on,
                    size: 30,
                    color: isPremium ? Colors.yellow : Colors.red,
                  ),
                ],
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

    if (_deviceLocation == null || !_deviceLocation!.success) {
      return Scaffold(
        appBar: AppBar(title: const Text('Map Explore')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.location_off, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  _deviceLocation?.errorMessage ?? 'Location access is required to use the map.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                      _deviceLocation = null;
                    });
                    _initMap();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                )
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(_deviceLocation!.latitude!, _deviceLocation!.longitude!),
              initialZoom: 14.0,
              onPositionChanged: (position, hasGesture) {
                if (hasGesture && position.center != null) {
                  _debounceTimer?.cancel();
                  _debounceTimer = Timer(const Duration(milliseconds: 600), () {
                    if (mounted) {
                      // Only reload rentals for the new center — do NOT
                      // overwrite _deviceLocation with setState, because
                      // that triggers a full FlutterMap rebuild which
                      // causes the map to lose its camera position.
                      _loadRentals(position.center.latitude, position.center.longitude);
                    }
                  });
                }
              },
              onLongPress: (tapPosition, point) {
                setState(() {
                  _deviceLocation = DeviceLocationResult(
                    latitude: point.latitude,
                    longitude: point.longitude,
                    success: true,
                  );
                });
                _loadRentals(point.latitude, point.longitude);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Radar origin manually adjusted!'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.bluvberry.dwelly',
              ),
              PolygonLayer(
                polygons: _buildPolygons(),
              ),
                            CircleLayer(
                circles: _deviceLocation != null && _isRadarActive ? <CircleMarker>[
                  CircleMarker(
                    point: LatLng(_deviceLocation!.latitude!, _deviceLocation!.longitude!),
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderStrokeWidth: 2,
                    borderColor: Theme.of(context).colorScheme.primary,
                    useRadiusInMeter: true,
                    radius: radarDistanceMeters,
                  )
                ] : const <CircleMarker>[],
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
              top: 110,
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
                        'Radar Active: Heading ${_currentHeading!.toStringAsFixed(0)}°\nRevealing nearby rentals in your direction.\nTip: Long-press anywhere on map to manually adjust radar center.',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
          // Back Button (Top Left)
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
          
          // Refresh GPS Location Button (Top Right opposite of arrow)
          Positioned(
            top: 50,
            right: 16,
            child: Material(
              color: Colors.white,
              elevation: 4,
              borderRadius: BorderRadius.circular(25),
              child: InkWell(
                onTap: _isRefreshingLocation ? null : _refreshLocation,
                borderRadius: BorderRadius.circular(25),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isRefreshingLocation)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
                        )
                      else
                        const Icon(Icons.refresh, size: 18, color: Colors.blue),
                      const SizedBox(width: 6),
                      Text(
                        _isRefreshingLocation ? 'Locating...' : 'Refresh GPS',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
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
