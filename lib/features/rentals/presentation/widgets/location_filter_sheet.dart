import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/data/kenya_locations.dart';
import '../../../../core/services/device_location_service.dart';
import '../../../../core/services/rental_service.dart';
import '../../domain/rental_filters.dart';

/// A bottom sheet for filtering rentals by location
/// Supports searching by nickname/area name and will suggest wards if not found
class LocationFilterSheet extends StatefulWidget {
  final String? initialQuery;
  final Function(LocationFilterResult) onApply;

  const LocationFilterSheet({
    super.key,
    this.initialQuery,
    required this.onApply,
  });

  @override
  State<LocationFilterSheet> createState() => _LocationFilterSheetState();
}

class _LocationFilterSheetState extends State<LocationFilterSheet> {
  final _searchController = TextEditingController();
  List<LocationSearchResult> _suggestions = [];
  LocationSearchResult? _selectedLocation;
  bool _showWardSuggestion = false;

  // Dynamic popular areas from backend
  List<PopularAreaResult> _popularAreas = [];
  bool _loadingPopularAreas = true;

  // Device location state
  bool _gettingDeviceLocation = false;
  DeviceLocationResult? _deviceLocation;

  // Room type filter
  UnitType? _selectedUnitType;

  // Backend search debounce
  Timer? _backendSearchDebounce;

  // Price range filter
  RangeValues _priceRange = const RangeValues(0, 100000);
  bool _priceFilterActive = false;

  @override
  void initState() {
    super.initState();
    _fetchPopularAreas();
    _checkCachedLocation();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchController.text = widget.initialQuery!;
      // Try to find and auto-select a matching location
      final results = KenyaLocations.searchLocations(widget.initialQuery!);
      final exactMatch = results
          .where(
            (r) => r.name.toLowerCase() == widget.initialQuery!.toLowerCase(),
          )
          .firstOrNull;
      if (exactMatch != null) {
        _selectedLocation = exactMatch;
        // Don't show suggestions since we have an exact match
      } else {
        _onSearchChanged(widget.initialQuery!);
      }
    }
  }

  Future<void> _checkCachedLocation() async {
    final cached = await DeviceLocationService.getCachedLocation();
    if (mounted && cached != null && cached.hasLocationData) {
      setState(() {
        _deviceLocation = cached;
      });
    }
  }

  Future<void> _fetchPopularAreas() async {
    try {
      final areas = await RentalService.getPopularAreas(limit: 15);
      if (mounted) {
        setState(() {
          _popularAreas = areas;
          _loadingPopularAreas = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingPopularAreas = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    _backendSearchDebounce?.cancel();
    if (query.length < 2) {
      setState(() {
        _suggestions = [];
        _showWardSuggestion = false;
      });
      return;
    }

    // Instant local search
    final results = KenyaLocations.searchLocations(query);
    setState(() {
      _suggestions = results;
      _showWardSuggestion = results.isEmpty && query.length >= 3;
      _selectedLocation = null;
    });

    // Debounced backend search for dynamic nicknames from listings
    _backendSearchDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      try {
        final backendResults = await RentalService.searchAreas(query);
        if (!mounted || _searchController.text != query) return;

        final existingNames = _suggestions
            .map((r) => r.name.toLowerCase())
            .toSet();
        final newResults = <LocationSearchResult>[];

        for (final br in backendResults) {
          if (!existingNames.contains(br.name.toLowerCase())) {
            newResults.add(br);
            existingNames.add(br.name.toLowerCase());
          } else if (br.listingCount > 0) {
            // Enrich existing result with listing count
            _suggestions = _suggestions.map((r) {
              if (r.name.toLowerCase() == br.name.toLowerCase()) {
                return LocationSearchResult(
                  name: r.name,
                  type: r.type,
                  county: br.county ?? r.county,
                  constituency: br.constituency ?? r.constituency,
                  ward: br.ward ?? r.ward,
                  listingCount: br.listingCount,
                );
              }
              return r;
            }).toList();
          }
        }

        setState(() {
          _suggestions = [..._suggestions, ...newResults];
          _suggestions.sort((a, b) {
            if (a.listingCount != b.listingCount) {
              return b.listingCount.compareTo(a.listingCount);
            }
            return a.type.index.compareTo(b.type.index);
          });
          if (_suggestions.length > 20) {
            _suggestions = _suggestions.sublist(0, 20);
          }
          _showWardSuggestion = _suggestions.isEmpty && query.length >= 3;
        });
      } catch (_) {
        // Local results still showing
      }
    });
  }

  void _selectLocation(LocationSearchResult location) {
    setState(() {
      _selectedLocation = location;
      _searchController.text = location.name;
      _suggestions = [];
      _showWardSuggestion = false;
    });
  }

  void _applyFilter() {
    final int? minPrice = _priceFilterActive ? _priceRange.start.round() : null;
    final int? maxPrice = _priceFilterActive ? _priceRange.end.round() : null;

    if (_selectedLocation != null) {
      widget.onApply(
        LocationFilterResult(
          query: _searchController.text,
          ward:
              _selectedLocation!.type == LocationType.ward ||
                  _selectedLocation!.type == LocationType.area
              ? _selectedLocation!.ward ?? _selectedLocation!.name
              : null,
          constituency: _selectedLocation!.constituency,
          county: _selectedLocation!.county,
          nickname: _selectedLocation!.type == LocationType.area
              ? _selectedLocation!.name
              : null,
          locationType: _selectedLocation!.type,
          unitType: _selectedUnitType,
          minPrice: minPrice,
          maxPrice: maxPrice,
        ),
      );
      Navigator.pop(context);
    } else if (_searchController.text.isNotEmpty ||
        _selectedUnitType != null ||
        _priceFilterActive) {
      // User typed something, selected a room type, or set price range
      widget.onApply(
        LocationFilterResult(
          query: _searchController.text,
          nickname: _searchController.text.isNotEmpty
              ? _searchController.text
              : null,
          unitType: _selectedUnitType,
          minPrice: minPrice,
          maxPrice: maxPrice,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _backendSearchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Filter by Location',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText:
                              'Search by area name or ward (e.g. Ruaka, Kilimani)',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearchChanged('');
                                  },
                                  icon: const Icon(Icons.clear),
                                )
                              : null,
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: _onSearchChanged,
                      ),
                    ),
                    if (_selectedLocation != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: Wrap(
                          children: [
                            Chip(
                              avatar: Icon(
                                _getLocationIcon(_selectedLocation!.type),
                                size: 18,
                              ),
                              label: Text(_selectedLocation!.name),
                              deleteIcon: const Icon(Icons.close, size: 18),
                              onDeleted: () {
                                setState(() {
                                  _selectedLocation = null;
                                  _searchController.clear();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    if (_suggestions.isNotEmpty)
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _suggestions.length,
                        itemBuilder: (context, index) {
                          final location = _suggestions[index];
                          return _buildSuggestionTile(location);
                        },
                      ),
                    if (_showWardSuggestion)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: colorScheme.onTertiaryContainer,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Area not found. Try searching by the official ward name for more accurate results.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onTertiaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_searchController.text.isEmpty &&
                        _selectedLocation == null)
                      _buildUseMyLocation(),
                    if (_searchController.text.isEmpty &&
                        _selectedLocation == null)
                      _buildPopularAreas(),
                    _buildRoomTypeFilter(),
                    _buildPriceRangeFilter(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, viewInsetsBottom + 12),
              child: FilledButton(
                onPressed:
                    _selectedLocation != null ||
                        _searchController.text.isNotEmpty ||
                        _selectedUnitType != null ||
                        _priceFilterActive
                    ? _applyFilter
                    : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Apply Filter'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionTile(LocationSearchResult location) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: location.hasListings
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          _getLocationIcon(location.type),
          color: location.hasListings
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurface.withOpacity(0.5),
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Expanded(child: Text(location.name)),
          if (location.hasListings)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${location.listingCount}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        _getLocationSubtitle(location),
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.6),
        ),
      ),
      trailing: _getLocationTypeChip(location.type),
      onTap: () => _selectLocation(location),
    );
  }

  Widget _buildUseMyLocation() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Use my location tile
          InkWell(
            onTap: _gettingDeviceLocation ? null : _getDeviceLocationAndApply,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _gettingDeviceLocation
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          )
                        : Icon(
                            Icons.my_location,
                            color: colorScheme.onPrimaryContainer,
                            size: 20,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Use my current location',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        if (_deviceLocation != null &&
                            _deviceLocation!.hasLocationData)
                          Text(
                            'Last: ${_deviceLocation!.displayName}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.6),
                            ),
                          )
                        else
                          Text(
                            'Find rentals near you',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: colorScheme.primary.withOpacity(0.7),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _getDeviceLocationAndApply() async {
    setState(() {
      _gettingDeviceLocation = true;
    });

    try {
      // Check permission first
      final permission = await DeviceLocationService.checkPermission();

      if (permission == LocationPermission.denied) {
        final newPermission = await DeviceLocationService.requestPermission();
        if (newPermission == null ||
            newPermission == LocationPermission.denied ||
            newPermission == LocationPermission.deniedForever) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  newPermission == null
                      ? 'Location services are disabled. Please enable GPS.'
                      : 'Location permission denied. Please enable it in settings.',
                ),
              ),
            );
          }
          setState(() {
            _gettingDeviceLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permission permanently denied. Enable in device settings.',
              ),
            ),
          );
        }
        setState(() {
          _gettingDeviceLocation = false;
        });
        return;
      }

      // Get current location
      final result = await DeviceLocationService.getCurrentLocation();

      if (mounted) {
        if (result.success && result.hasLocationData) {
          setState(() {
            _deviceLocation = result;
            _gettingDeviceLocation = false;
          });

          // Apply as filter result
          widget.onApply(
            LocationFilterResult(
              query: result.displayName,
              ward: result.ward,
              constituency: result.constituency,
              county: result.county,
              nickname: result.areaName,
              locationType: LocationType.area,
              isDeviceLocation: true,
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.errorMessage ?? 'Could not determine your location',
              ),
            ),
          );
          setState(() {
            _gettingDeviceLocation = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to get location. Please try again.'),
          ),
        );
        setState(() {
          _gettingDeviceLocation = false;
        });
      }
    }
  }

  Widget _buildPopularAreas() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Fallback areas if API call fails
    final fallbackAreas = [
      'Kilimani',
      'Kileleshwa',
      'Westlands',
      'Ruaka',
      'Rongai',
      'Kitengela',
      'South B',
      'South C',
      'Karen',
      'Lavington',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Popular Areas',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              if (_loadingPopularAreas) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (_popularAreas.isNotEmpty)
            // Dynamic popular areas from backend (with listing counts)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _popularAreas.map((area) {
                return ActionChip(
                  avatar: area.listingCount > 0
                      ? CircleAvatar(
                          backgroundColor: colorScheme.primary.withValues(
                            alpha: 0.2,
                          ),
                          radius: 10,
                          child: Text(
                            '${area.listingCount}',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        )
                      : null,
                  label: Text(area.name),
                  onPressed: () {
                    _searchController.text = area.name;
                    _onSearchChanged(area.name);
                  },
                );
              }).toList(),
            )
          else
            // Fallback static areas
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: fallbackAreas.map((area) {
                return ActionChip(
                  label: Text(area),
                  onPressed: () {
                    _searchController.text = area;
                    _onSearchChanged(area);
                  },
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildRoomTypeFilter() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Room Type',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              if (_selectedUnitType != null)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedUnitType = null;
                    });
                  },
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: UnitType.values.map((type) {
              final isSelected = _selectedUnitType == type;
              return FilterChip(
                selected: isSelected,
                showCheckmark: false,
                label: Text(type.label),
                avatar: isSelected
                    ? Icon(
                        Icons.check_circle,
                        size: 18,
                        color: colorScheme.onPrimaryContainer,
                      )
                    : Icon(
                        _getRoomTypeIcon(type),
                        size: 18,
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                selectedColor: colorScheme.primaryContainer,
                onSelected: (selected) {
                  setState(() {
                    _selectedUnitType = selected ? type : null;
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRangeFilter() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String formatPrice(double value) {
      if (value >= 1000) {
        final k = value / 1000;
        return k == k.roundToDouble()
            ? 'KES ${k.toInt()}K'
            : 'KES ${k.toStringAsFixed(1)}K';
      }
      return 'KES ${value.toInt()}';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Price Range',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              if (_priceFilterActive)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _priceRange = const RangeValues(0, 100000);
                      _priceFilterActive = false;
                    });
                  },
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _priceFilterActive
                ? '${formatPrice(_priceRange.start)} – ${formatPrice(_priceRange.end)}'
                : 'Any price',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _priceFilterActive
                  ? colorScheme.primary
                  : colorScheme.onSurface.withOpacity(0.5),
              fontWeight: _priceFilterActive
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 8),
          RangeSlider(
            values: _priceRange,
            min: 0,
            max: 100000,
            divisions: 100,
            labels: RangeLabels(
              formatPrice(_priceRange.start),
              formatPrice(_priceRange.end),
            ),
            onChanged: (values) {
              setState(() {
                _priceRange = values;
                _priceFilterActive = true;
              });
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'KES 0',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
                Text(
                  'KES 100K',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getRoomTypeIcon(UnitType type) {
    switch (type) {
      case UnitType.bedsitter:
        return Icons.single_bed;
      case UnitType.singleRoom:
        return Icons.bed;
      case UnitType.doubleRoom:
        return Icons.king_bed;
      case UnitType.room:
        return Icons.door_back_door_outlined;
      case UnitType.studio:
        return Icons.weekend;
      case UnitType.airBnB:
        return Icons.travel_explore;
      case UnitType.apartment:
        return Icons.apartment;
      case UnitType.house:
        return Icons.home;
      case UnitType.condo:
        return Icons.location_city;
      case UnitType.townhouse:
        return Icons.holiday_village;
      case UnitType.villa:
        return Icons.villa;
      case UnitType.penthouse:
        return Icons.roofing;
      case UnitType.duplex:
        return Icons.home_work;
      case UnitType.office:
        return Icons.business;
      case UnitType.shop:
        return Icons.storefront;
      case UnitType.warehouse:
        return Icons.warehouse;
      case UnitType.other:
        return Icons.other_houses;
    }
  }

  IconData _getLocationIcon(LocationType type) {
    switch (type) {
      case LocationType.county:
        return Icons.map_outlined;
      case LocationType.constituency:
        return Icons.location_city_outlined;
      case LocationType.ward:
        return Icons.place_outlined;
      case LocationType.area:
        return Icons.location_on;
    }
  }

  String _getLocationSubtitle(LocationSearchResult location) {
    final parts = <String>[];
    if (location.ward != null && location.type != LocationType.ward) {
      parts.add(location.ward!);
    }
    if (location.constituency != null) {
      parts.add(location.constituency!);
    }
    if (location.county != null) {
      parts.add(location.county!);
    }
    return parts.join(', ');
  }

  Widget _getLocationTypeChip(LocationType type) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String label;
    Color color;
    switch (type) {
      case LocationType.county:
        label = 'County';
        color = colorScheme.tertiary;
        break;
      case LocationType.constituency:
        label = 'Constituency';
        color = colorScheme.secondary;
        break;
      case LocationType.ward:
        label = 'Ward';
        color = colorScheme.primary;
        break;
      case LocationType.area:
        label = 'Popular';
        color = Colors.orange;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Result from the location filter
class LocationFilterResult {
  final String query;
  final String? ward;
  final String? constituency;
  final String? county;
  final String? nickname;
  final LocationType? locationType;
  final bool isDeviceLocation;
  final UnitType? unitType; // Selected room type filter
  final int? minPrice; // Min price filter (KES)
  final int? maxPrice; // Max price filter (KES)

  const LocationFilterResult({
    required this.query,
    this.ward,
    this.constituency,
    this.county,
    this.nickname,
    this.locationType,
    this.isDeviceLocation = false,
    this.unitType,
    this.minPrice,
    this.maxPrice,
  });

  bool get hasLocation =>
      ward != null || constituency != null || county != null;

  @override
  String toString() =>
      'LocationFilterResult(query: $query, ward: $ward, constituency: $constituency, county: $county, nickname: $nickname, isDeviceLocation: $isDeviceLocation, unitType: $unitType, price: $minPrice-$maxPrice)';
}

/// Show the location filter bottom sheet
Future<LocationFilterResult?> showLocationFilterSheet(
  BuildContext context, {
  String? initialQuery,
}) async {
  LocationFilterResult? result;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => LocationFilterSheet(
        initialQuery: initialQuery,
        onApply: (r) => result = r,
      ),
    ),
  );

  return result;
}
