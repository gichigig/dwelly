import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../data/id_scanner_service.dart';

/// Page for scanning a found ID and registering it
class FoundIdScanPage extends StatefulWidget {
  const FoundIdScanPage({super.key});

  @override
  State<FoundIdScanPage> createState() => _FoundIdScanPageState();
}

class _FoundIdScanPageState extends State<FoundIdScanPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _locationController = TextEditingController();
  final _collectionPlaceController = TextEditingController();
  final _nameController = TextEditingController();
  final _idNumberController = TextEditingController();
  final _dobController = TextEditingController();
  
  File? _selectedImage;
  IdScanResult? _scanResult;
  bool _isScanning = false;
  bool _isSubmitting = false;
  bool _isGettingLocation = false;
  String? _errorMessage;
  
  @override
  void dispose() {
    _phoneController.dispose();
    _whatsappController.dispose();
    _locationController.dispose();
    _collectionPlaceController.dispose();
    _nameController.dispose();
    _idNumberController.dispose();
    _dobController.dispose();
    super.dispose();
  }
  
  Future<void> _getCurrentLocation() async {
    setState(() {
      _isGettingLocation = true;
    });
    
    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission denied')),
            );
          }
          setState(() => _isGettingLocation = false);
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission permanently denied. Please enable in settings.')),
          );
        }
        setState(() => _isGettingLocation = false);
        return;
      }
      
      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      
      // Reverse geocode to get address
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final locationParts = <String>[];
        
        if (place.subLocality?.isNotEmpty == true) {
          locationParts.add(place.subLocality!);
        }
        if (place.locality?.isNotEmpty == true) {
          locationParts.add(place.locality!);
        }
        if (place.subAdministrativeArea?.isNotEmpty == true) {
          locationParts.add(place.subAdministrativeArea!);
        }
        
        final locationText = locationParts.isNotEmpty 
            ? locationParts.join(', ')
            : '${place.locality ?? ''}, ${place.country ?? ''}';
        
        setState(() {
          _locationController.text = locationText;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to get location: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGettingLocation = false);
      }
    }
  }
  
  Future<void> _pickImage(ImageSource source) async {
    // Check camera permission
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (status.isPermanentlyDenied || status.isRestricted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera permission is blocked. Enable it in Settings.'),
            ),
          );
        }
        await openAppSettings();
        return;
      }
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera permission is required to scan IDs')),
          );
        }
        return;
      }
    }
    
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 90,
      );
      
      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _scanResult = null;
          _errorMessage = null;
        });
        
        await _scanImage();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to pick image: $e';
      });
    }
  }
  
  Future<void> _scanImage() async {
    if (_selectedImage == null) return;
    
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });
    
    try {
      final result = await IdScannerService.scanIdFromImage(_selectedImage!);
      
      setState(() {
        _scanResult = result;
        _isScanning = false;

        _nameController.text = result.fullName ?? '';
        _idNumberController.text = result.idNumber ?? '';
        _dobController.text = _formatDateOfBirth(result.dateOfBirth);

        if (!result.success) {
          _errorMessage = result.errors.join('\n');
        }
      });
    } catch (e) {
      setState(() {
        _isScanning = false;
        _errorMessage = 'Failed to scan image: $e';
      });
    }
  }
  
  Future<void> _submitFoundId() async {
    if (_scanResult == null) return;
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    
    try {
      final response = await IdScannerService.registerFoundId(
        idNumber: _idNumberController.text.trim(),
        fullName: _nameController.text.trim(),
        dateOfBirth: _parseDateOfBirth(_dobController.text.trim()),
        finderPhone: _phoneController.text.trim(),
        finderWhatsApp: _whatsappController.text.trim().isNotEmpty
            ? _whatsappController.text.trim()
            : null,
        foundLocation: _locationController.text.trim().isNotEmpty
            ? _locationController.text.trim()
            : null,
        collectionPlace: _collectionPlaceController.text.trim().isNotEmpty
            ? _collectionPlaceController.text.trim()
            : null,
      );
      
      setState(() {
        _isSubmitting = false;
      });
      
      if (response.success) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
              title: const Text('Thank You!'),
              content: Text(response.message),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Close dialog
                    Navigator.of(context).pop(); // Go back
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        }
      } else {
        setState(() {
          _errorMessage = response.message;
        });
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Failed to submit: $e';
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Found ID'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Instructions
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(height: 8),
                      Text(
                        'Found someone\'s ID? Help them find it!',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Take a photo of the ID to extract the details. Only the text information will be stored, not the image.',
                        style: TextStyle(color: Colors.blue.shade600, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Image capture section
              if (_selectedImage == null) ...[
                _buildCaptureButtons(),
              ] else ...[
                // Show captured image
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        _selectedImage!,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        onPressed: () {
                          setState(() {
                            _selectedImage = null;
                            _scanResult = null;
                            _errorMessage = null;
                          });
                        },
                        icon: const Icon(Icons.close),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                
                // Retake button
                OutlinedButton.icon(
                  onPressed: () => _showImageSourceDialog(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retake Photo'),
                ),
              ],
              
              // Scanning indicator
              if (_isScanning) ...[
                const SizedBox(height: 20),
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Scanning ID...'),
                    ],
                  ),
                ),
              ],
              
              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              // Scan results - EDITABLE
              if (_scanResult != null) ...[
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Review ID Details',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _scanResult!.success
                              ? 'Edit any details below if they are not exact'
                              : 'We could not read everything. Fill in the missing fields.',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                        const Divider(height: 24),
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Name on ID *',
                            helperText: 'Any name from the ID is ok.',
                            prefixIcon: const Icon(Icons.person_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Name is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _idNumberController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'ID Number *',
                            prefixIcon: const Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'ID number is required';
                            }
                            if (value.trim().length < 7) {
                              return 'Enter a valid ID number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _dobController,
                          keyboardType: TextInputType.datetime,
                          decoration: InputDecoration(
                            labelText: 'Date of Birth (Optional)',
                            hintText: 'DD/MM/YYYY',
                            prefixIcon: const Icon(Icons.calendar_today),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Your Contact Information section
                const Text(
                  'Your Contact Information',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The ID owner will use this to contact you',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 12),
                
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Your Phone Number *',
                    hintText: '07XXXXXXXX',
                    prefixIcon: const Icon(Icons.phone),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Phone number is required';
                    }
                    if (value.trim().length < 10) {
                      return 'Enter a valid phone number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                
                TextFormField(
                  controller: _whatsappController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'WhatsApp Number (Optional)',
                    hintText: '07XXXXXXXX',
                    prefixIcon: const Icon(Icons.chat),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    helperText: 'Leave empty if same as phone number',
                  ),
                ),
                const SizedBox(height: 16),
                
                // Location section
                TextFormField(
                  controller: _locationController,
                  decoration: InputDecoration(
                    labelText: 'Where did you find it? (Optional)',
                    hintText: 'e.g., Near CBD bus stop',
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    suffixIcon: _isGettingLocation
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.my_location),
                            tooltip: 'Use current location',
                            onPressed: _getCurrentLocation,
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Collection place
                TextFormField(
                  controller: _collectionPlaceController,
                  decoration: InputDecoration(
                    labelText: 'Collection Place (Optional)',
                    hintText: 'e.g., Central Police Station, any landmark',
                    prefixIcon: const Icon(Icons.place_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    helperText: 'Where can the owner come to collect their ID?',
                  ),
                ),
                const SizedBox(height: 24),
                
                // Submit button
                FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submitFoundId,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload),
                  label: Text(_isSubmitting ? 'Submitting...' : 'Register Found ID'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildCaptureButtons() {
    return Column(
      children: [
        InkWell(
          onTap: () => _pickImage(ImageSource.camera),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300, width: 2),
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey.shade50,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.camera_alt, size: 48, color: Colors.grey.shade600),
                const SizedBox(height: 12),
                Text(
                  'Take Photo of ID',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Position the ID clearly in the frame',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => _pickImage(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose from Gallery'),
        ),
      ],
    );
  }
  
  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatDateOfBirth(String? dob) {
    if (dob == null) return '';
    try {
      final parts = dob.split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}/${parts[0]}';
      }
    } catch (_) {}
    return dob;
  }
  
  /// Parse DD/MM/YYYY back to YYYY-MM-DD for the API
  String? _parseDateOfBirth(String dob) {
    if (dob.isEmpty) return null;
    try {
      final parts = dob.split('/');
      if (parts.length == 3) {
        return '${parts[2]}-${parts[1]}-${parts[0]}';
      }
    } catch (_) {}
    return dob;
  }
}
