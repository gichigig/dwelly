import 'package:flutter/material.dart';
import 'package:realestate/core/data/kenya_locations.dart';
import 'package:realestate/core/services/auth_service.dart';
import 'package:realestate/core/services/helper_service.dart';
import 'package:realestate/core/services/device_location_service.dart';
import 'package:realestate/core/widgets/location_autocomplete.dart';
import '../services_list_page.dart';

class RegisterHelperTab extends StatefulWidget {
  const RegisterHelperTab({super.key});

  @override
  State<RegisterHelperTab> createState() => _RegisterHelperTabState();
}

class _RegisterHelperTabState extends State<RegisterHelperTab> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  final TextEditingController _priceController = TextEditingController();
  String _selectedCoverageLevel = 'COUNTY'; // COUNTY, CONSTITUENCY, WARD
  
  String? _selectedCounty;
  String? _selectedServiceCategory;
  List<String> _selectedConstituencies = [];
  List<String> _selectedWards = [];

  // Offered products/services feature
  final TextEditingController _productNameController = TextEditingController();
  final TextEditingController _productPriceController = TextEditingController();
  List<String> _offeredServices = [];

  // Service area mode & radius vs administrative areas
  String _serviceAreaMode = 'ADMIN_AREAS'; // 'RADIUS' or 'ADMIN_AREAS'
  double _serviceRadiusKm = 10.0;
  bool _isLocating = false;
  String? _pinnedLocationLabel;

  // Landlord-style location autocomplete controllers
  final TextEditingController _wardController = TextEditingController();
  final TextEditingController _constituencyController = TextEditingController();
  final TextEditingController _countyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _populateExistingData();
  }

  void _populateExistingData() {
    final user = AuthService.currentUser;
    if (user != null) {
      if (user.helperPrice != null) {
        _priceController.text = user.helperPrice!.toStringAsFixed(2);
      }
      if (user.helperCoverageLevel != null) {
        _selectedCoverageLevel = user.helperCoverageLevel!;
      }
      _selectedCounty = user.helperCounty;
      _selectedServiceCategory = user.serviceCategory;
      _selectedConstituencies = List.from(user.helperConstituencies);
      _selectedWards = List.from(user.helperWards);

      if (user.serviceAreaMode != null && user.serviceAreaMode!.isNotEmpty) {
        _serviceAreaMode = user.serviceAreaMode!;
      }
      if (user.serviceRadiusKm != null && user.serviceRadiusKm! > 0) {
        _serviceRadiusKm = user.serviceRadiusKm!;
      }
      if (user.offeredServices.isNotEmpty) {
        _offeredServices = List.from(user.offeredServices);
      }
      if (user.locationLatitude != null && user.locationLongitude != null) {
        _pinnedLocationLabel = 'Lat: ${user.locationLatitude!.toStringAsFixed(4)}, Lon: ${user.locationLongitude!.toStringAsFixed(4)} (${user.formattedLocation})';
      }
      if (user.helperWards.isNotEmpty) {
        _wardController.text = user.helperWards.first;
      }
      if (user.helperConstituencies.isNotEmpty) {
        _constituencyController.text = user.helperConstituencies.first;
      }
      if (user.helperCounty != null) {
        _countyController.text = user.helperCounty!;
      }
    }
  }

  @override
  void dispose() {
    _priceController.dispose();
    _productNameController.dispose();
    _productPriceController.dispose();
    _wardController.dispose();
    _constituencyController.dispose();
    _countyController.dispose();
    super.dispose();
  }

  Future<void> _pinCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final loc = await DeviceLocationService.getCurrentLocation(forcePrompt: true);
      if (loc != null && loc.latitude != null && loc.longitude != null) {
        final currentUser = AuthService.currentUser;
        if (currentUser != null) {
          final updatedUser = currentUser.copyWith(
            locationLatitude: loc.latitude,
            locationLongitude: loc.longitude,
            locationWard: loc.ward ?? currentUser.locationWard,
            locationConstituency: loc.constituency ?? currentUser.locationConstituency,
            locationCounty: loc.county ?? currentUser.locationCounty,
            locationAreaName: loc.areaName ?? currentUser.locationAreaName,
          );
          await AuthService.updateUser(updatedUser);
        }
        setState(() {
          _pinnedLocationLabel = 'Lat: ${loc.latitude!.toStringAsFixed(4)}, Lon: ${loc.longitude!.toStringAsFixed(4)} (${loc.formattedLocation})';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location pinned successfully!')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not fetch location. Please check location permissions.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error pinning location: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_serviceAreaMode == 'RADIUS' && _pinnedLocationLabel == null && AuthService.currentUser?.locationLatitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pin or use your current location first for Radius mode.')),
      );
      return;
    }

    if (_serviceAreaMode == 'ADMIN_AREAS') {
      if (_selectedCounty == null && _countyController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a county or use ward autocomplete')),
        );
        return;
      }
      if (_selectedCoverageLevel == 'CONSTITUENCY' && _selectedConstituencies.isEmpty && _constituencyController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select at least one constituency')),
        );
        return;
      }
      if (_selectedCoverageLevel == 'WARD' && _selectedWards.isEmpty && _wardController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select at least one ward')),
        );
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      final user = AuthService.currentUser;
      if (user != null && user.primaryRole != 'helper') {
        await AuthService.setPrimaryRole('helper');
      }

      final countyVal = _countyController.text.isNotEmpty ? _countyController.text : _selectedCounty;
      final constituenciesVal = _constituencyController.text.isNotEmpty ? [_constituencyController.text] : _selectedConstituencies;
      final wardsVal = _wardController.text.isNotEmpty ? [_wardController.text] : _selectedWards;

      await HelperService.updateHelperProfile(
        price: double.parse(_priceController.text),
        coverageLevel: _selectedCoverageLevel,
        county: countyVal,
        constituencies: constituenciesVal,
        wards: wardsVal,
        serviceCategory: _selectedServiceCategory,
        serviceRadiusKm: _serviceAreaMode == 'RADIUS' ? _serviceRadiusKm : null,
        serviceAreaMode: _serviceAreaMode,
        offeredServices: _offeredServices,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Helper profile updated successfully!')),
        );
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
  Widget build(BuildContext context) {
    if (!AuthService.isLoggedIn) {
      return const Center(
        child: Text(
          'Please sign in to register as a helper or service provider.',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AuthService.currentUser?.primaryRole == 'helper' 
                ? 'Update your pricing, products/services, and coverage area below.'
                : 'Set your pricing and coverage area to start accepting jobs.',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // Service Category
            DropdownButtonFormField<String>(
              value: _selectedServiceCategory,
              decoration: const InputDecoration(
                labelText: 'Specialized Service Category (Optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.handyman_rounded),
                helperText: 'Select a category if offering specialized services (e.g., Plumber, Gas delivery)',
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('General Helper / Household Help'),
                ),
                ...kServiceCategoriesList
                    .where((c) => c.name != 'All')
                    .map((c) => DropdownMenuItem(
                          value: c.name,
                          child: Text(c.name),
                        )),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedServiceCategory = value;
                });
              },
            ),
            const SizedBox(height: 24),

            // Base Pricing
            TextFormField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Base Price per Job / Service (KES)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Please enter a price';
                if (double.tryParse(value) == null) return 'Please enter a valid number';
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Offered Products & Services Section
            const Text('Offered Products & Services (Optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Add specific services or products you offer with their prices:', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _productNameController,
                    decoration: const InputDecoration(
                      labelText: 'Item / Service Name',
                      hintText: 'e.g. Sofa cleaning / 13kg Gas Refill',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _productPriceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Price (KES)',
                      hintText: 'e.g. 1500',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    final name = _productNameController.text.trim();
                    final price = _productPriceController.text.trim();
                    if (name.isNotEmpty && price.isNotEmpty) {
                      setState(() {
                        _offeredServices.add('$name - KES $price');
                        _productNameController.clear();
                        _productPriceController.clear();
                      });
                    }
                  },
                ),
              ],
            ),
            if (_offeredServices.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: _offeredServices.map((item) {
                  return Chip(
                    label: Text(item),
                    onDeleted: () {
                      setState(() {
                        _offeredServices.remove(item);
                      });
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 24),

            // Service Area Mode
            const Text('Service Area Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Choose how you want customers to find your service area:', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'ADMIN_AREAS',
                  icon: Icon(Icons.map_outlined),
                  label: Text('Wards & County'),
                ),
                ButtonSegment(
                  value: 'RADIUS',
                  icon: Icon(Icons.my_location),
                  label: Text('Pin Location & Radius'),
                ),
              ],
              selected: {_serviceAreaMode},
              onSelectionChanged: (newSel) {
                setState(() {
                  _serviceAreaMode = newSel.first;
                });
              },
            ),
            const SizedBox(height: 20),

            if (_serviceAreaMode == 'RADIUS') ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Service Radius Configuration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 8),
                    Text(
                      _pinnedLocationLabel ?? 'No location pinned yet. Click below to use your current location.',
                      style: TextStyle(color: _pinnedLocationLabel != null ? Colors.black87 : Colors.red, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLocating ? null : _pinCurrentLocation,
                        icon: _isLocating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location),
                        label: Text(_isLocating ? 'Locating...' : (_pinnedLocationLabel != null ? 'Update Pinned Location' : 'Pin Current Location')),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Service Radius: ${_serviceRadiusKm.toStringAsFixed(0)} km', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Slider(
                      value: _serviceRadiusKm,
                      min: 2,
                      max: 50,
                      divisions: 48,
                      label: '${_serviceRadiusKm.toStringAsFixed(0)} km',
                      onChanged: (val) {
                        setState(() {
                          _serviceRadiusKm = val;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Administrative Areas (Landlord style autocomplete + dropdowns)
              LocationAutocomplete(
                labelText: 'Search Ward Location (Autofills Constituency & County)',
                hintText: 'Type ward name as landlord uses...',
                required: false,
                initialValue: _wardController.text,
                onSelected: (loc) {
                  setState(() {
                    _wardController.text = loc.ward ?? '';
                    _constituencyController.text = loc.constituency ?? '';
                    _countyController.text = loc.county ?? '';
                    if (loc.county != null) {
                      _selectedCounty = loc.county;
                    }
                    if (loc.constituency != null) {
                      if (!_selectedConstituencies.contains(loc.constituency!)) {
                        _selectedConstituencies.clear();
                        _selectedConstituencies.add(loc.constituency!);
                      }
                    }
                    if (loc.ward != null) {
                      if (!_selectedWards.contains(loc.ward!)) {
                        _selectedWards.clear();
                        _selectedWards.add(loc.ward!);
                      }
                    }
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

              // Coverage Level
              DropdownButtonFormField<String>(
                value: _selectedCoverageLevel,
                decoration: const InputDecoration(
                  labelText: 'Coverage Level',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.layers),
                ),
                items: const [
                  DropdownMenuItem(value: 'COUNTY', child: Text('Entire County')),
                  DropdownMenuItem(value: 'CONSTITUENCY', child: Text('Specific Constituencies (Max 2)')),
                  DropdownMenuItem(value: 'WARD', child: Text('Specific Wards (Max 5)')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedCoverageLevel = value;
                      _selectedConstituencies.clear();
                      _selectedWards.clear();
                    });
                  }
                },
              ),
              const SizedBox(height: 16),

              // County Selection (Required for all levels)
              DropdownButtonFormField<String>(
                value: _selectedCounty,
                decoration: const InputDecoration(
                  labelText: 'County',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_city),
                ),
                items: KenyaLocations.counties.map((county) {
                  return DropdownMenuItem(value: county, child: Text(county));
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCounty = value;
                    _selectedConstituencies.clear();
                    _selectedWards.clear();
                  });
                },
              ),

              // Constituency Selection
              if (_selectedCoverageLevel == 'CONSTITUENCY' && _selectedCounty != null) ...[
                const SizedBox(height: 16),
                const Text('Select Constituencies (Max 2)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: KenyaLocations.getConstituencies(_selectedCounty!).map((constituency) {
                    final isSelected = _selectedConstituencies.contains(constituency);
                    return FilterChip(
                      label: Text(constituency),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            if (_selectedConstituencies.length < 2) {
                              _selectedConstituencies.add(constituency);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Maximum 2 constituencies allowed')),
                              );
                            }
                          } else {
                            _selectedConstituencies.remove(constituency);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],

              // Ward Selection
              if (_selectedCoverageLevel == 'WARD' && _selectedCounty != null) ...[
                const SizedBox(height: 16),
                const Text('Select Wards (Max 5)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...KenyaLocations.getConstituencies(_selectedCounty!).map((constituency) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(constituency, style: const TextStyle(color: Colors.grey)),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children: KenyaLocations.getWards(constituency).map((ward) {
                          final isSelected = _selectedWards.contains(ward);
                          return FilterChip(
                            label: Text(ward),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  if (_selectedWards.length < 5) {
                                    _selectedWards.add(ward);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Maximum 5 wards allowed')),
                                    );
                                  }
                                } else {
                                  _selectedWards.remove(ward);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                }),
              ],
            ],

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        AuthService.currentUser?.primaryRole == 'helper'
                          ? 'Update Profile'
                          : 'Save Profile & Register',
                        style: const TextStyle(fontSize: 16)
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
