import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/di/providers.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/device_location_service.dart';
import '../../../core/services/rental_service.dart' hide RentalFilters;
import '../../../core/widgets/empty_state.dart';
import '../data/rentals_repo.dart';
import '../domain/rental_filters.dart';
import 'widgets/floating_filter_bubble.dart';
import 'widgets/location_filter_sheet.dart';
import '../../../core/data/kenya_locations.dart';

class RentalsExploreView extends ConsumerStatefulWidget {
  const RentalsExploreView({super.key});

  @override
  ConsumerState<RentalsExploreView> createState() => _RentalsExploreViewState();
}

class _RentalsExploreViewState extends ConsumerState<RentalsExploreView> {
  final _searchCtrl = TextEditingController();
  final _scrollController = ScrollController();
  RentalFilters _filters = const RentalFilters();
  bool _filterApplied = false;
  String? _resolvedLocation;
  List<String> _nearbyAreas = [];

  // Device location state
  bool _loadingDeviceLocation = true;
  bool _locationPermissionDenied = false;
  DeviceLocationResult? _deviceLocation;
  bool _usingDeviceLocation = false;
  bool _showingGeneralResults =
      false; // True when showing general results due to no local results

  // FYP (For You Page) preferences
  bool _usingFypPreferences = false;
  List<String> _fypSearchTerms = [];

  // Typewriter effect state
  Timer? _typewriterTimer;
  int _typewriterIndex = 0;
  String _typewriterText = '';
  int _currentPlaceholderIndex = 0;
  bool _isTyping = true; // true = typing, false = deleting

  // Search autocomplete state
  final _searchFocusNode = FocusNode();
  List<LocationSearchResult> _searchResults = [];
  Timer? _backendSearchDebounce;

  // Inline filter state (visible on explore tab)
  bool _showPriceSlider = false;
  RangeValues _priceRange = const RangeValues(0, 100000);

  static const List<String> _placeholderTexts = [
    'Search "Ruaka"',
    'Search "Rongai"',
    'Search "Kilimani"',
    'Search "South B"',
    'Search "Westlands"',
    'Search "Kileleshwa"',
    'Search "Lavington"',
    'Try "Near me"',
  ];

  @override
  void initState() {
    super.initState();
    _initLocationAndFyp();
    _startTypewriterEffect();
    _searchFocusNode.addListener(_onSearchFocusChange);
  }

  void _startTypewriterEffect() {
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // Don't animate if user has typed something, location is loading, or search is focused
      if (_searchCtrl.text.isNotEmpty ||
          _loadingDeviceLocation ||
          _searchFocusNode.hasFocus) {
        return;
      }

      setState(() {
        final currentText = _placeholderTexts[_currentPlaceholderIndex];

        if (_isTyping) {
          // Typing
          if (_typewriterIndex < currentText.length) {
            _typewriterText = currentText.substring(0, _typewriterIndex + 1);
            _typewriterIndex++;
          } else {
            // Pause at end before deleting
            _isTyping = false;
            // Add a delay before starting to delete
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted) setState(() {});
            });
          }
        } else {
          // Deleting
          if (_typewriterIndex > 0) {
            _typewriterIndex--;
            _typewriterText = currentText.substring(0, _typewriterIndex);
          } else {
            // Move to next placeholder
            _isTyping = true;
            _currentPlaceholderIndex =
                (_currentPlaceholderIndex + 1) % _placeholderTexts.length;
          }
        }
      });
    });
  }

  Future<void> _initLocationAndFyp() async {
    // First check if user has FYP preferences
    final user = AuthService.currentUser;
    if (user != null && user.hasFypPreferences) {
      _applyFypPreferences(user.fypWards, user.fypNicknames);
      return;
    }

    // Otherwise use device location
    await _initDeviceLocation();
  }

  void _applyFypPreferences(List<String> wards, List<String> nicknames) {
    final allTerms = [...wards, ...nicknames];
    if (allTerms.isEmpty) return;

    final displayText = allTerms.length <= 2
        ? allTerms.join(', ')
        : '${allTerms.take(2).join(', ')} +${allTerms.length - 2} more';

    setState(() {
      _loadingDeviceLocation = false;
      _usingFypPreferences = true;
      _fypSearchTerms = allTerms;
      _filters = _filters.copyWith(
        locationQuery: displayText,
        fypTerms: allTerms,
      );
      _searchCtrl.text = displayText;
      _resolvedLocation = displayText;
    });
  }

  Future<void> _initDeviceLocation() async {
    // Check if user previously denied location
    final wasDenied = await DeviceLocationService.hasUserDeniedLocation();

    if (wasDenied) {
      // Re-check actual permission state — user may have re-enabled in system settings
      final currentPermission = await DeviceLocationService.checkPermission();
      if (currentPermission == LocationPermission.always ||
          currentPermission == LocationPermission.whileInUse) {
        // User re-granted permission via system settings — clear the denied flag
        await DeviceLocationService.setUserDeniedLocation(false);
        await _fetchDeviceLocation();
        return;
      }

      // Still denied — try cached location
      final cached = await DeviceLocationService.getCachedLocation();
      if (cached != null && cached.hasLocationData) {
        _applyDeviceLocation(cached);
      } else {
        setState(() {
          _loadingDeviceLocation = false;
          _locationPermissionDenied = true;
        });
      }
      return;
    }

    // Check if location service is even enabled
    final serviceEnabled =
        await DeviceLocationService.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Service off but user hasn't denied permission — try cached location,
      // then fall through to fetch which will prompt to enable GPS
      final cached = await DeviceLocationService.getCachedLocation();
      if (cached != null && cached.hasLocationData) {
        _applyDeviceLocation(cached);
        return;
      }
    }

    // Check current permission status
    final permission = await DeviceLocationService.checkPermission();

    if (permission == LocationPermission.deniedForever) {
      // Try to use cached location
      final cached = await DeviceLocationService.getCachedLocation();
      if (cached != null && cached.hasLocationData) {
        _applyDeviceLocation(cached);
      } else {
        setState(() {
          _loadingDeviceLocation = false;
          _locationPermissionDenied = true;
        });
      }
      return;
    }

    // Permission granted or can be requested — proceed to fetch
    await _fetchDeviceLocation();
  }

  Future<void> _fetchDeviceLocation() async {
    setState(() {
      _loadingDeviceLocation = true;
    });

    final result = await DeviceLocationService.getCurrentLocation();

    if (result.success && result.hasLocationData) {
      _applyDeviceLocation(result);
    } else if (result.success &&
        !result.hasLocationData &&
        result.latitude != 0) {
      // We got GPS coordinates but ward resolution didn't match any known area
      // Still cache the coordinates and show a generic location
      print(
        '[ExploreView] Got coordinates (${result.latitude}, ${result.longitude}) but no ward match',
      );
      _applyDeviceLocation(
        DeviceLocationResult(
          latitude: result.latitude,
          longitude: result.longitude,
          ward: null,
          constituency: null,
          county: 'Nearby',
          areaName: 'My Location',
          success: true,
        ),
      );
    } else {
      print('[ExploreView] Location failed: ${result.errorMessage}');
      setState(() {
        _loadingDeviceLocation = false;
        if (result.errorMessage?.contains('denied') == true) {
          _locationPermissionDenied = true;
        }
      });
    }
  }

  void _applyDeviceLocation(DeviceLocationResult location) {
    setState(() {
      _deviceLocation = location;
      _loadingDeviceLocation = false;
      _usingDeviceLocation = true;

      // Get detailed location string (ward, constituency, county)
      final locationText = location.detailedDisplayName;

      // Apply device location as default filter
      _filters = _filters.copyWith(
        locationQuery: locationText,
        ward: location.ward,
        constituency: location.constituency,
        county: location.county,
        nickname: location.areaName,
      );
      _searchCtrl.text = locationText;
      _resolvedLocation = locationText;
    });
  }

  Future<void> _requestLocationPermission() async {
    final permission = await DeviceLocationService.requestPermission();

    if (permission == null) {
      // Location service is disabled
      setState(() {
        _locationPermissionDenied = true;
      });
      return;
    }

    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      await DeviceLocationService.setUserDeniedLocation(false);
      _fetchDeviceLocation();
    } else {
      setState(() {
        _locationPermissionDenied = true;
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollController.dispose();
    _typewriterTimer?.cancel();
    _backendSearchDebounce?.cancel();
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ==================== Search Autocomplete ====================

  void _onSearchFocusChange() {
    if (_searchFocusNode.hasFocus) {
      // If search bar has pre-filled device location text, select all so user can type fresh
      if (_usingDeviceLocation && _searchCtrl.text.isNotEmpty) {
        _searchCtrl.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchCtrl.text.length,
        );
      }
    } else {
      // Clear suggestions when losing focus (with small delay for tap to register)
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_searchFocusNode.hasFocus) {
          setState(() {
            _searchResults = [];
          });
        }
      });
    }
    // Rebuild to update hintText when focus changes
    if (mounted) setState(() {});
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      _backendSearchDebounce?.cancel();
      return;
    }
    // Instant local search (static wards/constituencies/areas)
    setState(() {
      _searchResults = KenyaLocations.searchLocations(query);
    });

    // Debounced backend search for dynamic nicknames from listings
    _backendSearchDebounce?.cancel();
    _backendSearchDebounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      try {
        final backendResults = await RentalService.searchAreas(query);
        if (!mounted || _searchCtrl.text != query) return;

        // Merge backend results, avoiding duplicates
        final existingNames = _searchResults
            .map((r) => r.name.toLowerCase())
            .toSet();
        final newResults = <LocationSearchResult>[];

        // Add backend results with listing counts first (they have real data)
        for (final br in backendResults) {
          if (!existingNames.contains(br.name.toLowerCase())) {
            newResults.add(br);
            existingNames.add(br.name.toLowerCase());
          } else if (br.listingCount > 0) {
            // Replace static result with backend result that has listing count
            _searchResults = _searchResults.map((r) {
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

        // Sort: items with listings first, then by type priority
        _searchResults = [..._searchResults, ...newResults];
        _searchResults.sort((a, b) {
          if (a.listingCount != b.listingCount) {
            return b.listingCount.compareTo(a.listingCount);
          }
          return a.type.index.compareTo(b.type.index);
        });

        // Limit to 20 results
        if (_searchResults.length > 20) {
          _searchResults = _searchResults.sublist(0, 20);
        }

        if (mounted) setState(() {});
      } catch (_) {
        // Silently fail - local results still showing
      }
    });
  }

  Widget _buildInlineSuggestions(ColorScheme colorScheme, ThemeData theme) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _searchResults.length,
        itemBuilder: (ctx, index) {
          final result = _searchResults[index];
          return InkWell(
            onTap: () => _onSuggestionSelected(result),
            borderRadius: index == 0
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : index == _searchResults.length - 1
                ? const BorderRadius.vertical(bottom: Radius.circular(12))
                : BorderRadius.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _getTypeIcon(result.type),
                    size: 20,
                    color: _getTypeColor(result.type),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.displayName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          result.subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getTypeColor(result.type).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getTypeLabel(result.type),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: _getTypeColor(result.type),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _onSuggestionSelected(LocationSearchResult result) {
    _searchFocusNode.unfocus();
    setState(() {
      _searchResults = [];
      _searchCtrl.text = result.name;
      _filterApplied = true;
      _usingDeviceLocation = false;
      _usingFypPreferences = false;
      _resolvedLocation = result.displayName;
      switch (result.type) {
        case LocationType.county:
          _filters = RentalFilters(
            locationQuery: result.name,
            county: result.name,
          );
        case LocationType.constituency:
          _filters = RentalFilters(
            locationQuery: result.name,
            constituency: result.name,
            county: result.county,
          );
        case LocationType.ward:
          _filters = RentalFilters(
            locationQuery: result.name,
            ward: result.name,
            constituency: result.constituency,
            county: result.county,
          );
        case LocationType.area:
          _filters = RentalFilters(
            locationQuery: result.name,
            nickname: result.name,
            ward: result.ward,
            constituency: result.constituency,
            county: result.county,
          );
      }
    });
  }

  void _onSearchSubmitted(String query) {
    _searchFocusNode.unfocus();
    setState(() {
      _searchResults = [];
    });
    if (query.isNotEmpty) {
      final results = KenyaLocations.searchLocations(query);
      if (results.isNotEmpty) {
        _onSuggestionSelected(results.first);
      } else {
        setState(() {
          _filters = RentalFilters(locationQuery: query, nickname: query);
          _filterApplied = true;
          _usingDeviceLocation = false;
          _resolvedLocation = query;
        });
      }
    }
  }

  IconData _getTypeIcon(LocationType type) {
    switch (type) {
      case LocationType.county:
        return Icons.location_city;
      case LocationType.constituency:
        return Icons.pin_drop;
      case LocationType.ward:
        return Icons.holiday_village;
      case LocationType.area:
        return Icons.star;
    }
  }

  Color _getTypeColor(LocationType type) {
    switch (type) {
      case LocationType.county:
        return Colors.blue;
      case LocationType.constituency:
        return Colors.green;
      case LocationType.ward:
        return Colors.purple;
      case LocationType.area:
        return Colors.amber;
    }
  }

  String _getTypeLabel(LocationType type) {
    switch (type) {
      case LocationType.county:
        return 'County';
      case LocationType.constituency:
        return 'Constituency';
      case LocationType.ward:
        return 'Ward';
      case LocationType.area:
        return 'Area';
    }
  }

  void _openLocationFilter() async {
    // Pass a simple name (nickname or ward) so the filter sheet can match
    // and auto-select it, rather than the detailed display string
    final result = await showLocationFilterSheet(
      context,
      initialQuery:
          _filters.nickname ?? _filters.ward ?? _filters.locationQuery,
    );

    if (result != null) {
      setState(() {
        _filters = _filters.copyWith(
          locationQuery: result.query,
          nickname: result.nickname,
          ward: result.ward,
          constituency: result.constituency,
          county: result.county,
          unitType: result.unitType,
          minPrice: result.minPrice,
          maxPrice: result.maxPrice,
        );
        _filterApplied = true;
        _usingDeviceLocation = result.isDeviceLocation;
        _searchCtrl.text = result.query;
        if (result.query.isNotEmpty) {
          _resolvedLocation = result.query;
        }
      });
    }
  }

  void _clearFilter() {
    _searchResults = [];
    setState(() {
      _filterApplied = false;
      _searchCtrl.clear();
      _resolvedLocation = null;
      _nearbyAreas = [];
      _usingFypPreferences = false;
      _fypSearchTerms = [];
      _showPriceSlider = false;
      _priceRange = const RangeValues(0, 100000);

      // Try to reset to user's preferred state in priority order:
      // 1. FYP preferences
      // 2. Device location
      // 3. Clear all
      final user = AuthService.currentUser;
      if (user != null && user.hasFypPreferences) {
        _applyFypPreferences(user.fypWards, user.fypNicknames);
      } else if (_deviceLocation != null && _deviceLocation!.hasLocationData) {
        _applyDeviceLocation(_deviceLocation!);
      } else {
        _filters = const RentalFilters();
        _usingDeviceLocation = false;
      }
    });
  }

  void _useCurrentLocation() async {
    if (_locationPermissionDenied) {
      // Show dialog to request permission
      final shouldRequest = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Location Access'),
          content: const Text(
            'Allow location access to see rentals near you. '
            'You can always search any location manually.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not Now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Allow'),
            ),
          ],
        ),
      );

      if (shouldRequest == true) {
        await _requestLocationPermission();
      }
    } else {
      await _fetchDeviceLocation();
    }
  }

  /// Search with fallback to general results if no local results found
  Future<Map<String, dynamic>> _searchWithFallback(RentalsRepo repo) async {
    try {
      // FYP mode: use backend recommendations with 60:40 ward split
      if (_usingFypPreferences && _fypSearchTerms.isNotEmpty) {
        final result = await RentalService.getRecommendations(
          page: 0,
          size: 20,
          preferredAreas: _fypSearchTerms,
          ward: _filters.ward,
          constituency: _filters.constituency,
          nickname: _filters.nickname,
        );
        return {'rentals': result.rentals, 'isGeneral': false};
      }

      // Location filter: use backend smart location search
      if (_filters.hasLocationFilter) {
        final result = await RentalService.smartLocationSearch(
          nickname: _filters.nickname,
          ward: _filters.ward,
          constituency: _filters.constituency,
          county: _filters.county,
          includeNearby: _filters.includeNearby,
          minPrice: _filters.minPrice?.toDouble(),
          maxPrice: _filters.maxPrice?.toDouble(),
          propertyType: _filters.unitType?.backendName,
          page: 0,
          size: 20,
        );

        if (result.rentals.rentals.isNotEmpty) {
          return {'rentals': result.rentals.rentals, 'isGeneral': false};
        }

        // Fallback to general results if location search returns nothing
        if (_usingDeviceLocation) {
          final generalResult = await RentalService.getPaginated(
            page: 0,
            size: 20,
          );
          return {'rentals': generalResult.rentals, 'isGeneral': true};
        }

        return {'rentals': result.rentals.rentals, 'isGeneral': false};
      }

      // Unit type or price filter without location: use search with filters
      if (_filters.unitType != null ||
          _filters.minPrice != null ||
          _filters.maxPrice != null) {
        final result = await RentalService.smartLocationSearch(
          minPrice: _filters.minPrice?.toDouble(),
          maxPrice: _filters.maxPrice?.toDouble(),
          propertyType: _filters.unitType?.backendName,
          includeNearby: false,
          page: 0,
          size: 20,
        );
        return {'rentals': result.rentals.rentals, 'isGeneral': false};
      }

      // No filter: show general active rentals
      final result = await RentalService.getPaginated(page: 0, size: 20);
      return {'rentals': result.rentals, 'isGeneral': false};
    } catch (e) {
      print('Error searching rentals: $e');
      // Fallback to local repo search
      final localResults = await repo.search(_filters);
      return {'rentals': localResults, 'isGeneral': false};
    }
  }

  // ==================== Inline Filter Chips ====================

  Widget _buildInlineFilterChips(ColorScheme colorScheme, ThemeData theme) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // Price filter chip
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              selected: _filters.minPrice != null || _filters.maxPrice != null,
              showCheckmark: false,
              avatar: Icon(
                Icons.payments_outlined,
                size: 16,
                color: (_filters.minPrice != null || _filters.maxPrice != null)
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurface.withOpacity(0.6),
              ),
              label: Text(
                (_filters.minPrice != null || _filters.maxPrice != null)
                    ? _formatPriceChip(_filters.minPrice, _filters.maxPrice)
                    : 'Price',
              ),
              selectedColor: colorScheme.primaryContainer,
              onSelected: (_) {
                setState(() {
                  _showPriceSlider = !_showPriceSlider;
                });
              },
            ),
          ),
          // Unit type filter chips
          ...UnitType.values.map((type) {
            final isSelected = _filters.unitType == type;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                selected: isSelected,
                showCheckmark: false,
                avatar: isSelected
                    ? Icon(
                        Icons.check_circle,
                        size: 16,
                        color: colorScheme.onPrimaryContainer,
                      )
                    : Icon(
                        _getUnitTypeIcon(type),
                        size: 16,
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                label: Text(type.label),
                selectedColor: colorScheme.primaryContainer,
                onSelected: (selected) {
                  setState(() {
                    _filters = selected
                        ? _filters.copyWith(unitType: type)
                        : RentalFilters(
                            locationQuery: _filters.locationQuery,
                            nickname: _filters.nickname,
                            ward: _filters.ward,
                            constituency: _filters.constituency,
                            county: _filters.county,
                            minPrice: _filters.minPrice,
                            maxPrice: _filters.maxPrice,
                            bedrooms: _filters.bedrooms,
                            includeNearby: _filters.includeNearby,
                            fypTerms: _filters.fypTerms,
                          );
                    _filterApplied =
                        _filters.hasLocationFilter ||
                        _filters.unitType != null ||
                        _filters.minPrice != null;
                  });
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInlinePriceSlider(ColorScheme colorScheme, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                (_filters.minPrice != null || _filters.maxPrice != null)
                    ? _formatPriceChip(_filters.minPrice, _filters.maxPrice)
                    : 'Any price',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
              if (_filters.minPrice != null || _filters.maxPrice != null)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _priceRange = const RangeValues(0, 100000);
                      _filters = RentalFilters(
                        locationQuery: _filters.locationQuery,
                        nickname: _filters.nickname,
                        ward: _filters.ward,
                        constituency: _filters.constituency,
                        county: _filters.county,
                        unitType: _filters.unitType,
                        bedrooms: _filters.bedrooms,
                        includeNearby: _filters.includeNearby,
                        fypTerms: _filters.fypTerms,
                      );
                      _filterApplied =
                          _filters.hasLocationFilter ||
                          _filters.unitType != null;
                    });
                  },
                  child: Text(
                    'Clear',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          RangeSlider(
            values: _priceRange,
            min: 0,
            max: 100000,
            divisions: 100,
            labels: RangeLabels(
              _formatKes(_priceRange.start),
              _formatKes(_priceRange.end),
            ),
            onChanged: (values) {
              setState(() {
                _priceRange = values;
                _filters = _filters.copyWith(
                  minPrice: values.start.round(),
                  maxPrice: values.end.round(),
                );
                _filterApplied = true;
              });
            },
          ),
          Row(
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
        ],
      ),
    );
  }

  String _formatKes(double value) {
    if (value >= 1000) {
      final k = value / 1000;
      return k == k.roundToDouble()
          ? 'KES ${k.toInt()}K'
          : 'KES ${k.toStringAsFixed(1)}K';
    }
    return 'KES ${value.toInt()}';
  }

  String _formatPriceChip(int? min, int? max) {
    if (min == null && max == null) return 'Price';
    if (min != null && max != null && min == 0 && max == 100000) return 'Price';
    final minStr = min != null ? _formatKes(min.toDouble()) : 'KES 0';
    final maxStr = max != null ? _formatKes(max.toDouble()) : 'KES 100K';
    return '$minStr – $maxStr';
  }

  IconData _getUnitTypeIcon(UnitType type) {
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

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(rentalsRepoProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Search bar with filter button
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocusNode,
                      onChanged: _onSearchChanged,
                      onSubmitted: _onSearchSubmitted,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: _loadingDeviceLocation
                            ? 'Getting your location...'
                            : _searchCtrl.text.isEmpty
                            ? (_searchFocusNode.hasFocus
                                  ? 'Search ward, area or constituency...'
                                  : (_typewriterText.isNotEmpty
                                        ? _typewriterText
                                        : 'Search location...'))
                            : null,
                        prefixIcon: _loadingDeviceLocation
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton(
                                icon: Icon(
                                  Icons.search,
                                  color: colorScheme.primary,
                                ),
                                tooltip: 'Search locations',
                                onPressed: () {
                                  _searchFocusNode.requestFocus();
                                },
                              ),
                        suffixIcon:
                            (_filterApplied ||
                                _usingDeviceLocation ||
                                _searchCtrl.text.isNotEmpty)
                            ? IconButton(
                                onPressed: _clearFilter,
                                icon: const Icon(Icons.clear),
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Filter button
                  Container(
                    decoration: BoxDecoration(
                      color: _filterApplied
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      onPressed: _openLocationFilter,
                      icon: Icon(
                        Icons.filter_list,
                        color: _filterApplied
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                  // My Location button
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: _usingDeviceLocation
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      onPressed: _loadingDeviceLocation
                          ? null
                          : _useCurrentLocation,
                      tooltip: 'Use my location',
                      icon: _loadingDeviceLocation
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.onSurface.withOpacity(0.5),
                              ),
                            )
                          : Icon(
                              _usingDeviceLocation
                                  ? Icons.my_location
                                  : Icons.location_searching,
                              color: _usingDeviceLocation
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurface,
                            ),
                    ),
                  ),
                ],
              ),

              // Inline search suggestions
              if (_searchResults.isNotEmpty && _searchFocusNode.hasFocus)
                _buildInlineSuggestions(colorScheme, theme),

              // Show resolved location info or prompt to enable location
              if (_resolvedLocation != null ||
                  _usingDeviceLocation ||
                  _usingFypPreferences) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _usingFypPreferences
                        ? Colors.orange.withOpacity(0.15)
                        : _usingDeviceLocation
                        ? colorScheme.primaryContainer.withOpacity(0.5)
                        : colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _usingFypPreferences
                            ? Icons.tune
                            : _usingDeviceLocation
                            ? Icons.my_location
                            : Icons.location_on,
                        size: 16,
                        color: _usingFypPreferences
                            ? Colors.orange
                            : _usingDeviceLocation
                            ? colorScheme.primary
                            : colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _usingFypPreferences
                              ? 'Showing rentals from your preferences: $_resolvedLocation'
                              : _usingDeviceLocation
                              ? 'Showing rentals near you in ${_resolvedLocation ?? _deviceLocation?.displayName ?? ''}'
                              : 'Showing results for $_resolvedLocation'
                                    '${_nearbyAreas.isNotEmpty ? ' and nearby areas' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _usingFypPreferences
                                ? Colors.orange.shade700
                                : _usingDeviceLocation
                                ? colorScheme.primary
                                : colorScheme.onSecondaryContainer,
                            fontWeight:
                                (_usingDeviceLocation || _usingFypPreferences)
                                ? FontWeight.w600
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (!_loadingDeviceLocation &&
                  !_filterApplied &&
                  !_locationPermissionDenied) ...[
                // Prompt to use location
                const SizedBox(height: 8),
                InkWell(
                  onTap: _useCurrentLocation,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.tertiary.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_searching,
                          size: 16,
                          color: colorScheme.tertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tap to find rentals near you',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.tertiary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 12,
                          color: colorScheme.tertiary.withOpacity(0.7),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 8),

              // Inline filter chips row
              _buildInlineFilterChips(colorScheme, theme),

              // Price range slider (expandable)
              if (_showPriceSlider) _buildInlinePriceSlider(colorScheme, theme),

              const SizedBox(height: 4),

              Expanded(
                child: FutureBuilder(
                  future: _searchWithFallback(repo),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final result = snap.data!;
                    final list = result['rentals'] as List<dynamic>;
                    final isGeneralSearch = result['isGeneral'] as bool;

                    if (list.isEmpty) {
                      return EmptyState(
                        icon: Icons.home_work_outlined,
                        title: _filterApplied
                            ? 'No rentals found'
                            : 'No rentals yet',
                        subtitle: _filterApplied
                            ? 'Try searching a different area or ward.'
                            : 'Post the first listing in your area.',
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Show notice when showing general results
                        if (isGeneralSearch && _usingDeviceLocation)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer.withOpacity(
                                0.5,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: colorScheme.onTertiaryContainer,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'No rentals in your area yet. Showing general listings.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onTertiaryContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        Expanded(
                          child: ListView.builder(
                            controller: _scrollController,
                            itemCount: list.length,
                            itemBuilder: (_, i) => _buildRentalCard(list[i]),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // WhatsApp-style floating info bubble - centered at top below search bar
        if (!_filterApplied && !_usingDeviceLocation && !_usingFypPreferences)
          Positioned(
            top: 85, // Below search bar
            left: 24,
            right: 24,
            child: Center(
              child: ScrollAwareFilterBubble(
                scrollController: _scrollController,
                onFilterTap: _openLocationFilter,
                filterApplied: _filterApplied,
                initiallyVisible: true,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRentalCard(dynamic rental) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          // Navigate to rental details
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Placeholder image
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.home,
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rental.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (rental.ward != null || rental.areaName != null)
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: colorScheme.onSurface.withOpacity(0.6),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              rental.areaName ?? rental.ward ?? '',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.6),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'KES ${rental.price?.toStringAsFixed(0) ?? 'N/A'}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
