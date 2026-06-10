import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/models/rental.dart';
import '../../../../core/services/device_location_service.dart';

class RentalsMapView extends StatefulWidget {
  final List<Rental> rentals;
  final DeviceLocationResult? userLocation;
  final ValueChanged<Rental> onRentalSelected;

  const RentalsMapView({
    super.key,
    required this.rentals,
    this.userLocation,
    required this.onRentalSelected,
  });

  @override
  State<RentalsMapView> createState() => _RentalsMapViewState();
}

class _RentalsMapViewState extends State<RentalsMapView> {
  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();
  Set<Marker> _markers = {};

  // Nairobi default center
  static const CameraPosition _defaultPosition = CameraPosition(
    target: LatLng(-1.2921, 36.8219),
    zoom: 12.0,
  );

  @override
  void initState() {
    super.initState();
    _updateMarkers();
  }

  @override
  void didUpdateWidget(RentalsMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rentals != widget.rentals) {
      _updateMarkers();
      _fitMapToMarkers();
    }
  }

  void _updateMarkers() {
    final markers = <Marker>{};

    for (final rental in widget.rentals) {
      if (rental.latitude != null && rental.longitude != null) {
        markers.add(
          Marker(
            markerId: MarkerId(rental.id.toString()),
            position: LatLng(rental.latitude!, rental.longitude!),
            // A simple blue dot for the listing
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            onTap: () => widget.onRentalSelected(rental),
          ),
        );
      }
    }

    setState(() {
      _markers = markers;
    });
  }

  Future<void> _fitMapToMarkers() async {
    if (widget.rentals.isEmpty && widget.userLocation == null) return;
    
    final GoogleMapController controller = await _controller.future;
    
    double minLat = 90.0;
    double maxLat = -90.0;
    double minLng = 180.0;
    double maxLng = -180.0;
    bool hasValidPoints = false;

    for (final rental in widget.rentals) {
      if (rental.latitude != null && rental.longitude != null) {
        hasValidPoints = true;
        if (rental.latitude! < minLat) minLat = rental.latitude!;
        if (rental.latitude! > maxLat) maxLat = rental.latitude!;
        if (rental.longitude! < minLng) minLng = rental.longitude!;
        if (rental.longitude! > maxLng) maxLng = rental.longitude!;
      }
    }

    if (widget.userLocation != null) {
      hasValidPoints = true;
      final lat = widget.userLocation!.latitude;
      final lng = widget.userLocation!.longitude;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    if (hasValidPoints) {
      // Add a small padding to the bounds
      final latDelta = (maxLat - minLat).abs();
      final lngDelta = (maxLng - minLng).abs();
      final padding = 0.01; // Roughly 1km padding
      
      final bounds = LatLngBounds(
        southwest: LatLng(minLat - padding, minLng - padding),
        northeast: LatLng(maxLat + padding, maxLng + padding),
      );
      
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 50.0),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine initial camera position
    CameraPosition initialPosition = _defaultPosition;
    if (widget.userLocation != null) {
      initialPosition = CameraPosition(
        target: LatLng(widget.userLocation!.latitude, widget.userLocation!.longitude),
        zoom: 14.0,
      );
    } else if (widget.rentals.isNotEmpty) {
      final firstValid = widget.rentals.firstWhere(
        (r) => r.latitude != null && r.longitude != null, 
        orElse: () => widget.rentals.first
      );
      if (firstValid.latitude != null && firstValid.longitude != null) {
        initialPosition = CameraPosition(
          target: LatLng(firstValid.latitude!, firstValid.longitude!),
          zoom: 13.0,
        );
      }
    }

    return GoogleMap(
      mapType: MapType.normal,
      initialCameraPosition: initialPosition,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      compassEnabled: true,
      markers: _markers,
      onMapCreated: (GoogleMapController controller) {
        _controller.complete(controller);
        // Apply dark style if theme is dark
        if (Theme.of(context).brightness == Brightness.dark) {
          _setDarkMapStyle(controller);
        }
        // Frame the map to fit all rentals after a small delay
        Future.delayed(const Duration(milliseconds: 500), _fitMapToMarkers);
      },
    );
  }

  void _setDarkMapStyle(GoogleMapController controller) {
    const String darkMapStyle = '''
    [
      {
        "elementType": "geometry",
        "stylers": [
          {
            "color": "#212121"
          }
        ]
      },
      {
        "elementType": "labels.icon",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#757575"
          }
        ]
      },
      {
        "elementType": "labels.text.stroke",
        "stylers": [
          {
            "color": "#212121"
          }
        ]
      },
      {
        "featureType": "administrative",
        "elementType": "geometry",
        "stylers": [
          {
            "color": "#757575"
          }
        ]
      },
      {
        "featureType": "administrative.country",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#9e9e9e"
          }
        ]
      },
      {
        "featureType": "administrative.land_parcel",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "administrative.locality",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#bdbdbd"
          }
        ]
      },
      {
        "featureType": "poi",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#757575"
          }
        ]
      },
      {
        "featureType": "poi.park",
        "elementType": "geometry",
        "stylers": [
          {
            "color": "#181818"
          }
        ]
      },
      {
        "featureType": "poi.park",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#616161"
          }
        ]
      },
      {
        "featureType": "poi.park",
        "elementType": "labels.text.stroke",
        "stylers": [
          {
            "color": "#1b1b1b"
          }
        ]
      },
      {
        "featureType": "road",
        "elementType": "geometry.fill",
        "stylers": [
          {
            "color": "#2c2c2c"
          }
        ]
      },
      {
        "featureType": "road",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#8a8a8a"
          }
        ]
      },
      {
        "featureType": "road.arterial",
        "elementType": "geometry",
        "stylers": [
          {
            "color": "#373737"
          }
        ]
      },
      {
        "featureType": "road.highway",
        "elementType": "geometry",
        "stylers": [
          {
            "color": "#3c3c3c"
          }
        ]
      },
      {
        "featureType": "road.highway.controlled_access",
        "elementType": "geometry",
        "stylers": [
          {
            "color": "#4e4e4e"
          }
        ]
      },
      {
        "featureType": "road.local",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#616161"
          }
        ]
      },
      {
        "featureType": "transit",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#757575"
          }
        ]
      },
      {
        "featureType": "water",
        "elementType": "geometry",
        "stylers": [
          {
            "color": "#000000"
          }
        ]
      },
      {
        "featureType": "water",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#3d3d3d"
          }
        ]
      }
    ]
    ''';
    controller.setMapStyle(darkMapStyle);
  }
}
