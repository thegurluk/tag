import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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
  _RouteTarget? _customDestination;
  RouteMode _routeMode = RouteMode.motorcycle;
  AsyncValue<RouteResult?> _routeState = const AsyncData(null);
  final Set<String> _deletedLocationIds = {};

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
    final visibleLocations = activeLocations
        ?.where((location) => !_deletedLocationIds.contains(location.id))
        .toList(growable: false);
    final route = _routeState.whenOrNull(data: (value) => value);

    return Scaffold(
      body: Stack(
        children: [
          locations.when(
            data: (items) => _AlertMap(
              locations: items
                  .where(
                    (location) => !_deletedLocationIds.contains(location.id),
                  )
                  .toList(growable: false),
              position: currentPosition,
              selectedLocation: _selectedLocation,
              customDestination: _customDestination,
              route: route,
              onMapCreated: (controller) {
                _mapController = controller;
                if (currentPosition != null) {
                  unawaited(_moveToUser(currentPosition));
                }
              },
              onMarkerTap: _openDetails,
              onLongPress: _setCustomDestination,
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
                    count: visibleLocations?.length,
                    isLoading: locations.isLoading,
                    onOpenList: () =>
                        _openMarkerList(visibleLocations ?? const []),
                    onRefresh: _refresh,
                    onSearch: _openSearch,
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
                      onRoutePressed: _calculateRoute,
                      onStartNavigation: () => _startNavigation(
                        _RouteTarget(
                          id: _selectedLocation!.id,
                          title: _selectedLocation!.title,
                          subtitle: _selectedLocation!.formattedAddress,
                          position: LatLng(
                            _selectedLocation!.latitude,
                            _selectedLocation!.longitude,
                          ),
                        ),
                      ),
                      onClose: () {
                        setState(() {
                          _selectedLocation = null;
                          _routeState = const AsyncData(null);
                        });
                      },
                    ),
                  if (_customDestination != null)
                    _DestinationSheet(
                      destination: _customDestination!,
                      userPosition: currentPosition,
                      routeMode: _routeMode,
                      routeState: _routeState,
                      onRouteModeChanged: (mode) {
                        setState(() {
                          _routeMode = mode;
                          _routeState = const AsyncData(null);
                        });
                      },
                      onRoutePressed: () =>
                          _calculateRouteToTarget(_customDestination!),
                      onStartNavigation: () =>
                          _startNavigation(_customDestination!),
                      onClose: () {
                        setState(() {
                          _customDestination = null;
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

  Future<void> _openMarkerList(List<ActiveLocation> locations) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _MarkerListSheet(
        locations: locations,
        onOpenLocation: (location) {
          Navigator.of(context).pop();
          _openDetails(location);
        },
        onDeleteLocation: _deleteLocation,
      ),
    );
  }

  Future<void> _deleteLocation(ActiveLocation location) async {
    try {
      await ref
          .read(locationsRepositoryProvider)
          .deleteActiveLocation(location.id);
      if (!mounted) return;
      setState(() {
        _deletedLocationIds.add(location.id);
        if (_selectedLocation?.id == location.id) {
          _selectedLocation = null;
          _routeState = const AsyncData(null);
        }
      });
      ref.invalidate(activeLocationsProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Marker silinemedi: $error')));
    }
  }

  void _openDetails(ActiveLocation location) {
    setState(() {
      _selectedLocation = location;
      _customDestination = null;
      _routeState = const AsyncData(null);
    });
    unawaited(
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(location.latitude, location.longitude)),
      ),
    );
  }

  void _setCustomDestination(LatLng position) {
    final target = _RouteTarget(
      id: 'custom-${position.latitude}-${position.longitude}',
      title: 'Secilen hedef',
      subtitle:
          '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
      position: position,
    );

    setState(() {
      _selectedLocation = null;
      _customDestination = target;
      _routeState = const AsyncData(null);
    });
  }

  Future<void> _openSearch() async {
    final result = await showModalBottomSheet<_RouteTarget>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _RouteSearchSheet(),
    );

    if (result == null) return;

    setState(() {
      _selectedLocation = null;
      _customDestination = result;
      _routeState = const AsyncData(null);
    });

    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: result.position, zoom: 15),
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

  Future<void> _calculateRoute() async {
    final selected = _selectedLocation;
    if (selected == null) return;

    await _calculateRouteToTarget(
      _RouteTarget(
        id: selected.id,
        title: selected.title,
        subtitle: selected.formattedAddress,
        position: LatLng(selected.latitude, selected.longitude),
      ),
    );
  }

  Future<void> _calculateRouteToTarget(_RouteTarget target) async {
    setState(() => _routeState = const AsyncLoading());

    final position = await _resolveCurrentPosition();

    if (position == null) {
      setState(() {
        _routeState = AsyncError('Konum izni gerekiyor', StackTrace.current);
      });
      return;
    }

    try {
      final route = await ref
          .read(routesRepositoryProvider)
          .calculateRoute(
            origin: LatLng(position.latitude, position.longitude),
            destination: target.position,
            mode: _routeMode,
          );

      setState(() => _routeState = AsyncData(route));
      unawaited(_fitRoute(route.points));
    } catch (error, stackTrace) {
      setState(() => _routeState = AsyncError(error, stackTrace));
    }
  }

  Future<void> _startNavigation(_RouteTarget target) async {
    final lat = target.position.latitude;
    final lng = target.position.longitude;
    final nativeUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final webUri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '$lat,$lng',
      'travelmode': 'driving',
    });

    if (await canLaunchUrl(nativeUri)) {
      await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
      return;
    }

    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }

  Future<Position?> _resolveCurrentPosition() async {
    final cached = ref
        .read(currentPositionProvider)
        .whenOrNull(data: (value) => value);
    if (cached != null) return cached;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      ref.invalidate(currentPositionProvider);
      return position;
    } on TimeoutException {
      return Geolocator.getLastKnownPosition();
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
    required this.customDestination,
    required this.route,
    required this.onMapCreated,
    required this.onMarkerTap,
    required this.onLongPress,
  });

  final List<ActiveLocation> locations;
  final Position? position;
  final ActiveLocation? selectedLocation;
  final _RouteTarget? customDestination;
  final RouteResult? route;
  final ValueChanged<GoogleMapController> onMapCreated;
  final ValueChanged<ActiveLocation> onMarkerTap;
  final ValueChanged<LatLng> onLongPress;

  @override
  Widget build(BuildContext context) {
    final initialTarget = position == null
        ? _MapScreenState._istanbul
        : LatLng(position!.latitude, position!.longitude);

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: initialTarget, zoom: 11.5),
      onMapCreated: onMapCreated,
      onLongPress: onLongPress,
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
        if (customDestination != null)
          Marker(
            markerId: MarkerId(customDestination!.id),
            position: customDestination!.position,
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            infoWindow: InfoWindow(
              title: customDestination!.title,
              snippet: customDestination!.subtitle,
            ),
            zIndexInt: 3,
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
    required this.onOpenList,
    required this.onRefresh,
    required this.onSearch,
    required this.onLocate,
  });

  final int? count;
  final bool isLoading;
  final VoidCallback onOpenList;
  final VoidCallback onRefresh;
  final VoidCallback onSearch;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MapButton(
          icon: Icons.menu,
          tooltip: 'Marker listesi',
          onPressed: onOpenList,
        ),
        const SizedBox(width: 8),
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
          icon: Icons.search,
          tooltip: 'Hedef ara',
          onPressed: onSearch,
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

class _MarkerListSheet extends StatefulWidget {
  const _MarkerListSheet({
    required this.locations,
    required this.onOpenLocation,
    required this.onDeleteLocation,
  });

  final List<ActiveLocation> locations;
  final ValueChanged<ActiveLocation> onOpenLocation;
  final ValueChanged<ActiveLocation> onDeleteLocation;

  @override
  State<_MarkerListSheet> createState() => _MarkerListSheetState();
}

class _MarkerListSheetState extends State<_MarkerListSheet> {
  late List<ActiveLocation> _locations;

  @override
  void initState() {
    super.initState();
    _locations = List.of(widget.locations);
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.82;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Aktif markerlar',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${_locations.length}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF59636E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  tooltip: 'Kapat',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _locations.isEmpty
                ? const _MarkerListEmpty()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                    itemCount: _locations.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final location = _locations[index];
                      return _MarkerListItem(
                        index: index + 1,
                        location: location,
                        onOpen: () => widget.onOpenLocation(location),
                        onShowMessage: () =>
                            _showMarkerMessage(context, location),
                        onDelete: () {
                          setState(() {
                            _locations.removeWhere(
                              (item) => item.id == location.id,
                            );
                          });
                          widget.onDeleteLocation(location);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static Future<void> _showMarkerMessage(
    BuildContext context,
    ActiveLocation location,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mesaj detayi'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailLine(label: 'Baslik', value: location.title),
              _DetailLine(
                label: 'Ham mesaj',
                value: location.rawMessage.isEmpty
                    ? 'Ham mesaj yok'
                    : location.rawMessage,
              ),
              _DetailLine(
                label: 'Temizlenen metin',
                value: location.cleanedLocationText.isEmpty
                    ? location.title
                    : location.cleanedLocationText,
              ),
              _DetailLine(
                label: 'Adres',
                value: location.formattedAddress.isEmpty
                    ? 'Adres bilgisi yok'
                    : location.formattedAddress,
              ),
              _DetailLine(
                label: 'Koordinat',
                value:
                    '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
              ),
              _DetailLine(
                label: 'Confidence',
                value: location.confidenceScore.toStringAsFixed(2),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
}

class _MarkerListItem extends StatelessWidget {
  const _MarkerListItem({
    required this.index,
    required this.location,
    required this.onOpen,
    required this.onShowMessage,
    required this.onDelete,
  });

  final int index;
  final ActiveLocation location;
  final VoidCallback onOpen;
  final VoidCallback onShowMessage;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E5E8)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: location.accentColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        location.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        location.formattedAddress.isEmpty
                            ? 'Adres bilgisi yok'
                            : location.formattedAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF59636E),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Sil',
                  icon: const Icon(Icons.delete_outline),
                  color: const Color(0xFFB3261E),
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.schedule,
                  label: _LocationSheet._ageLabel(location.ageMinutes),
                ),
                _InfoChip(
                  icon: Icons.flag_outlined,
                  label: location.statusLabel,
                ),
                _InfoChip(
                  icon: Icons.percent,
                  label: location.confidenceScore.toStringAsFixed(2),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onShowMessage,
                    icon: const Icon(Icons.article_outlined),
                    label: const Text('Mesaj'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.place_outlined),
                    label: const Text('Haritada ac'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkerListEmpty extends StatelessWidget {
  const _MarkerListEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Aktif marker yok.'),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF59636E),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
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
    required this.onStartNavigation,
    required this.onClose,
  });

  final ActiveLocation location;
  final Position? userPosition;
  final RouteMode routeMode;
  final AsyncValue<RouteResult?> routeState;
  final ValueChanged<RouteMode> onRouteModeChanged;
  final VoidCallback onRoutePressed;
  final VoidCallback onStartNavigation;
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
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: onStartNavigation,
                  icon: const Icon(Icons.assistant_direction_outlined),
                  label: const Text('Suruse basla'),
                ),
              ),
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
    return 'Rota hesaplanamadi. Emulator konumu Istanbul disindaysa konumu Istanbul yapip tekrar dene.';
  }

  RouteResult? get _routeResult {
    return routeState.whenOrNull(data: (value) => value);
  }
}

class _DestinationSheet extends StatelessWidget {
  const _DestinationSheet({
    required this.destination,
    required this.userPosition,
    required this.routeMode,
    required this.routeState,
    required this.onRouteModeChanged,
    required this.onRoutePressed,
    required this.onStartNavigation,
    required this.onClose,
  });

  final _RouteTarget destination;
  final Position? userPosition;
  final RouteMode routeMode;
  final AsyncValue<RouteResult?> routeState;
  final ValueChanged<RouteMode> onRouteModeChanged;
  final VoidCallback onRoutePressed;
  final VoidCallback onStartNavigation;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final distance = userPosition == null
        ? null
        : Geolocator.distanceBetween(
            userPosition!.latitude,
            userPosition!.longitude,
            destination.position.latitude,
            destination.position.longitude,
          );
    final routeResult = routeState.whenOrNull(data: (value) => value);

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
                    color: const Color(0xFF1F7A5A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        destination.subtitle,
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
            if (distance != null)
              _InfoChip(
                icon: Icons.near_me_outlined,
                label: _LocationSheet._distanceLabel(distance),
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
                  routeState.isLoading ? 'Rota hesaplaniyor' : 'Rota olustur',
                ),
              ),
            ),
            if (routeState.hasError) ...[
              const SizedBox(height: 8),
              Text(
                _LocationSheet._routeErrorMessage(routeState.error),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (routeResult != null) ...[
              const SizedBox(height: 10),
              _RouteSummary(route: routeResult),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: onStartNavigation,
                  icon: const Icon(Icons.assistant_direction_outlined),
                  label: const Text('Suruse basla'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RouteSearchSheet extends ConsumerStatefulWidget {
  const _RouteSearchSheet();

  @override
  ConsumerState<_RouteSearchSheet> createState() => _RouteSearchSheetState();
}

class _RouteSearchSheetState extends ConsumerState<_RouteSearchSheet> {
  final _controller = TextEditingController();
  AsyncValue<List<RouteSearchResult>> _results = const AsyncData([]);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Hedef ara',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Kapat',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Orn. Taksim, Kadikoy, Perpa',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Ara',
                icon: const Icon(Icons.arrow_forward),
                onPressed: _search,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: _results.when(
              data: (items) {
                if (items.isEmpty) {
                  return const _SearchEmptyState();
                }

                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(item.title),
                      subtitle: Text(
                        item.formattedAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.of(context).pop(
                          _RouteTarget(
                            id: item.id,
                            title: item.title,
                            subtitle: item.formattedAddress,
                            position: item.position,
                          ),
                        );
                      },
                    );
                  },
                );
              },
              error: (_, _) => const _SearchErrorState(),
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.length < 2) return;

    setState(() => _results = const AsyncLoading());

    try {
      final results = await ref
          .read(routesRepositoryProvider)
          .searchDestinations(query);
      setState(() => _results = AsyncData(results));
    } catch (error, stackTrace) {
      setState(() => _results = AsyncError(error, stackTrace));
    }
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Hedef arayabilir veya haritada uzun basarak hedef secebilirsin.',
      ),
    );
  }
}

class _SearchErrorState extends StatelessWidget {
  const _SearchErrorState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Arama yapilamadi. Backend search endpoint deploy veya Google Geocoding ayarini kontrol et.',
      ),
    );
  }
}

class _RouteTarget {
  const _RouteTarget({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.position,
  });

  final String id;
  final String title;
  final String subtitle;
  final LatLng position;
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
