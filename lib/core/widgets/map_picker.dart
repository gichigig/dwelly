import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/device_location_service.dart';

class MapPicker extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final void Function(double lat, double lng) onLocationSelected;

  const MapPicker({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    required this.onLocationSelected,
  });

  @override
  State<MapPicker> createState() => _MapPickerState();
}

class _MapPickerState extends State<MapPicker> {
  final MapController _mapController = MapController();
  LatLng? _selectedPoint;
  LatLng _initialCenter = const LatLng(-1.2921, 36.8219); // Default Nairobi
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _initialCenter = LatLng(widget.initialLatitude!, widget.initialLongitude!);
      _selectedPoint = _initialCenter;
      setState(() => _isLoading = false);
      return;
    }

    try {
      final loc = await DeviceLocationService.getCurrentLocation();
      if (loc.hasLocationData && mounted) {
        setState(() {
          _initialCenter = LatLng(loc.latitude, loc.longitude);
          _selectedPoint = _initialCenter;
          _isLoading = false;
        });
        widget.onLocationSelected(loc.latitude, loc.longitude);
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _selectedPoint = point;
    });
    widget.onLocationSelected(point.latitude, point.longitude);
  }

  Future<void> _locateMe() async {
    setState(() => _isLoading = true);
    try {
      final loc = await DeviceLocationService.getCurrentLocation();
      if (loc.hasLocationData && mounted) {
        final point = LatLng(loc.latitude, loc.longitude);
        _mapController.move(point, 15.0);
        setState(() {
          _selectedPoint = point;
          _isLoading = false;
        });
        widget.onLocationSelected(point.latitude, point.longitude);
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _selectedPoint == null) {
      return Container(
        height: 250,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _initialCenter,
                initialZoom: 13.0,
                onTap: _handleTap,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.drag,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.bluvberry.dwelly',
                ),
                if (_selectedPoint != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _selectedPoint!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              elevation: 2,
              child: InkWell(
                onTap: _locateMe,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isLoading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.my_location, size: 18, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Text(
                        'Locate Me',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
