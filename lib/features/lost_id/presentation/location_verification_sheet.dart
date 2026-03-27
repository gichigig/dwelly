import 'package:flutter/material.dart';
import '../../../core/data/kenya_locations.dart';
import '../../../core/services/device_location_service.dart';

/// Result from location verification
class LocationVerificationResult {
  final String displayName;
  final String? ward;
  final String? constituency;
  final String? county;

  LocationVerificationResult({
    required this.displayName,
    this.ward,
    this.constituency,
    this.county,
  });
}

/// Shows a bottom sheet to verify and optionally change the detected location
Future<LocationVerificationResult?> showLocationVerificationSheet(
  BuildContext context, {
  required DeviceLocationResult detectedLocation,
}) {
  return showModalBottomSheet<LocationVerificationResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => LocationVerificationSheet(
      detectedLocation: detectedLocation,
    ),
  );
}

class LocationVerificationSheet extends StatefulWidget {
  final DeviceLocationResult detectedLocation;

  const LocationVerificationSheet({
    super.key,
    required this.detectedLocation,
  });

  @override
  State<LocationVerificationSheet> createState() => _LocationVerificationSheetState();
}

class _LocationVerificationSheetState extends State<LocationVerificationSheet> {
  final _searchController = TextEditingController();
  List<LocationSearchResult> _suggestions = [];
  bool _isSearching = false;
  
  // Selected location (starts with detected location)
  String? _selectedWard;
  String? _selectedConstituency;
  String? _selectedCounty;
  String _displayName = '';

  @override
  void initState() {
    super.initState();
    // Initialize with detected location
    _selectedWard = widget.detectedLocation.ward;
    _selectedConstituency = widget.detectedLocation.constituency;
    _selectedCounty = widget.detectedLocation.county;
    _displayName = widget.detectedLocation.displayName;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (query.length < 2) {
      setState(() {
        _suggestions = [];
        _isSearching = false;
      });
      return;
    }

    final results = KenyaLocations.searchLocations(query);
    setState(() {
      _suggestions = results;
      _isSearching = true;
    });
  }

  void _selectLocation(LocationSearchResult location) {
    setState(() {
      _selectedWard = location.ward;
      _selectedConstituency = location.constituency;
      _selectedCounty = location.county;
      _displayName = location.name;
      _searchController.clear();
      _suggestions = [];
      _isSearching = false;
    });
  }

  void _confirmLocation() {
    Navigator.pop(
      context,
      LocationVerificationResult(
        displayName: _displayName,
        ward: _selectedWard,
        constituency: _selectedConstituency,
        county: _selectedCounty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Title
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Verify Your Location',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              
              const Divider(height: 1),
              
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Detected location card
                    Card(
                      elevation: 0,
                      color: colorScheme.primaryContainer.withOpacity(0.3),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: colorScheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Detected Location',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildLocationRow('Ward', _selectedWard),
                            _buildLocationRow('Constituency', _selectedConstituency),
                            _buildLocationRow('County', _selectedCounty),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Search to change location
                    Text(
                      'Not correct? Search for your location:',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search ward, constituency, or county...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _suggestions = [];
                                    _isSearching = false;
                                  });
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                      ),
                      onChanged: _onSearchChanged,
                    ),
                    
                    // Search results
                    if (_suggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _suggestions.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final location = _suggestions[index];
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                location.type == LocationType.ward
                                    ? Icons.location_city
                                    : location.type == LocationType.constituency
                                        ? Icons.apartment
                                        : Icons.map,
                                size: 20,
                                color: colorScheme.primary,
                              ),
                              title: Text(location.name),
                              subtitle: Text(
                                location.type == LocationType.ward
                                    ? '${location.constituency}, ${location.county}'
                                    : location.type == LocationType.constituency
                                        ? location.county ?? ''
                                        : 'County',
                                style: theme.textTheme.bodySmall,
                              ),
                              onTap: () => _selectLocation(location),
                            );
                          },
                        ),
                      ),
                    ],
                    
                    if (_isSearching && _suggestions.isEmpty) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          'No locations found',
                          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              
              // Confirm button
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: FilledButton.icon(
                    onPressed: _confirmLocation,
                    icon: const Icon(Icons.check),
                    label: Text('Confirm: $_displayName'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLocationRow(String label, String? value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? 'Not detected',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
