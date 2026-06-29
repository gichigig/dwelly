import 'dart:io';

void main() {
  var file = File('lib/core/services/rental_service.dart');
  var content = file.readAsStringSync();
  
  if (!content.contains('getMapRadarListings')) {
    var newMethod = '''
  static Future<List<Rental>> getMapRadarListings(double latitude, double longitude, {double radiusMeters = 1500}) async {
    try {
      final response = await ApiService.timedGet(
        Uri.parse('\${ApiService.baseUrl}/rentals/search/map-radar?latitude=\$latitude&longitude=\$longitude&radiusMeters=\$radiusMeters'),
        headers: _jsonHeadersWithAuth(),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Rental.fromJson(json)).toList();
      } else {
        return [];
      }
    } catch (e) {
      _logDebug('Error fetching map radar listings', e);
      return [];
    }
  }
''';
    
    // Find the end of smartLocationSearch
    var index = content.indexOf('static Future<SmartLocationSearchResult> smartLocationSearch');
    content = content.substring(0, index) + newMethod + '\n' + content.substring(index);
    file.writeAsStringSync(content);
    print('Added getMapRadarListings');
  }
}
