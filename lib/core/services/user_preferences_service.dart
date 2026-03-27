import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

/// Service to track user interactions and generate personalized recommendations
class UserPreferencesService {
  static const String _viewHistoryKey = 'rental_view_history';
  static const String _searchHistoryKey = 'search_history';
  static const String _preferredAreasKey = 'preferred_areas';
  static const String _priceRangeKey = 'price_range_preference';
  static const String _bedroomPreferenceKey = 'bedroom_preference';
  static const String _fypWardsKey = 'fyp_wards';        // User's manually set wards
  static const String _fypNicknamesKey = 'fyp_nicknames'; // User's manually set nicknames
  
  static UserPreferencesService? _instance;
  late SharedPreferences _prefs;
  
  // User behavior tracking
  List<RentalInteraction> _viewHistory = [];
  List<String> _searchHistory = [];
  Map<String, int> _areaClickCounts = {};
  Map<int, int> _bedroomClickCounts = {};
  List<double> _priceClicks = [];
  
  UserPreferencesService._();
  
  static Future<UserPreferencesService> getInstance() async {
    if (_instance == null) {
      _instance = UserPreferencesService._();
      await _instance!._init();
    }
    return _instance!;
  }
  
  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadData();
  }
  
  void _loadData() {
    // Load view history
    final viewHistoryJson = _prefs.getStringList(_viewHistoryKey) ?? [];
    _viewHistory = viewHistoryJson
        .map((json) => RentalInteraction.fromJson(jsonDecode(json)))
        .toList();
    
    // Load search history
    _searchHistory = _prefs.getStringList(_searchHistoryKey) ?? [];
    
    // Load area preferences
    final areaJson = _prefs.getString(_preferredAreasKey);
    if (areaJson != null) {
      _areaClickCounts = Map<String, int>.from(jsonDecode(areaJson));
    }
    
    // Load bedroom preferences
    final bedroomJson = _prefs.getString(_bedroomPreferenceKey);
    if (bedroomJson != null) {
      final decoded = jsonDecode(bedroomJson) as Map<String, dynamic>;
      _bedroomClickCounts = decoded.map((k, v) => MapEntry(int.parse(k), v as int));
    }
    
    // Load price clicks
    final priceJson = _prefs.getString(_priceRangeKey);
    if (priceJson != null) {
      _priceClicks = List<double>.from(jsonDecode(priceJson));
    }
  }
  
  Future<void> _saveData() async {
    // Save view history (keep last 100)
    final recentHistory = _viewHistory.take(100).toList();
    await _prefs.setStringList(
      _viewHistoryKey,
      recentHistory.map((i) => jsonEncode(i.toJson())).toList(),
    );
    
    // Save search history (keep last 20)
    await _prefs.setStringList(_searchHistoryKey, _searchHistory.take(20).toList());
    
    // Save area preferences
    await _prefs.setString(_preferredAreasKey, jsonEncode(_areaClickCounts));
    
    // Save bedroom preferences
    final bedroomMap = _bedroomClickCounts.map((k, v) => MapEntry(k.toString(), v));
    await _prefs.setString(_bedroomPreferenceKey, jsonEncode(bedroomMap));
    
    // Save price clicks (keep last 50)
    await _prefs.setString(_priceRangeKey, jsonEncode(_priceClicks.take(50).toList()));
  }
  
  /// Record when user views a rental
  Future<void> recordRentalView({
    required int rentalId,
    required String city,
    required String state,
    required int bedrooms,
    required double price,
  }) async {
    final interaction = RentalInteraction(
      rentalId: rentalId,
      city: city,
      state: state,
      bedrooms: bedrooms,
      price: price,
      timestamp: DateTime.now(),
    );
    
    _viewHistory.insert(0, interaction);
    
    // Track area preference
    final areaKey = '$city, $state'.toLowerCase();
    _areaClickCounts[areaKey] = (_areaClickCounts[areaKey] ?? 0) + 1;
    
    // Track bedroom preference
    _bedroomClickCounts[bedrooms] = (_bedroomClickCounts[bedrooms] ?? 0) + 1;
    
    // Track price preference
    _priceClicks.insert(0, price);
    
    await _saveData();
  }
  
  /// Record search query
  Future<void> recordSearch(String query) async {
    if (query.isNotEmpty && !_searchHistory.contains(query.toLowerCase())) {
      _searchHistory.insert(0, query.toLowerCase());
      await _saveData();
    }
  }
  
  /// Get recommended price range based on user clicks
  PriceRange? getPreferredPriceRange() {
    if (_priceClicks.length < 3) return null;
    
    final sortedPrices = List<double>.from(_priceClicks)..sort();
    final minPrice = sortedPrices.first * 0.8; // 20% below min clicked
    final maxPrice = sortedPrices.last * 1.3; // 30% above max clicked
    
    return PriceRange(min: minPrice, max: maxPrice);
  }
  
  /// Get expanded bedroom preference (e.g., if user likes 1BR, also suggest 2BR)
  List<int> getExpandedBedroomPreferences() {
    if (_bedroomClickCounts.isEmpty) return [];
    
    // Sort by click count
    final sorted = _bedroomClickCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    final preferredBedrooms = <int>{};
    for (var entry in sorted.take(2)) {
      preferredBedrooms.add(entry.key);
      // Add adjacent bedroom counts for FYP
      if (entry.key > 0) preferredBedrooms.add(entry.key - 1);
      if (entry.key < 10) preferredBedrooms.add(entry.key + 1);
    }
    
    return preferredBedrooms.toList()..sort();
  }
  
  /// Get preferred areas sorted by frequency
  List<String> getPreferredAreas() {
    if (_areaClickCounts.isEmpty) return [];
    
    final sorted = _areaClickCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sorted.take(5).map((e) => e.key).toList();
  }
  
  /// Get FYP (For You Page) wards from user profile
  /// Returns user's manually set preferred wards (up to 5)
  List<String> getFypWards() {
    final user = AuthService.currentUser;
    if (user == null) return [];
    return user.fypWards;
  }
  
  /// Get FYP nicknames from user profile  
  /// Returns user's manually set area nicknames (unlimited)
  List<String> getFypNicknames() {
    final user = AuthService.currentUser;
    if (user == null) return [];
    return user.fypNicknames;
  }
  
  /// Check if user has FYP preferences set
  bool get hasFypPreferences {
    final user = AuthService.currentUser;
    if (user == null) return false;
    return user.fypWards.isNotEmpty || user.fypNicknames.isNotEmpty;
  }
  
  /// Get all FYP search terms (wards + nicknames combined)
  List<String> getAllFypSearchTerms() {
    final user = AuthService.currentUser;
    if (user == null) return [];
    
    final terms = <String>{};
    terms.addAll(user.fypWards);
    terms.addAll(user.fypNicknames);
    
    // Also include user's location if set
    if (user.locationWard != null) terms.add(user.locationWard!);
    if (user.locationAreaName != null) terms.add(user.locationAreaName!);
    
    return terms.toList();
  }
  
  /// Get user's location ward for filtering
  String? getUserLocationWard() {
    return AuthService.currentUser?.locationWard;
  }
  
  /// Get user's location constituency for filtering
  String? getUserLocationConstituency() {
    return AuthService.currentUser?.locationConstituency;
  }
  
  /// Get user's location county for filtering  
  String? getUserLocationCounty() {
    return AuthService.currentUser?.locationCounty;
  }
  
  /// Check if user has location set
  bool get hasUserLocation {
    return AuthService.currentUser?.hasLocation ?? false;
  }
  
  /// Get search history
  List<String> getSearchHistory() => List.from(_searchHistory);
  
  /// Clear all preferences
  Future<void> clearPreferences() async {
    _viewHistory.clear();
    _searchHistory.clear();
    _areaClickCounts.clear();
    _bedroomClickCounts.clear();
    _priceClicks.clear();
    await _prefs.clear();
  }
}

class RentalInteraction {
  final int rentalId;
  final String city;
  final String state;
  final int bedrooms;
  final double price;
  final DateTime timestamp;
  
  RentalInteraction({
    required this.rentalId,
    required this.city,
    required this.state,
    required this.bedrooms,
    required this.price,
    required this.timestamp,
  });
  
  factory RentalInteraction.fromJson(Map<String, dynamic> json) {
    return RentalInteraction(
      rentalId: json['rentalId'],
      city: json['city'],
      state: json['state'],
      bedrooms: json['bedrooms'],
      price: (json['price'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'rentalId': rentalId,
    'city': city,
    'state': state,
    'bedrooms': bedrooms,
    'price': price,
    'timestamp': timestamp.toIso8601String(),
  };
}

class PriceRange {
  final double min;
  final double max;
  
  PriceRange({required this.min, required this.max});
}
