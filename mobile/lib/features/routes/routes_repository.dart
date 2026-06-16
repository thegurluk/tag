import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'route_result.dart';

class RoutesRepository {
  const RoutesRepository(this._dio);

  final Dio _dio;

  Future<RouteResult> calculateRoute({
    required LatLng origin,
    required LatLng destination,
    required RouteMode mode,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/routes/calculate',
      data: {
        'origin': {'latitude': origin.latitude, 'longitude': origin.longitude},
        'destination': {
          'latitude': destination.latitude,
          'longitude': destination.longitude,
        },
        'mode': mode.name,
      },
    );

    final data = response.data;
    if (data == null) {
      throw StateError('Route response is empty');
    }

    return RouteResult.fromJson(data);
  }

  Future<List<RouteSearchResult>> searchDestinations(String query) async {
    final response = await _dio.get<List<dynamic>>(
      '/routes/search',
      queryParameters: {'q': query},
    );
    final data = response.data ?? const [];

    return data
        .whereType<Map<String, dynamic>>()
        .map(RouteSearchResult.fromJson)
        .toList(growable: false);
  }
}
