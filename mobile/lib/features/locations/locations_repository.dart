import 'package:dio/dio.dart';

import 'active_location.dart';

class LocationsRepository {
  const LocationsRepository(this._dio);

  final Dio _dio;

  Future<List<ActiveLocation>> fetchActiveLocations() async {
    final response = await _dio.get<List<dynamic>>('/locations/active');
    final data = response.data ?? const [];

    return data
        .whereType<Map<String, dynamic>>()
        .map(ActiveLocation.fromJson)
        .toList(growable: false);
  }
}
