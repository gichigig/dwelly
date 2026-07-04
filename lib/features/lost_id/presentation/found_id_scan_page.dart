import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../data/id_scanner_service.dart';
import '../../../core/services/google_ad_service.dart';

/// Page for scanning a found ID and registering it
class FoundIdScanPage extends StatefulWidget {
  final String? initialIdType;

  const FoundIdScanPage({super.key, this.initialIdType});

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
  final _schoolController = TextEditingController();

  static const String _nationalIdType = 'NATIONAL_ID';
  static const String _schoolIdType = 'SCHOOL_ID';
  final List<String> _idTypes = [_nationalIdType, _schoolIdType];
  String _selectedIdType = _nationalIdType;
  
  File? _selectedImage;
  IdScanResult? _scanResult;
  bool _isScanning = false;
  bool _isSubmitting = false;
  bool _isGettingLocation = false;
  bool _isManualEntry = false;
  String? _errorMessage;
  bool _agreedToSafetyPolicy = false;
  
  @override
  void initState() {
    super.initState();
    _applyInitialIdType();
  }

  void _applyInitialIdType() {
    final initial = widget.initialIdType;
    if (initial != null && _idTypes.contains(initial)) {
      _selectedIdType = initial;
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _whatsappController.dispose();
    _locationController.dispose();
    _collectionPlaceController.dispose();
    _nameController.dispose();
    _idNumberController.dispose();
    _schoolController.dispose();
    super.dispose();
  }
  
  void _enableManualEntry() {
    setState(() {
      _isManualEntry = true;
      _selectedImage = null;
      _scanResult = null;
      _errorMessage = null;
      _nameController.clear();
      _idNumberController.clear();
      _schoolController.clear();
    });
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
          _isManualEntry = false;
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
        if (result.idNumber != null) {
          _idNumberController.text = result.idNumber!;
        }
        
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
    if (_scanResult == null && !_isManualEntry) return;
    if (!_formKey.currentState!.validate()) return;
    
    if (!_agreedToSafetyPolicy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please check the box to agree to the Safety & Data Handling Policy.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    
    try {
      final response = await IdScannerService.registerFoundId(
        idNumber: _idNumberController.text.trim(),
        fullName: _nameController.text.trim(),
        idType: _selectedIdType,
        schoolName: _selectedIdType == _schoolIdType
            ? _schoolController.text.trim()
            : null,
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
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
                            _isManualEntry = false;
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
              
              // Scan results or Manual Entry - EDITABLE
              if (_scanResult != null || _isManualEntry) ...[
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
                          _isManualEntry 
                              ? 'Enter the details of the ID you found below.'
                              : _scanResult!.success
                                  ? 'Edit any details below if they are not exact'
                                  : 'We could not read everything. Fill in the missing fields.',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                        const Divider(height: 24),
                        DropdownButtonFormField<String>(
                          value: _selectedIdType,
                          items: _idTypes
                              .map(
                                (type) => DropdownMenuItem<String>(
                                  value: type,
                                  child: Text(
                                    type == _schoolIdType
                                        ? 'School ID'
                                        : 'National ID',
                                  ),
                                ),
                              )
                              .toList(),
                          decoration: InputDecoration(
                            labelText: 'ID Type',
                            prefixIcon: const Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _selectedIdType = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
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
                        if (_selectedIdType == _schoolIdType) ...[
                          TextFormField(
                            controller: _schoolController,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: 'School Name *',
                              prefixIcon: const Icon(Icons.school_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            validator: (value) {
                              if (_selectedIdType != _schoolIdType) {
                                return null;
                              }
                              if (value == null || value.trim().isEmpty) {
                                return 'School name is required for School ID';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        TextFormField(
                          controller: _idNumberController,
                          keyboardType: _selectedIdType == _schoolIdType
                              ? TextInputType.text
                              : TextInputType.number,
                          decoration: InputDecoration(
                            labelText: _selectedIdType == _schoolIdType
                                ? 'School ID Number *'
                                : 'National ID Number *',
                            prefixIcon: const Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'ID number is required';
                            }
                            if (_selectedIdType == _schoolIdType) {
                              if (value.trim().length < 3) {
                                return 'Enter a valid school ID number';
                              }
                            } else if (value.trim().length < 7) {
                              return 'Enter a valid ID number';
                            }
                            return null;
                          },
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
                const SizedBox(height: 20),
                
                // Safety & Data Handling Policy Card
                Container(
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.shield_outlined, color: Colors.amber.shade900, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Safety & Data Handling Policy',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '• Data Privacy: Your contact details are encrypted and shared ONLY with the verified owner searching for this specific ID.\n'
                        '• Data Deletion Schedule: All found ID records and contact details are automatically deleted from our servers after 7 days or immediately upon collection/match confirmation.\n'
                        '• Manual Deletion: You or the owner can manually delete this record at any time using the red "Delete This Record" button when searching the ID number on the search screen.\n'
                        '• How to Verify Deletion: To manually check and verify that this record has been permanently erased, search the ID Number on the "Lost My ID" screen. A result of "Not Found" confirms total deletion from our databases.\n'
                        '• Safety & Security Advice: For security purposes, we strongly urge you to leave found IDs at a secure public facility (such as a Police Station, bank, or security desk). If meeting the owner in person, ALWAYS meet in a busy, crowded public place. Never lure people to secluded areas or demand a reward/ransom.',
                        style: TextStyle(fontSize: 12.5, color: Colors.amber.shade900, height: 1.4),
                      ),
                      const Divider(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: _agreedToSafetyPolicy,
                              activeColor: Colors.amber.shade900,
                              onChanged: (val) {
                                setState(() {
                                  _agreedToSafetyPolicy = val ?? false;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _agreedToSafetyPolicy = !_agreedToSafetyPolicy;
                                });
                              },
                              child: Text(
                                'I agree to the Data Handling Policy and will follow safety advice when returning this ID.',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
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
              const SizedBox(height: 32),
              const Center(child: GoogleAdMediumRectangleWidget()),
              const SizedBox(height: 16),
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
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            setState(() {
              _isManualEntry = true;
              _selectedImage = null;
              _scanResult = null;
              _errorMessage = null;
            });
          },
          icon: const Icon(Icons.edit_note),
          label: const Text('Enter Details Manually'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.grey.shade700,
          ),
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
  

}
