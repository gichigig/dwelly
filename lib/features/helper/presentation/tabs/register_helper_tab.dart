import 'package:flutter/material.dart';
import 'package:realestate/core/data/kenya_locations.dart';
import 'package:realestate/core/services/auth_service.dart';
import 'package:realestate/core/services/helper_service.dart';

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
  List<String> _selectedConstituencies = [];
  List<String> _selectedWards = [];

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
      _selectedConstituencies = List.from(user.helperConstituencies);
      _selectedWards = List.from(user.helperWards);
    }
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCounty == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a county')),
      );
      return;
    }
    if (_selectedCoverageLevel == 'CONSTITUENCY' && _selectedConstituencies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one constituency')),
      );
      return;
    }
    if (_selectedCoverageLevel == 'WARD' && _selectedWards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one ward')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = AuthService.currentUser;
      if (user != null && user.primaryRole != 'helper') {
        await AuthService.setPrimaryRole('helper');
      }

      await HelperService.updateHelperProfile(
        price: double.parse(_priceController.text),
        coverageLevel: _selectedCoverageLevel,
        county: _selectedCounty,
        constituencies: _selectedConstituencies,
        wards: _selectedWards,
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
          'Please sign in to register as a helper.',
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
                ? 'Update your pricing and coverage area below. You are currently registered as a helper!'
                : 'Set your pricing and coverage area to start accepting jobs.',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // Pricing
            TextFormField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Price per Job (KES)',
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
            const SizedBox(height: 24),

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
              const SizedBox(height: 24),
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
              const SizedBox(height: 24),
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
