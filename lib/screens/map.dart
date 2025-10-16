import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart' as turf;
import 'package:website_app/screens/search_places.dart';

import '../models/navitia/journey.dart';
import '../models/navitia/journeys.dart';
import '../models/navitia/place.dart';
import '../services/api_repository.dart';
import '../services/notification_service.dart';
import '../utils/style_utils.dart';
import '../widgets/journey_card.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<String> transportModes = ["BUS", "NOCTILIEN", "METRO", "TRAM", "TER", "TRANSILIEN", "RER"];
  String? selectedMode;

  List<Polyline> polylines = [];
  List<Marker> markers = [];
  final api = ApiRepository();

  final MapController _mapController = MapController();
  final DraggableScrollableController _scrollableController = DraggableScrollableController();

  Place? selectedStartPlace;
  Place? selectedDestinationPlace;

  Journeys? _journeys;

  bool _isLoadingJourneys = false;
  bool _showRoutes = false;

  Timer? _journeySimulator;

  StreamSubscription<Position>? _positionStreamSubscription;
  Position? _currentPosition;
  Journey? _activeJourney;
  int _currentSectionIndex = -1;

  double _totalJourneyDistanceInMeters = 0.0;

  final List<LatLng> _fullJourneyPolyline = [];
  final List<double> _cumulativeDistances = [];

  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _notificationService.init();
  }

  @override
  void dispose() {
    _journeySimulator?.cancel();
    _positionStreamSubscription?.cancel();
    _startController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _navigateToSearchScreen({required bool isStart}) async {
    final Place? result = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (context) => SearchPlaceScreen(
          hintText: isStart ? 'Enter a starting point' : 'Enter a destination',
        ),
      ),
    );

    if (result != null) {
      setState(() {
        if (isStart) {
          selectedStartPlace = result;
          _startController.text = result.name ?? '';
        } else {
          selectedDestinationPlace = result;
          _destinationController.text = result.name ?? '';
        }
      });
      _fetchJourneys();
    }
  }

  Future<void> _fetchJourneys() async {
    if (selectedStartPlace != null && selectedDestinationPlace != null) {
      setState(() {
        _isLoadingJourneys = true;
        _showRoutes = true;
        _journeys = null;
        polylines.clear();
      });

      try {
        final journeysResult = await api.getJourneys(selectedStartPlace?.id ?? '', selectedDestinationPlace?.id ?? '');
        setState(() {
          _journeys = journeysResult;
          _isLoadingJourneys = false;
        });
      } catch (e) {
        print('Erreur lors de la récupération des itinéraires: $e');
        setState(() {
          _isLoadingJourneys = false;
        });
      }
    }
  }

  void _displayJourneyOnMap(Journey journey) {
    _stopGpsTracking();

    final List<Polyline> newJourneyPolylines = [];
    final List<LatLng> allJourneyPoints = [];

    setState(() {
      _activeJourney = journey;
      _currentSectionIndex = -1;
      _totalJourneyDistanceInMeters = 0.0;
      _cumulativeDistances.clear();
    });

    _fullJourneyPolyline.clear();
    double totalDistance = 0;

    for (var section in journey.sections!) {
      if (section.geojson != null && section.geojson!.coordinates != null && section.geojson!.coordinates!.isNotEmpty) {
        final List<LatLng> sectionPoints = [];
        for (var coord in section.geojson!.coordinates!) {
          if (coord.length >= 2) {
            final point = LatLng(coord[1], coord[0]);
            sectionPoints.add(point);
            allJourneyPoints.add(point);
            _fullJourneyPolyline.add(point);
          }
        }
        if (sectionPoints.isNotEmpty) {
          final color = hexToColor(section.displayInformations?.color);
          newJourneyPolylines.add(
            Polyline(
              points: sectionPoints,
              strokeWidth: 5.0,
              color: color,
            ),
          );
        }
      }
      totalDistance += section.geojson?.properties?[0].length ?? 0;
      _cumulativeDistances.add(totalDistance);
    }

    _totalJourneyDistanceInMeters = totalDistance;
    _startGpsTracking();

    setState(() {
      polylines.clear();
      polylines.addAll(newJourneyPolylines);
      _scrollableController.animateTo(
        0.25,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });

    if (allJourneyPoints.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(allJourneyPoints);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(50.0),
        ),
      );
    }
  }

  Future<void> _startGpsTracking() async {
    if (!mounted) return;

    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Location Services Disabled'),
          content: const Text('Please enable location services to use live tracking.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Open Settings'),
              onPressed: () {
                Geolocator.openLocationSettings();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      );
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required to track your journey.')),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      await showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Location Permission Denied'),
          content: const Text('Location permission has been permanently denied. Please enable it from the app settings to use this feature.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Open Settings'),
              onPressed: () {
                Geolocator.openAppSettings();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      );
      return;
    }

    if (_activeJourney != null) {
      _notificationService.showJourneyProgressNotification(_activeJourney!);
    }

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
    );
    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(_onLocationUpdate);
  }

  void _onLocationUpdate(Position position) {
    if (_fullJourneyPolyline.isEmpty || _activeJourney == null || _activeJourney!.sections == null) return;

    final userPosition = turf.Position(position.longitude, position.latitude);

    int newSectionIndex = -1;
    double minDistanceToSection = double.infinity;

    for (int i = 0; i < _activeJourney!.sections!.length; i++) {
      final section = _activeJourney!.sections![i];
      if (section.geojson?.coordinates == null || section.geojson!.coordinates!.isEmpty) continue;

      final sectionPoints = section.geojson!.coordinates!
          .where((c) => c.length >= 2)
          .map((c) => turf.Position(c[0], c[1]))
          .toList();

      if (sectionPoints.isEmpty) continue;

      final sectionLine = turf.LineString(coordinates: sectionPoints);
      final pointOnThisSection = turf.nearestPointOnLine(sectionLine, turf.Point(coordinates: userPosition), turf.Unit.meters);
      final distance = pointOnThisSection.properties!['dist'] as num;

      if (distance < minDistanceToSection) {
        minDistanceToSection = distance.toDouble();
        newSectionIndex = i;
      }
    }

    if (newSectionIndex == -1) {
      newSectionIndex = _activeJourney!.sections!.length - 1;
    }

    final newPolylines = <Polyline>[];
    for (int i = 0; i < _activeJourney!.sections!.length; i++) {
      final section = _activeJourney!.sections![i];
      if (section.geojson?.coordinates == null || section.geojson!.coordinates!.isEmpty) continue;

      final sectionPoints = section.geojson!.coordinates!
          .where((c) => c.length >= 2)
          .map((c) => LatLng(c[1], c[0]))
          .toList();

      if (sectionPoints.isEmpty) continue;

      final originalColor = hexToColor(section.displayInformations?.color);
      final traveledColor = originalColor.withValues(alpha: 0.2);

      if (i < newSectionIndex) {
        newPolylines.add(Polyline(points: sectionPoints, strokeWidth: 5.0, color: traveledColor));
      } else if (i > newSectionIndex) {
        newPolylines.add(Polyline(points: sectionPoints, strokeWidth: 5.0, color: originalColor));
      } else {
        final sectionLine = turf.LineString(coordinates: sectionPoints.map((p) => turf.Position(p.longitude, p.latitude)).toList());
        final snappedOnSection = turf.nearestPointOnLine(sectionLine, turf.Point(coordinates: userPosition), turf.Unit.meters);
        final snappedLatLngOnSection = LatLng(snappedOnSection.geometry!.coordinates.lat.toDouble(), snappedOnSection.geometry!.coordinates.lng.toDouble());
        final splitIndex = snappedOnSection.properties!['index'] as int;

        if (splitIndex >= 0 && sectionPoints.length > 1) {
          final traveledPart = sectionPoints.sublist(0, splitIndex + 1)..add(snappedLatLngOnSection);
          newPolylines.add(Polyline(points: traveledPart, strokeWidth: 5.0, color: traveledColor));
        }

        if (splitIndex < sectionPoints.length - 1) {
          final remainingPart = [snappedLatLngOnSection, ...sectionPoints.sublist(splitIndex + 1)];
          newPolylines.add(Polyline(points: remainingPart, strokeWidth: 5.0, color: originalColor));
        } else if (newPolylines.where((p) => p.color == originalColor).isEmpty && sectionPoints.length <= 1) {
          newPolylines.add(Polyline(points: [snappedLatLngOnSection, sectionPoints.last], strokeWidth: 5.0, color: originalColor));
        }
      }
    }

    double traveledDistance = 0;

    if (newSectionIndex > 0) {
      traveledDistance += _cumulativeDistances[newSectionIndex - 1];
    }

    final currentSectionPoints = _activeJourney!.sections![newSectionIndex].geojson!.coordinates!
        .where((c) => c.length >= 2)
        .map((c) => LatLng(c[1], c[0]))
        .toList();

    final snappedOnSection = turf.nearestPointOnLine(
        turf.LineString(coordinates: currentSectionPoints.map((p) => turf.Position(p.longitude, p.latitude)).toList()),
        turf.Point(coordinates: turf.Position(position.longitude, position.latitude)),
        turf.Unit.meters
    );
    final splitIndex = snappedOnSection.properties!['index'] as int;
    final snappedLatLngOnSection = LatLng(snappedOnSection.geometry!.coordinates.lat.toDouble(), snappedOnSection.geometry!.coordinates.lng.toDouble());

    double distanceInCurrentSection = 0.0;
    for (int i = 0; i < splitIndex; i++) {
      distanceInCurrentSection += Geolocator.distanceBetween(
        currentSectionPoints[i].latitude, currentSectionPoints[i].longitude,
        currentSectionPoints[i + 1].latitude, currentSectionPoints[i + 1].longitude,
      );
    }

    if (splitIndex < currentSectionPoints.length) {
      distanceInCurrentSection += Geolocator.distanceBetween(
        currentSectionPoints[splitIndex].latitude, currentSectionPoints[splitIndex].longitude,
        snappedLatLngOnSection.latitude, snappedLatLngOnSection.longitude,
      );
    }

    traveledDistance += distanceInCurrentSection;

    setState(() {
      _currentPosition = position;
      polylines = newPolylines;
    });

    _notificationService.updateJourneyProgressNotification(
        _activeJourney!,
        newSectionIndex,
        traveledDistance,
        _totalJourneyDistanceInMeters
    );

    if (newSectionIndex != _currentSectionIndex) {
      setState(() {
        _currentSectionIndex = newSectionIndex;
      });
    }

    final endPoint = _fullJourneyPolyline.last;
    final distanceToEnd = Geolocator.distanceBetween(position.latitude, position.longitude, endPoint.latitude, endPoint.longitude);
    if (distanceToEnd < 50) {
      _stopGpsTracking();
    }
  }

  void _stopGpsTracking() {
    _positionStreamSubscription?.cancel();
    if (_activeJourney != null) {
      _notificationService.cancelJourneyNotification(_activeJourney!);
    }
    setState(() {
      _currentPosition = null;
      _activeJourney = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: LatLng(48.864716, 2.349014),
            initialZoom: 11,
            interactionOptions: InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.guillaumedamiens',
            ),
            PolylineLayer(
              polylines: polylines,
            ),
            if (_currentPosition != null) ...[
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                    radius: _currentPosition!.accuracy,
                    useRadiusInMeter: true,
                    color: Colors.blue.withValues(alpha: 0.2),
                    borderColor: Colors.blue.withValues(alpha: 0.4),
                    borderStrokeWidth: 1.5,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                    width: 80,
                    height: 80,
                    child: Center(
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.0),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            MarkerLayer(
              markers: markers,
            ),
          ],
        ),
        DraggableScrollableSheet(
          controller: _scrollableController,
          initialChildSize: 0.25,
          minChildSize: 0.25,
          maxChildSize: 0.80,
          builder: (BuildContext context, ScrollController scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _startController,
                          readOnly: true,
                          onTap: () => _navigateToSearchScreen(isStart: true),
                          decoration: const InputDecoration(
                            labelText: 'Start',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.trip_origin),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _destinationController,
                          readOnly: true,
                          onTap: () => _navigateToSearchScreen(isStart: false),
                          decoration: const InputDecoration(
                            labelText: 'Destination',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.fmd_good_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 21, thickness: 1),
                  if (_showRoutes)
                    if (_isLoadingJourneys)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_journeys != null && _journeys!.journeys != null && _journeys!.journeys!.isNotEmpty)
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _journeys!.journeys!.length,
                        itemBuilder: (context, index) {
                          final journey = _journeys!.journeys![index];
                          return JourneyCard(
                            journey: journey,
                            onJourneySelected: _displayJourneyOnMap,
                          );
                        },
                      )
                    else
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text("Aucun itinéraire trouvé."),
                        ),
                      ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}