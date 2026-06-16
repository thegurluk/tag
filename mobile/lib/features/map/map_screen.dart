import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../locations/active_location.dart';
import '../locations/locations_providers.dart';
import '../routes/route_result.dart';
import '../routes/routes_providers.dart';
import 'location_permission_controller.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  static const _istanbul = LatLng(41.015137, 28.979530);

  GoogleMapController? _mapController;
  ActiveLocation? _selectedLocation;
  RouteMode _routeMode = RouteMode.motorcycle;
  AsyncValue<RouteResult?> _routeState = const AsyncData(null);

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locations = ref.watch(activeLocationsProvider);
    final position = ref.watch(currentPositionProvider);
    final currentPosition = position.whenOrNull(data: (value) => value);
    final activeLocations = locations.whenOrNull(data: (value) => value);
    final route = _routeState.whenOrNull(data: (value) => value);

    return Scaffold(
      body: Stack(
        children: [
          locations.when(
            data: (items) => _AlertMap(
              locations: items,
              position: currentPosition,
              selectedLocation: _selectedLocation,
              route: route,
              onMapCreated: (controller) {
                _mapController = controller;
                if (currentPosition != null) {
                  unawaited(_moveToUser(currentPosition));
                }
              },
              onMarkerTap: _openDetails,
            ),
            error: (error, _) => _MapMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Konumlar alinamadi',
              message: error.toString(),
              onRetry: _refresh,
            ),
            loading: () => const _MapMessage(
              icon: Icons.map_outlined,
              title: 'Harita hazirlaniyor',
              message: 'Aktif yol bildirimleri yukleniyor.',
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TopBar(
                    count: activeLocations?.length,
                    isLoading: locations.isLoading,
                    onRefresh: _refresh,
                    onLocate: () {
                      if (currentPosition != null) {
                        unawaited(_moveToUser(currentPosition));
                      } else {
                        ref.invalidate(currentPositionProvider);
                      }
                    },
                  ),
                  const Spacer(),
                  if (_selectedLocation != null)
                    _LocationSheet(
                      location: _selectedLocation!,
                      userPosition: currentPosition,
                      routeMode: _routeMode,
                      routeState: _routeState,
                      onRouteModeChanged: (mode) {
                        setState(() {
                          _routeMode = mode;
                          _routeState = const AsyncData(null);
                        });
                      },
                      onRoutePressed: () => _calculateRoute(currentPosition),
                      onClose: () {
                        setState(() {
                          _selectedLocation = null;
                          _routeState = const AsyncData(null);
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _refresh() {
    ref.invalidate(activeLocationsProvider);
  }

  void _openDetails(ActiveLocation location) {
    setState(() {
      _selectedLocation = location;
      _routeState = const AsyncData(null);
    });
    unawaited(
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(location.latitude, location.longitude)),
      ),
    );
  }

  Future<void> _moveToUser(Position position) async {
    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(position.latitude, position.longitude),
          zoom: 14,
        ),
      ),
    );
  }

  Future<void> _calculateRoute(Position? position) async {
    final selected = _selectedLocation;
    if (selected == null) return;

    if (position == null) {
      ref.invalidate(currentPositionProvider);
      setState(() {
        _routeState = AsyncError('Konum izni gerekiyor', StackTrace.current);
      });
      return;
    }

    setState(() => _routeState = const AsyncLoading());

    try {
      final route = await ref
          .read(routesRepositoryProvider)
          .calculateRoute(
            origin: LatLng(position.latitude, position.longitude),
            destination: LatLng(selected.latitude, selected.longitude),
            mode: _routeMode,
          );

      setState(() => _routeState = AsyncData(route));
      unawaited(_fitRoute(route.points));
    } catch (error, stackTrace) {
      setState(() => _routeState = AsyncError(error, stackTrace));
    }
  }

  Future<void> _fitRoute(List<LatLng> points) async {
    if (points.isEmpty) return;

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points.skip(1)) {
      minLat = point.latitude < minLat ? point.latitude : minLat;
      maxLat = point.latitude > maxLat ? point.latitude : maxLat;
      minLng = point.longitude < minLng ? point.longitude : minLng;
      maxLng = point.longitude > maxLng ? point.longitude : maxLng;
    }

    await _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        72,
      ),
    );
  }
}

class _AlertMap extends StatelessWidget {
  const _AlertMap({
    required this.locations,
    required this.position,
    required this.selectedLocation,
    required this.route,
    required this.onMapCreated,
    required this.onMarkerTap,
  });

  final List<ActiveLocation> locations;
  final Position? position;
  final ActiveLocation? selectedLocation;
  final RouteResult? route;
  final ValueChanged<GoogleMapController> onMapCreated;
  final ValueChanged<ActiveLocation> onMarkerTap;

  @override
  Widget build(BuildContext context) {
    final initialTarget = position == null
        ? _MapScreenState._istanbul
        : LatLng(position!.latitude, position!.longitude);

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: initialTarget, zoom: 11.5),
      onMapCreated: onMapCreated,
      myLocationButtonEnabled: false,
      myLocationEnabled: position != null,
      zoomControlsEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      polylines: {
        if (route != null && route!.points.isNotEmpty)
          Polyline(
            polylineId: const PolylineId('active-route'),
            points: route!.points,
            color: const Color(0xFF1F7A5A),
            width: 6,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
          ),
      },
      markers: {
        for (final location in locations)
          Marker(
            markerId: MarkerId(location.id),
            position: LatLng(location.latitude, location.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              _markerHue(location.color),
            ),
            infoWindow: InfoWindow.noText,
            zIndexInt: selectedLocation?.id == location.id ? 2 : 1,
            onTap: () => onMarkerTap(location),
          ),
      },
    );
  }

  static double _markerHue(AlertColor color) {
    return switch (color) {
      AlertColor.red => BitmapDescriptor.hueRed,
      AlertColor.yellow => BitmapDescriptor.hueYellow,
      AlertColor.blue => BitmapDescriptor.hueAzure,
      AlertColor.expired => BitmapDescriptor.hueViolet,
    };
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.count,
    required this.isLoading,
    required this.onRefresh,
    required this.onLocate,
  });

  final int? count;
  final bool isLoading;
  final VoidCallback onRefresh;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F111111),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.route_outlined, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      count == null
                          ? 'Yol Bilgi'
                          : '$count aktif yol bildirimi',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _MapButton(
          icon: isLoading ? Icons.sync : Icons.refresh,
          tooltip: 'Yenile',
          onPressed: onRefresh,
        ),
        const SizedBox(width: 8),
        _MapButton(
          icon: Icons.my_location,
          tooltip: 'Konumum',
          onPressed: onLocate,
        ),
      ],
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 3,
      shadowColor: const Color(0x33111111),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}

class _LocationSheet extends StatelessWidget {
  const _LocationSheet({
    required this.location,
    required this.userPosition,
    required this.routeMode,
    required this.routeState,
    required this.onRouteModeChanged,
    required this.onRoutePressed,
    required this.onClose,
  });

  final ActiveLocation location;
  final Position? userPosition;
  final RouteMode routeMode;
  final AsyncValue<RouteResult?> routeState;
  final ValueChanged<RouteMode> onRouteModeChanged;
  final VoidCallback onRoutePressed;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final distance = userPosition == null
        ? null
        : Geolocator.distanceBetween(
            userPosition!.latitude,
            userPosition!.longitude,
            location.latitude,
            location.longitude,
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2B111111),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 12,
                  height: 44,
                  decoration: BoxDecoration(
                    color: location.accentColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        location.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        location.formattedAddress.isEmpty
                            ? 'Adres bilgisi yok'
                            : location.formattedAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF59636E),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Kapat',
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.schedule,
                  label: _ageLabel(location.ageMinutes),
                ),
                _InfoChip(
                  icon: Icons.flag_outlined,
                  label: location.statusLabel,
                ),
                if (distance != null)
                  _InfoChip(
                    icon: Icons.near_me_outlined,
                    label: _distanceLabel(distance),
                  ),
                _InfoChip(
                  icon: Icons.timer_outlined,
                  label: 'Biter ${DateFormat.Hm().format(location.expiresAt)}',
                ),
              ],
            ),
            const SizedBox(height: 14),
            SegmentedButton<RouteMode>(
              segments: [
                for (final mode in RouteMode.values)
                  ButtonSegment<RouteMode>(
                    value: mode,
                    icon: Icon(
                      mode == RouteMode.motorcycle
                          ? Icons.two_wheeler
                          : Icons.directions_car_outlined,
                    ),
                    label: Text(mode.label),
                  ),
              ],
              selected: {routeMode},
              onSelectionChanged: (selected) {
                onRouteModeChanged(selected.first);
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: routeState.isLoading ? null : onRoutePressed,
                icon: routeState.isLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.navigation_outlined),
                label: Text(
                  routeState.isLoading ? 'Rota hesaplaniyor' : 'Rota ciz',
                ),
              ),
            ),
            if (routeState.hasError) ...[
              const SizedBox(height: 8),
              Text(
                _routeErrorMessage(routeState.error),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_routeResult != null) ...[
              const SizedBox(height: 10),
              _RouteSummary(route: _routeResult!),
            ],
          ],
        ),
      ),
    );
  }

  static String _ageLabel(int minutes) {
    if (minutes < 60) {
      return '$minutes dk once';
    }

    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    if (remaining == 0) {
      return '$hours sa once';
    }
    return '$hours sa $remaining dk once';
  }

  static String _distanceLabel(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static String _routeErrorMessage(Object? error) {
    final text = error?.toString() ?? 'Rota hesaplanamadi';
    if (text.contains('Konum izni gerekiyor')) {
      return 'Rota icin konum izni gerekiyor.';
    }
    return 'Rota hesaplanamadi. Birazdan tekrar dene.';
  }

  RouteResult? get _routeResult {
    return routeState.whenOrNull(data: (value) => value);
  }
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({required this.route});

  final RouteResult route;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4EF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            const Icon(Icons.alt_route, size: 18, color: Color(0xFF1F7A5A)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_distance(route.distanceMeters)} · ${_duration(route.durationSeconds)}',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              route.travelModeUsed == 'TWO_WHEELER' ? 'Motor' : 'Standart',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }

  static String _distance(int meters) {
    if (meters < 1000) return '$meters m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static String _duration(int seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes dk';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return remaining == 0 ? '$hours sa' : '$hours sa $remaining dk';
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3EF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF4F5C63)),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}

class _MapMessage extends StatelessWidget {
  const _MapMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: const Color(0xFF536068)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar dene'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
