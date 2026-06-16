import 'package:google_maps_flutter/google_maps_flutter.dart';

enum RouteMode {
  standard,
  motorcycle;

  String get label {
    return switch (this) {
      RouteMode.standard => 'Standart',
      RouteMode.motorcycle => 'Motor',
    };
  }
}

class RouteResult {
  const RouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.encodedPolyline,
    required this.travelModeUsed,
    required this.points,
  });

  final int distanceMeters;
  final int durationSeconds;
  final String encodedPolyline;
  final String travelModeUsed;
  final List<LatLng> points;

  factory RouteResult.fromJson(Map<String, dynamic> json) {
    final encoded = json['polyline'] as String? ?? '';
    return RouteResult(
      distanceMeters: (json['distance_meters'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
      encodedPolyline: encoded,
      travelModeUsed: json['travel_mode_used'] as String? ?? 'DRIVE',
      points: decodePolyline(encoded),
    );
  }
}

class RouteSearchResult {
  const RouteSearchResult({
    required this.id,
    required this.title,
    required this.formattedAddress,
    required this.position,
  });

  final String id;
  final String title;
  final String formattedAddress;
  final LatLng position;

  factory RouteSearchResult.fromJson(Map<String, dynamic> json) {
    return RouteSearchResult(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Konum',
      formattedAddress: json['formatted_address'] as String? ?? '',
      position: LatLng(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
    );
  }
}

List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0;
  var latitude = 0;
  var longitude = 0;

  while (index < encoded.length) {
    final latResult = _decodeValue(encoded, index);
    index = latResult.nextIndex;
    latitude += latResult.value;

    final lngResult = _decodeValue(encoded, index);
    index = lngResult.nextIndex;
    longitude += lngResult.value;

    points.add(LatLng(latitude / 1E5, longitude / 1E5));
  }

  return points;
}

_DecodedValue _decodeValue(String encoded, int startIndex) {
  var index = startIndex;
  var shift = 0;
  var result = 0;
  int byte;

  do {
    byte = encoded.codeUnitAt(index++) - 63;
    result |= (byte & 0x1F) << shift;
    shift += 5;
  } while (byte >= 0x20 && index < encoded.length);

  final value = (result & 1) == 1 ? ~(result >> 1) : result >> 1;
  return _DecodedValue(value: value, nextIndex: index);
}

class _DecodedValue {
  const _DecodedValue({required this.value, required this.nextIndex});

  final int value;
  final int nextIndex;
}
