import 'dart:io';

void main() {
  var file = File('lib/features/listings/presentation/map_explore_page.dart');
  var content = file.readAsStringSync();
  
  var circleLayerStr = '''              CircleLayer(
                circles: _deviceLocation != null && _isRadarActive ? [
                  CircleMarker(
                    point: LatLng(_deviceLocation!.latitude, _deviceLocation!.longitude),
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderStrokeWidth: 2,
                    borderColor: Theme.of(context).colorScheme.primary,
                    useRadiusInMeter: true,
                    radius: radarDistanceMeters,
                  )
                ] : [],
              ),
              MarkerClusterLayerWidget''';

  content = content.replaceAll('MarkerClusterLayerWidget', circleLayerStr);
  file.writeAsStringSync(content);
  print('Added CircleLayer');
}
