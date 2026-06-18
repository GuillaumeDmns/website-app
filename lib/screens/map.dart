import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:website_app/screens/search_places.dart';

import '../models/navitia/journey.dart';
import '../models/navitia/journeys.dart';
import '../models/navitia/place.dart';
import '../models/navitia/section.dart';
import '../models/navitia/vehicle_journey.dart';
import '../services/api_repository.dart';
import '../services/notification_service.dart';
import '../services/permission_manager.dart';
import '../utils/constants.dart' as constants;
import '../utils/journey_utils.dart';
import '../utils/location_utils.dart';
import '../utils/time_utils.dart';
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
  final List<Polyline> _originalPolylines = [];
  final api = ApiRepository();

  late final AnimatedMapController _mapController;
  final PanelController _panelController = PanelController();

  Place? selectedStartPlace;
  Place? selectedDestinationPlace;

  JourneysResponse? _journeysResponse;
  Journey? _activeJourney;

  bool _isLoadingJourneys = false;
  bool _showRoutes = false;

  StreamSubscription<Position>? _positionStreamSubscription;
  Position? _currentPosition;
  int _currentSectionIndex = -1;
  int _focusedSectionIndex = -1;
  double _totalJourneyDistanceInMeters = 0.0;
  final List<LatLng> _fullJourneyPolyline = [];
  final List<double> _cumulativeDistances = [];
  final ValueNotifier<double> _panelPositionNotifier = ValueNotifier<double>(0.0);

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
    _mapController = AnimatedMapController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
      curve: Curves.easeInOut,
    );
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
    _mapController.dispose();
    _panelPositionNotifier.dispose();
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
        _journeysResponse = null;
        polylines.clear();
      });

      _panelController.animatePanelToPosition(
        1.0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );

      try {
        final journeysResult = await api.getJourneys(
            selectedStartPlace?.id ?? '', selectedDestinationPlace?.id ?? '');
        setState(() {
          _journeysResponse = journeysResult;
          _isLoadingJourneys = false;
        });
      } catch (e) {
        debugPrint('Erreur lors de la récupération des itinéraires: $e');
        setState(() {
          _isLoadingJourneys = false;
        });
      }
    }
  }

  EdgeInsets _getMapPadding() {
    final screenHeight = MediaQuery.of(context).size.height;

    final panelHeight = (screenHeight - constants.navigationBarHeight) * 0.5;

    const safePadding = 50.0;

    return EdgeInsets.only(
      left: safePadding,
      right: safePadding,
      top: safePadding,
      bottom: panelHeight + 200,
    );
  }

  void _displayJourneyOnMap(Journey journey) {
    _stopGpsTracking();

    final processedData = JourneyUtils.processJourneyForMap(journey);

    setState(() {
      _activeJourney = journey;
      _currentSectionIndex = -1;
      _focusedSectionIndex = -1;
      _totalJourneyDistanceInMeters =
          processedData.totalJourneyDistanceInMeters;

      _cumulativeDistances.clear();
      _cumulativeDistances.addAll(processedData.cumulativeDistances);

      _fullJourneyPolyline.clear();
      _fullJourneyPolyline.addAll(processedData.fullJourneyPolyline);

      _originalPolylines.clear();
      _originalPolylines.addAll(processedData.polylines);

      polylines.clear();
      polylines.addAll(processedData.polylines);
    });

    _startGpsTracking();
    _panelController.open();

    if (processedData.allJourneyPoints.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(processedData.allJourneyPoints);
      _mapController.animatedFitCamera(
        cameraFit: CameraFit.bounds(bounds: bounds, padding: _getMapPadding()),
      );
    }
  }

  void _fitMapToSection(int sectionIndex) {
    if (_activeJourney?.sections == null || _activeJourney!.sections!.isEmpty) {
      return;
    }

    final Section focusedSection = _activeJourney!.sections![sectionIndex];

    if (focusedSection.geojson == null) {
      return;
    }

    int polylineIndex = 0;
    for (int i = 0; i < sectionIndex; i++) {
      if (_activeJourney!.sections![i].geojson != null) {
        polylineIndex++;
      }
    }

    if (polylineIndex == _focusedSectionIndex || _originalPolylines.isEmpty) {
      return;
    }

    if (polylineIndex >= 0 && polylineIndex < _originalPolylines.length) {
      final Polyline sectionPolyline = _originalPolylines[polylineIndex];

      if (sectionPolyline.points.isNotEmpty) {
        setState(() {
          _focusedSectionIndex = polylineIndex;
        });

        final bounds = LatLngBounds.fromPoints(sectionPolyline.points);

        _mapController.animatedFitCamera(
          cameraFit:
              CameraFit.bounds(bounds: bounds, padding: _getMapPadding()),
        );
      }
    }
  }

  Future<void> _startGpsTracking() async {
    if (!mounted) return;

    bool hasPermission =
        await LocationUtils.checkAndRequestLocationPermissions(context);
    if (!hasPermission) return;

    if (mounted) {
      await PermissionManager().requestNotificationPermission(context);
    }

    final locationSettings = LocationUtils.getPlatformLocationSettings();

    if (_activeJourney != null) {
      await _notificationService.requestWebNotificationPermission();
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
      _originalPolylines.clear();
      _currentSectionIndex = -1;
      _focusedSectionIndex = -1;
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

  // ... inside _MapScreenState

  /// 1. Updates the specific section with new details from the selected VehicleJourney
  /// 2. Calculates the time difference
  /// 3. Shifts all subsequent sections by that difference
  void _onSectionChanged(int sectionIndex, VehicleJourney newVehicleJourney, Section originalSection) {
    if (_activeJourney == null || _activeJourney!.sections == null) return;

    // 1. Find new times from the selected vehicle journey
    String? newDepartureTime;
    String? newArrivalTime;

    // Simple lookup: Find stop time matching the 'from' ID
    var startStop = newVehicleJourney.stopTimes?.firstWhere(
          (st) => st.stopPoint?.id == originalSection.from?.stopPoint?.id,
      orElse: () => newVehicleJourney.stopTimes!.first,
    );

    // Simple lookup: Find stop time matching the 'to' ID
    var endStop = newVehicleJourney.stopTimes?.firstWhere(
          (st) => st.stopPoint?.id == originalSection.to?.stopPoint?.id,
      orElse: () => newVehicleJourney.stopTimes!.last,
    );

    newDepartureTime = startStop?.departureTime;
    newArrivalTime = endStop?.arrivalTime;

    if (newDepartureTime == null || newArrivalTime == null) return;

    DateTime getTrueTime(String timeStr, DateTime ref) {
      if (timeStr.length == 15) {
        try {
          return DateTime.parse(
              "${timeStr.substring(0, 4)}-${timeStr.substring(4, 6)}-${timeStr.substring(6, 8)} ${timeStr.substring(9, 11)}:${timeStr.substring(11, 13)}:${timeStr.substring(13, 15)}");
        } catch (_) {
          return ref;
        }
      } else if (timeStr.length >= 6) {
        try {
          int h = int.parse(timeStr.substring(0, 2));
          int m = int.parse(timeStr.substring(2, 4));
          int s = int.parse(timeStr.substring(4, 6));

          int extraDays = h ~/ 24;
          h = h % 24;

          DateTime constructed = DateTime(ref.year, ref.month, ref.day, h, m, s).add(Duration(days: extraDays));
          
          if (extraDays == 0) {
            if (constructed.difference(ref).inHours > 12) {
              constructed = constructed.subtract(const Duration(days: 1));
            } else if (constructed.difference(ref).inHours < -12) {
              constructed = constructed.add(const Duration(days: 1));
            }
          }
          return constructed;
        } catch (_) {
          return ref;
        }
      }
      return ref;
    }

    setState(() {
      // 2. Calculate the time shift (Delta)
      DateTime oldDeparture = TimeUtils.parseNavitiaTime(originalSection.departureDateTime!);
      DateTime newDepartureParsed = getTrueTime(newDepartureTime!, oldDeparture);
      Duration shift = newDepartureParsed.difference(oldDeparture);

      // 3. Create a NEW list from the existing sections (mutable copy)
      List<Section> updatedSections = List.from(_activeJourney!.sections!);

      // 4. Update the target section and all subsequent sections
      for (int i = sectionIndex; i < updatedSections.length; i++) {
        Section sec = updatedSections[i];

        String? shiftedDeparture;
        String? shiftedArrival;

        if (sec.departureDateTime != null) {
          DateTime sDep = TimeUtils.parseNavitiaTime(sec.departureDateTime!);
          shiftedDeparture = TimeUtils.formatNavitiaTime(sDep.add(shift));
        }

        if (sec.arrivalDateTime != null) {
          DateTime sArr = TimeUtils.parseNavitiaTime(sec.arrivalDateTime!);
          shiftedArrival = TimeUtils.formatNavitiaTime(sArr.add(shift));
        }

        var shiftedStops = sec.stopDateTimes?.map((stop) {
          String? newStopArr;
          String? newStopDep;
          if (stop.arrivalDateTime != null) {
            DateTime arr = TimeUtils.parseNavitiaTime(stop.arrivalDateTime!);
            newStopArr = TimeUtils.formatNavitiaTime(arr.add(shift));
          }
          if (stop.departureDateTime != null) {
            DateTime dep = TimeUtils.parseNavitiaTime(stop.departureDateTime!);
            newStopDep = TimeUtils.formatNavitiaTime(dep.add(shift));
          }
          return stop.copyWith(
            arrivalDateTime: newStopArr,
            departureDateTime: newStopDep,
          );
        }).toList();

        updatedSections[i] = sec.copyWith(
          departureDateTime: shiftedDeparture,
          arrivalDateTime: shiftedArrival,
          stopDateTimes: shiftedStops,
        );
      }

      String? journeyArrival = _activeJourney!.arrivalDateTime;
      String? journeyDeparture = _activeJourney!.departureDateTime;
      int? journeyDuration = _activeJourney!.duration;

      if (journeyArrival != null) {
        DateTime jArr = TimeUtils.parseNavitiaTime(journeyArrival);
        journeyArrival = TimeUtils.formatNavitiaTime(jArr.add(shift));
      }
      
      if (sectionIndex == 0 && journeyDeparture != null) {
         DateTime jDep = TimeUtils.parseNavitiaTime(journeyDeparture);
         journeyDeparture = TimeUtils.formatNavitiaTime(jDep.add(shift));
      }

      if (sectionIndex > 0 && journeyDeparture != null && journeyArrival != null) {
        DateTime jArr = TimeUtils.parseNavitiaTime(journeyArrival);
        DateTime jDep = TimeUtils.parseNavitiaTime(journeyDeparture);
        journeyDuration = jArr.difference(jDep).inSeconds;
      }

      _activeJourney = _activeJourney!.copyWith(
        sections: updatedSections,
        arrivalDateTime: journeyArrival,
        departureDateTime: journeyDeparture,
        duration: journeyDuration,
      );
    });
  }

  Future<void> _centerOnCurrentLocation() async {
    if (_currentPosition != null) {
      _mapController.animateTo(
        dest: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        zoom: 15,
      );
    } else {
      bool hasPermission = await LocationUtils.checkAndRequestLocationPermissions(
        context,
        title: 'Ma position',
        description: 'Autorisez l\'accès à votre position pour vous situer sur la carte.',
      );
      if (!hasPermission || !mounted) return;
      try {
        final position = await Geolocator.getCurrentPosition();
        setState(() {
          _currentPosition = position;
        });
        _mapController.animateTo(
          dest: LatLng(position.latitude, position.longitude),
          zoom: 15,
        );
      } catch (e) {
        debugPrint('GPS error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    BorderRadiusGeometry radius = const BorderRadius.only(
      topLeft: Radius.circular(24.0),
      topRight: Radius.circular(24.0),
    );

    final screenHeight = MediaQuery.of(context).size.height;
    final bool isDetailsActive = _activeJourney != null;
    final double panelMinHeight = isDetailsActive ? screenHeight * 0.5 : 150;
    final double panelMaxHeight = isDetailsActive ? screenHeight * 0.5 : 500;
    final bool isDraggable = !isDetailsActive;
    final bool parallaxEnabled = !isDetailsActive;
    final double parallaxOffset = !isDetailsActive ? 0.5 : 0.0;

    return Scaffold(
      body: Stack(
        children: [
          SlidingUpPanel(
            color: Theme.of(context).colorScheme.surface,
            parallaxEnabled: parallaxEnabled,
            parallaxOffset: parallaxOffset,
            minHeight: panelMinHeight,
            maxHeight: panelMaxHeight,
            isDraggable: isDraggable,
            controller: _panelController,
            borderRadius: radius,
            onPanelSlide: (position) => _panelPositionNotifier.value = position,
            panelBuilder: (sc) {
              if (_activeJourney != null) {
                return JourneyDetailsPanel(
                  sc: sc,
                  journey: _activeJourney!,
                  onReturn: _returnToSearch,
                  onSectionFocused: _fitMapToSection,
                  terminusList: _journeysResponse?.terminus ?? [],
                  onSectionUpdate: (index, vj, section) =>
                      _onSectionChanged(index, vj, section),
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
                  journeysList: _journeysResponse,
                  onJourneySelected: _displayJourneyOnMap,
                );
              }
            },
            body: MainMap(
              mapController: _mapController.mapController,
              polylines: polylines,
              currentPosition: _currentPosition,
              animatedLatLng: _animatedLatLng,
              animatedRadius: _animatedRadius,
              activeJourney: _activeJourney,
            ),
          ),
          if (!isDetailsActive)
            ValueListenableBuilder<double>(
              valueListenable: _panelPositionNotifier,
              builder: (context, position, child) {
                final double currentPanelHeight =
                    panelMinHeight + (panelMaxHeight - panelMinHeight) * position;
                return Positioned(
                  right: 16.0,
                  bottom: currentPanelHeight + 16.0,
                  child: child!,
                );
              },
              child: FloatingActionButton.small(
                onPressed: _centerOnCurrentLocation,
                backgroundColor: Theme.of(context).colorScheme.surface,
                foregroundColor: Theme.of(context).colorScheme.primary,
                elevation: 2,
                tooltip: 'Ma position',
                child: const Icon(Icons.my_location_rounded),
              ),
            ),
        ],
      ),
    );
  }
}
