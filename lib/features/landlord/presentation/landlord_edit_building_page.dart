import 'package:flutter/material.dart';
import '../services/landlord_service.dart';
import '../../../core/services/api_service.dart';
import '../../../core/widgets/location_autocomplete.dart';
import '../../../core/widgets/map_picker.dart';
import 'dart:convert';

class LandlordEditBuildingPage extends StatefulWidget {
  final dynamic building;
  const LandlordEditBuildingPage({super.key, required this.building});

  @override
  State<LandlordEditBuildingPage> createState() => _LandlordEditBuildingPageState();
}

class _LandlordEditBuildingPageState extends State<LandlordEditBuildingPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _wardController;
  late TextEditingController _constituencyController;
  late TextEditingController _countyController;
  
  double? _latitude;
  double? _longitude;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.building['name'] ?? '');
    _wardController = TextEditingController(text: widget.building['ward'] ?? '');
    _constituencyController = TextEditingController(text: widget.building['constituency'] ?? '');
    _countyController = TextEditingController(text: widget.building['county'] ?? '');
    _latitude = widget.building['latitude'];
    _longitude = widget.building['longitude'];
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final response = await ApiService.timedPut(
        Uri.parse('${ApiService.baseUrl}/buildings/${widget.building['id']}'),
        headers: LandlordService.jsonHeadersWithAuth(),
        body: json.encode({
          'name': _nameController.text,
          'ward': _wardController.text,
          'constituency': _constituencyController.text,
          'county': _countyController.text,
          if (_latitude != null) 'latitude': _latitude,
          if (_longitude != null) 'longitude': _longitude,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        throw Exception('Failed to update building: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _wardController.dispose();
    _constituencyController.dispose();
    _countyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Building')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Building Name', border: OutlineInputBorder()),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    LocationAutocomplete(
                      labelText: 'Ward Location',
                      hintText: 'Search for a ward...',
                      required: true,
                      initialValue: _wardController.text,
                      onSelected: (loc) {
                        setState(() {
                          _wardController.text = loc.ward ?? '';
                          _constituencyController.text = loc.constituency ?? '';
                          _countyController.text = loc.county ?? '';
                        });
                      },
                      onChanged: (val) {
                        if (val.isEmpty) {
                          setState(() {
                            _wardController.text = '';
                            _constituencyController.text = '';
                            _countyController.text = '';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Type ward name to fetch location. Constituency and County will fill automatically.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _constituencyController,
                      decoration: InputDecoration(
                        labelText: 'Constituency', 
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                      ),
                      readOnly: true,
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _countyController,
                      decoration: InputDecoration(
                        labelText: 'County', 
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                      ),
                      readOnly: true,
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 24),
                    const Row(
                      children: [
                        Icon(Icons.map, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          'Geotag Coordinates',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Click on the map below to pinpoint the exact location of the building.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    MapPicker(
                      initialLatitude: _latitude,
                      initialLongitude: _longitude,
                      onLocationSelected: (lat, lng) {
                        setState(() {
                          _latitude = lat;
                          _longitude = lng;
                        });
                      },
                    ),
                    if (_latitude != null && _longitude != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Coordinates locked: ${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}',
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                      child: const Text('Save Changes'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
