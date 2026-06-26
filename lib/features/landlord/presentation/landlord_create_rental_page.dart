import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/landlord_service.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/auth_service.dart';

class LandlordCreateRentalPage extends StatefulWidget {
  final List<dynamic> buildings;
  const LandlordCreateRentalPage({super.key, required this.buildings});

  @override
  State<LandlordCreateRentalPage> createState() => _LandlordCreateRentalPageState();
}

class _LandlordCreateRentalPageState extends State<LandlordCreateRentalPage> {
  final _formKey = GlobalKey<FormState>();
  
  String? _selectedBuildingId;
  String _propertyType = 'APARTMENT';
  int _bedrooms = 1;
  int _bathrooms = 1;
  final _priceController = TextEditingController();
  final _descController = TextEditingController();
  final _squareFeetController = TextEditingController(text: '0');
  final _floorController = TextEditingController();

  List<String> _amenities = [];
  bool _petsAllowed = false;
  bool _parkingAvailable = false;
  bool _requiresApproval = false;
  String _cardDisplayPreference = 'One Picture';
  String? _availableFrom;
  
  File? _imageFile;
  File? _videoFile;
  File? _compoundVideoFile;
  bool _isLoading = false;

  final List<String> _availableAmenities = [
    'Wi-Fi', 'Air Conditioning', 'Pool', 'Gym', 'Security', 'Borehole', 'Solar Heating', 'Elevator', 'Backup Generator', 'Balcony'
  ];

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null) {
      setState(() {
        _imageFile = File(picked.path);
      });
    }
  }

  Future<void> _pickVideo(bool isCompound) async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        if (isCompound) {
          _compoundVideoFile = File(picked.path);
        } else {
          _videoFile = File(picked.path);
        }
      });
    }
  }

  Future<void> _openRealAdminProPayment() async {
    String baseUrl = 'https://billygichigdev.me/payments/mpesa';
    if (kDebugMode) {
      if (kIsWeb) {
        baseUrl = 'http://localhost:3000/payments/mpesa';
      } else if (!kIsWeb && Platform.isIOS) {
        baseUrl = 'http://localhost:3000/payments/mpesa';
      } else {
        baseUrl = 'http://10.0.2.2:3000/payments/mpesa';
      }
    }
    
    final params = <String, String>{
      'type': 'REALADMIN_PRO',
      'amount': '1000',
    };
    
    final token = AuthService.token;
    if (token != null) {
      params['token'] = token;
    }
    
    final uri = Uri.parse(baseUrl).replace(queryParameters: params);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the payment page.')),
      );
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBuildingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a building')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      String? imageUrl;
      String? videoUrl;
      String? compoundVideoUrl;

      if (_imageFile != null) {
        imageUrl = await ApiService.uploadFile(_imageFile!, '/files/upload', token: AuthService.token);
      }
      if (_videoFile != null) {
        videoUrl = await ApiService.uploadFile(_videoFile!, '/files/upload', token: AuthService.token);
      }
      if (_compoundVideoFile != null) {
        compoundVideoUrl = await ApiService.uploadFile(_compoundVideoFile!, '/files/upload', token: AuthService.token);
      }

      final building = widget.buildings.firstWhere((b) => b['id'].toString() == _selectedBuildingId);

      final response = await ApiService.timedPost(
        Uri.parse('${ApiService.baseUrl}/rentals?userId=${AuthService.currentUser?.id}'),
        headers: LandlordService.jsonHeadersWithAuth(),
        body: json.encode({
          'buildingId': int.parse(_selectedBuildingId!),
          'propertyType': _propertyType,
          'bedrooms': _bedrooms,
          'bathrooms': _bathrooms,
          'price': double.parse(_priceController.text),
          'description': _descController.text,
          'squareFeet': int.tryParse(_squareFeetController.text) ?? 0,
          'floor': int.tryParse(_floorController.text),
          'amenities': _amenities,
          'petsAllowed': _petsAllowed,
          'parkingAvailable': _parkingAvailable,
          'requiresApproval': _requiresApproval,
          'cardDisplayPreference': _cardDisplayPreference,
          'availableFrom': _availableFrom,
          'imageUrls': imageUrl != null ? [imageUrl] : [],
          'videoUrl': videoUrl,
          'compoundVideoUrl': compoundVideoUrl,
          'hasVideo': (videoUrl != null || compoundVideoUrl != null),
          'status': 'DRAFT',
          'ward': building['ward'],
          'county': building['county'],
          'constituency': building['constituency'],
          'latitude': building['latitude'],
          'longitude': building['longitude'],
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        throw Exception('Failed to create rental: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _priceController.dispose();
    _descController.dispose();
    _squareFeetController.dispose();
    _floorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isPro = AuthService.currentUser?.isRealadminPremiumActive ?? false;
    if (widget.buildings.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add Rental')),
        body: const Center(child: Text('Please create a building first')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Add Rental')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedBuildingId,
                      decoration: const InputDecoration(labelText: 'Building', border: OutlineInputBorder()),
                      items: widget.buildings.map((b) => DropdownMenuItem<String>(
                        value: b['id'].toString(),
                        child: Text(b['name'] ?? 'Unnamed Building'),
                      )).toList(),
                      onChanged: (v) => setState(() => _selectedBuildingId = v),
                      validator: (v) => v == null ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _propertyType,
                      decoration: const InputDecoration(labelText: 'Property Type', border: OutlineInputBorder()),
                      items: ['APARTMENT', 'HOUSE', 'STUDIO', 'BEDSITTER'].map((t) => DropdownMenuItem(value: t, child: Text(t[0] + t.substring(1).toLowerCase()))).toList(),
                      onChanged: (v) => setState(() => _propertyType = v!),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            decoration: const InputDecoration(labelText: 'Bedrooms', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            initialValue: _bedrooms.toString(),
                            onChanged: (v) => _bedrooms = int.tryParse(v) ?? 1,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            decoration: const InputDecoration(labelText: 'Bathrooms', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            initialValue: _bathrooms.toString(),
                            onChanged: (v) => _bathrooms = int.tryParse(v) ?? 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _priceController,
                      decoration: const InputDecoration(labelText: 'Price (KES)', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (double.tryParse(v) == null) return 'Invalid number';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descController,
                      decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                      maxLines: 3,
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _squareFeetController,
                            decoration: const InputDecoration(labelText: 'Square Feet', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _floorController,
                            decoration: const InputDecoration(labelText: 'Floor (Optional)', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Amenities', style: TextStyle(fontWeight: FontWeight.bold)),
                    Wrap(
                      spacing: 8.0,
                      children: _availableAmenities.map((amenity) {
                        final selected = _amenities.contains(amenity);
                        return FilterChip(
                          label: Text(amenity),
                          selected: selected,
                          onSelected: (bool value) {
                            setState(() {
                              if (value) {
                                _amenities.add(amenity);
                              } else {
                                _amenities.remove(amenity);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Pets Allowed'),
                      value: _petsAllowed,
                      onChanged: (v) => setState(() => _petsAllowed = v),
                    ),
                    SwitchListTile(
                      title: const Text('Parking Available'),
                      value: _parkingAvailable,
                      onChanged: (v) => setState(() => _parkingAvailable = v),
                    ),
                    SwitchListTile(
                      title: const Text('Requires Super Admin Approval (Private)'),
                      value: _requiresApproval,
                      onChanged: (v) => setState(() => _requiresApproval = v),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _cardDisplayPreference,
                      decoration: const InputDecoration(labelText: 'Card Display Preference', border: OutlineInputBorder()),
                      items: ['One Picture', 'Double Pictures', 'Three Pictures', 'Video'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (v) => setState(() => _cardDisplayPreference = v!),
                    ),
                    const SizedBox(height: 16),
                    const Text('Images & Media', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 150,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                          image: _imageFile != null
                              ? DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover)
                              : null,
                        ),
                        child: _imageFile == null
                            ? const Center(child: Text('Tap to pick cover image'))
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Video Tours', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    if (isPro) ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _pickVideo(false),
                              icon: const Icon(Icons.video_call),
                              label: Text(_videoFile != null ? 'Main Video Selected' : 'Upload Main Video'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _pickVideo(true),
                              icon: const Icon(Icons.video_library),
                              label: Text(_compoundVideoFile != null ? 'Compound Video Selected' : 'Upload Compound Video'),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.workspace_premium, color: Colors.amber, size: 40),
                            const SizedBox(height: 8),
                            const Text(
                              'Unlock Video Uploads',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const Text(
                              'Upgrade to RealAdmin Pro to add video tours to your listings.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                              onPressed: _openRealAdminProPayment,
                              child: const Text('Unlock RealAdmin Pro (KES 1000)'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                      child: const Text('Save as Draft'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
