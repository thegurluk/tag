import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_provider.dart';
import 'active_location.dart';
import 'locations_repository.dart';

final locationsRepositoryProvider = Provider<LocationsRepository>((ref) {
  return LocationsRepository(ref.watch(dioProvider));
});

final activeLocationsProvider = FutureProvider<List<ActiveLocation>>((ref) {
  return ref.watch(locationsRepositoryProvider).fetchActiveLocations();
});
