import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:website_app/screens/search_places.dart';

import '../models/navitia/journey.dart';
import '../models/navitia/journeys.dart';
import '../models/navitia/place.dart';
import '../services/api_repository.dart';
import '../services/notification_service.dart';
import '../utils/journey_utils.dart';
import '../utils/location_utils.dart';
import '../widgets/main_map.dart';
import '../widgets/panels/journey_details_panel.dart';
import '../widgets/panels/search_panel.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  List<Polyline> polylines = [];
  final api = ApiRepository();

  final MapController _mapController = MapController();
  final PanelController _panelController = PanelController();

  Place? selectedStartPlace;
  Place? selectedDestinationPlace;

  Journeys? _journeys;
  Journey? _activeJourney;

  bool _isLoadingJourneys = false;
  bool _showRoutes = false;

  StreamSubscription<Position>? _positionStreamSubscription;
  Position? _currentPosition;
  int _currentSectionIndex = -1;
  double _totalJourneyDistanceInMeters = 0.0;
  final List<LatLng> _fullJourneyPolyline = [];
  final List<double> _cumulativeDistances = [];

  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  final NotificationService _notificationService = NotificationService();
  late final AnimationController _animationController;
  Animation<LatLng>? _positionAnimation;
  Animation<double>? _radiusAnimation;
  LatLng? _animatedLatLng;
  double? _animatedRadius;

  @override
  void initState() {
    super.initState();
    _notificationService.init();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..addListener(() {
        setState(() {
          if (_positionAnimation != null) {
            _animatedLatLng = _positionAnimation!.value;
          }
          if (_radiusAnimation != null) {
            _animatedRadius = _radiusAnimation!.value;
          }
        });
      });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _startController.dispose();
    _destinationController.dispose();
    _animationController.dispose();
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
        final journeysResult = await api.getJourneys(
            selectedStartPlace?.id ?? '', selectedDestinationPlace?.id ?? '');
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

    final processedData = JourneyUtils.processJourneyForMap(journey);

    setState(() {
      _activeJourney = journey;
      _currentSectionIndex = -1;
      _totalJourneyDistanceInMeters =
          processedData.totalJourneyDistanceInMeters;

      _cumulativeDistances.clear();
      _cumulativeDistances.addAll(processedData.cumulativeDistances);

      _fullJourneyPolyline.clear();
      _fullJourneyPolyline.addAll(processedData.fullJourneyPolyline);

      polylines.clear();
      polylines.addAll(processedData.polylines);
    });

    _startGpsTracking();
    _panelController.open();

    if (processedData.allJourneyPoints.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(processedData.allJourneyPoints);
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

    bool hasPermission =
        await LocationUtils.checkAndRequestLocationPermissions(context);
    if (!hasPermission) return;

    final locationSettings = LocationUtils.getPlatformLocationSettings();

    if (_activeJourney != null) {
      await _notificationService
          .showJourneyProgressNotification(_activeJourney!);
    }

    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen(_onLocationUpdate);

    final Position position2 = await Geolocator.getCurrentPosition();
    _onLocationUpdate(position2);
  }

  void _onLocationUpdate(Position position) {
    if (_fullJourneyPolyline.isEmpty || _activeJourney == null) return;

    final updateData = JourneyUtils.updateJourneyProgress(
      position: position,
      activeJourney: _activeJourney!,
      fullJourneyPolyline: _fullJourneyPolyline,
      cumulativeDistances: _cumulativeDistances,
    );

    final LatLng beginLatLng =
        _animatedLatLng ?? LatLng(position.latitude, position.longitude);
    final double beginRadius = _animatedRadius ?? position.accuracy;
    final LatLng endLatLng = LatLng(position.latitude, position.longitude);
    final double endRadius = position.accuracy;

    _positionAnimation =
        LatLngTween(begin: beginLatLng, end: endLatLng).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.linear),
    );
    _radiusAnimation =
        Tween<double>(begin: beginRadius, end: endRadius).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward(from: 0.0);

    setState(() {
      _currentPosition = position;
      polylines = updateData.newPolylines;
    });

    _notificationService.updateJourneyProgressNotification(
        _activeJourney!,
        updateData.newSectionIndex,
        updateData.traveledDistance,
        _totalJourneyDistanceInMeters);

    if (updateData.newSectionIndex != _currentSectionIndex) {
      setState(() {
        _currentSectionIndex = updateData.newSectionIndex;
      });
    }

    if (updateData.isJourneyFinished) {
      _stopGpsTracking();
    }
  }

  void _stopGpsTracking() {
    _positionStreamSubscription?.cancel();
    if (_activeJourney != null) {
      _notificationService.cancelJourneyNotification();
    }
    setState(() {
      _currentPosition = null;
      _activeJourney = null;
    });
  }

  void _returnToSearch() {
    _stopGpsTracking();
    setState(() {
      polylines.clear();
      _currentSectionIndex = -1;
      _fullJourneyPolyline.clear();
      _cumulativeDistances.clear();
      _currentPosition = null;
      _animatedLatLng = null;
    });
    _panelController.animatePanelToPosition(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    BorderRadiusGeometry radius = BorderRadius.only(
      topLeft: Radius.circular(24.0),
      topRight: Radius.circular(24.0),
    );

    return SlidingUpPanel(
      parallaxEnabled: true,
      parallaxOffset: 0.5,
      minHeight: 150,
      controller: _panelController,
      borderRadius: radius,
      panelBuilder: (sc) {
        if (_activeJourney != null) {
          return JourneyDetailsPanel(
            sc: sc,
            journey: _activeJourney!,
            onReturn: _returnToSearch,
          );
        } else {
          return SearchPanel(
            sc: sc,
            startController: _startController,
            destinationController: _destinationController,
            onStartTap: () => _navigateToSearchScreen(isStart: true),
            onDestinationTap: () => _navigateToSearchScreen(isStart: false),
            isLoading: _isLoadingJourneys,
            showRoutes: _showRoutes,
            journeys: _journeys,
            onJourneySelected: _displayJourneyOnMap,
          );
        }
      },
      body: MainMap(
        mapController: _mapController,
        polylines: polylines,
        currentPosition: _currentPosition,
        animatedLatLng: _animatedLatLng,
        animatedRadius: _animatedRadius,
        activeJourney: _activeJourney,
      ),
    );
  }
}
