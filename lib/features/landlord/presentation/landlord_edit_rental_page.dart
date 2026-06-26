import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/landlord_service.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/auth_service.dart';
import 'widgets/simple_video_preview.dart';

import '../../../core/models/rental.dart';

class LandlordEditRentalPage extends StatefulWidget {
  final Rental rental;
  final List<dynamic> buildings;
  const LandlordEditRentalPage({super.key, required this.rental, required this.buildings});

  @override
  State<LandlordEditRentalPage> createState() => _LandlordEditRentalPageState();
}

class _LandlordEditRentalPageState extends State<LandlordEditRentalPage> {
  final _formKey = GlobalKey<FormState>();
  
  String? _selectedBuildingId;
  late String _propertyType;
  late int _bedrooms;
  late int _bathrooms;
  late TextEditingController _priceController;
  late TextEditingController _descController;
  late TextEditingController _squareFeetController;
  late TextEditingController _floorController;

  late List<String> _amenities;
  late bool _petsAllowed;
  late bool _parkingAvailable;
  late bool _requiresApproval;
  late String _cardDisplayPreference;
  String? _availableFrom;
  
  File? _imageFile;
  File? _videoFile;
  File? _compoundVideoFile;
  bool _isLoading = false;

  final List<String> _availableAmenities = [
    'Wi-Fi', 'Air Conditioning', 'Pool', 'Gym', 'Security', 'Borehole', 'Solar Heating', 'Elevator', 'Backup Generator', 'Balcony'
  ];

  @override
  void initState() {
    super.initState();
    _propertyType = widget.rental.propertyType;
    _bedrooms = widget.rental.bedrooms;
    _bathrooms = widget.rental.bathrooms;
    _priceController = TextEditingController(text: widget.rental.price.toStringAsFixed(0));
    _descController = TextEditingController(text: widget.rental.description);
    _squareFeetController = TextEditingController(text: widget.rental.squareFeet.toString());
    _floorController = TextEditingController(text: widget.rental.floor?.toString() ?? '');
    _amenities = List.from(widget.rental.amenities);
    _petsAllowed = widget.rental.petsAllowed;
    _parkingAvailable = widget.rental.parkingAvailable;
    _requiresApproval = widget.rental.requiresApproval;
    _cardDisplayPreference = widget.rental.cardDisplayPreference ?? 'One Picture';
    _availableFrom = widget.rental.availableFrom;

    // Normalize propertyType to upper case to match dropdown values
    _propertyType = widget.rental.propertyType.toUpperCase();
    if (!['APARTMENT', 'HOUSE', 'STUDIO', 'BEDSITTER'].contains(_propertyType)) {
      _propertyType = 'APARTMENT';
    }
  }

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

      final response = await ApiService.timedPut(
        Uri.parse('${ApiService.baseUrl}/rentals/${widget.rental.id}'),
        headers: LandlordService.jsonHeadersWithAuth(),
        body: json.encode({
          if (_selectedBuildingId != null) 'buildingId': int.parse(_selectedBuildingId!),
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
          if (imageUrl != null) 'imageUrls': [imageUrl],
          if (videoUrl != null) 'videoUrl': videoUrl,
          if (compoundVideoUrl != null) 'compoundVideoUrl': compoundVideoUrl,
          if (videoUrl != null || compoundVideoUrl != null) 'hasVideo': true,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        throw Exception('Failed to update rental: ${response.statusCode}');
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
      appBar: AppBar(title: const Text('Edit Rental')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    if (widget.buildings.isNotEmpty)
                      DropdownButtonFormField<String>(
                        value: _selectedBuildingId,
                        decoration: const InputDecoration(labelText: 'Building (Optional to Change)', border: OutlineInputBorder()),
                        items: widget.buildings.map((b) => DropdownMenuItem<String>(
                          value: b['id'].toString(),
                          child: Text(b['name'] ?? 'Unnamed Building'),
                        )).toList(),
                        onChanged: (v) => setState(() => _selectedBuildingId = v),
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
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
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
                              : (widget.rental.imageUrls.isNotEmpty
                                  ? DecorationImage(
                                      image: NetworkImage(ApiService.resolveMediaUrl(widget.rental.imageUrls.first) ?? ''),
                                      fit: BoxFit.cover,
                                    )
                                  : null),
                        ),
                        child: _imageFile == null && widget.rental.imageUrls.isEmpty
                            ? const Center(child: Text('Tap to pick cover image'))
                            : _imageFile == null && widget.rental.imageUrls.isNotEmpty
                                ? Center(
                                    child: Container(
                                      color: Colors.black54,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      child: const Text('Tap to change cover image', style: TextStyle(color: Colors.white)),
                                    ),
                                  )
                                : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Video Tours', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    if (isPro) ...[
                      if (widget.rental.videoUrl != null || widget.rental.compoundVideoUrl != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            border: Border.all(color: Colors.green.shade200),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, color: Colors.green),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'This listing already has ${[
                                    if (widget.rental.videoUrl != null) 'a Main Video',
                                    if (widget.rental.compoundVideoUrl != null) 'a Compound Video'
                                  ].join(' and ')} attached.',
                                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (widget.rental.videoUrl != null && _videoFile == null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SimpleVideoPreview(
                            videoUrl: ApiService.resolveMediaUrl(widget.rental.videoUrl) ?? '',
                            onRemove: () {}, // Deletion not supported by backend yet, only replacement
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _pickVideo(false),
                              icon: const Icon(Icons.video_call),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _videoFile != null ? Colors.green : null,
                                foregroundColor: _videoFile != null ? Colors.white : null,
                              ),
                              label: Text(_videoFile != null 
                                ? 'New Video Picked' 
                                : (widget.rental.videoUrl != null ? 'Replace Main Video' : 'Upload Main Video')),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _pickVideo(true),
                              icon: const Icon(Icons.video_library),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _compoundVideoFile != null ? Colors.green : null,
                                foregroundColor: _compoundVideoFile != null ? Colors.white : null,
                              ),
                              label: Text(_compoundVideoFile != null 
                                ? 'New Video Picked' 
                                : (widget.rental.compoundVideoUrl != null ? 'Replace Compound Video' : 'Upload Compound Video')),
                            ),
                          ),
                        ],
                      ),
                      if (widget.rental.compoundVideoUrl != null && _compoundVideoFile == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: SimpleVideoPreview(
                            videoUrl: ApiService.resolveMediaUrl(widget.rental.compoundVideoUrl) ?? '',
                            onRemove: () {}, // Deletion not supported by backend yet, only replacement
                          ),
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
                      child: const Text('Save Changes'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
