import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geojson_vi/geojson_vi.dart';

import '../app_settings.dart';
import '../models/call_unit.dart';
import '../models/line_dto.dart';
import '../models/stops_by_line_dto.dart';
import '../services/api_repository.dart';
import '../widgets/transport_mode_selector.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<String> transportModes = ["BUS", "NOCTILIEN", "METRO", "TRAM", "TER", "TRANSILIEN", "RER"];
  String? selectedMode;
  List<LineDTO> lines = [];
  List<Polyline> polylines = [];
  List<Marker> markers = [];
  Map<String, int> transportModeCount = {};
  bool isLoadingDepartures = false;
  final MapController _mapController = MapController();
  Marker? _userMarker;
  final api = ApiRepository();

  @override
  void initState() {
    super.initState();
    fetchLines();
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
            MarkerLayer(
              markers: [
                ...markers,
                if (_userMarker != null) _userMarker!,
              ],
            ),
          ],
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _buildDraggableScrollableSheet(),
        ),
        if (isLoadingDepartures)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }

  Widget _buildDraggableScrollableSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.1,
      minChildSize: 0.1,
      maxChildSize: 0.6,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                alignment: Alignment.center,
                margin: const EdgeInsets.only(top: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: transportModes.length,
                  itemBuilder: (context, index) {
                    final mode = transportModes[index];
                    return ListTile(
                      title: Text(mode),
                      onTap: () {
                        setState(() {
                          selectedMode = mode;
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> fetchLines() async {
    final response = await api.fetchLines();

    lines = response.lines;
    transportModeCount = response.count;

    setState(() {});
  }

  Future<void> fetchStopsAndShape(String lineId, {required String lineIdBackgroundColor}) async {
    final response = await api.fetchStopsAndShape(lineId);
    final lineColor = Color(int.parse("FF${lineIdBackgroundColor.toUpperCase()}", radix: 16));

    if (response.shape.isNotEmpty) {
      _parseShapeGeoJson(response, lineColor);
    }

    if (response.stops.isNotEmpty) {
      _addStopsMarkers(response.stops, lineId, lineColor);
    }
  }

  void _addStopsMarkers(List<IDFMStopArea> stops, String lineId, Color lineColor) {
    if (stops.isEmpty) return;

    final validStops = stops.where((stop) => stop.latitude != null && stop.longitude != null).toList();
    if (validStops.isEmpty) return;

    final minLat = validStops.reduce((prev, curr) => curr.latitude! < prev.latitude! ? curr : prev).latitude!;
    final maxLat = validStops.reduce((prev, curr) => curr.latitude! > prev.latitude! ? curr : prev).latitude!;
    final minLong = validStops.reduce((prev, curr) => curr.longitude! < prev.longitude! ? curr : prev).longitude!;
    final maxLong = validStops.reduce((prev, curr) => curr.longitude! > prev.longitude! ? curr : prev).longitude!;

    setState(() {
      markers.clear();
      for (final stop in validStops) {
        markers.add(Marker(
          point: LatLng(stop.latitude!, stop.longitude!),
          width: 10.0,
          height: 10.0,
          child: GestureDetector(
            onTap: () => _onMarkerTap(stop.id!, stop.name!, lineId),
            child: Icon(
              Icons.circle,
              color: lineColor,
              size: 10.0,
            ),
          ),
        ));
      }
    });

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(minLat, minLong),
          LatLng(maxLat, maxLong),
        ),
        padding: const EdgeInsets.all(40.0)
      )
    );
  }

  void _parseShapeGeoJson(StopsByLineDTO stopsByLine, Color lineColor) {
    final geoJsonMultilineString = GeoJSONMultiLineString.fromJSON(stopsByLine.shape);

    setState(() {
      polylines.clear();
      polylines = geoJsonMultilineString.coordinates.map((subList) {
        return Polyline(
          points: subList.map((point) => LatLng(point[1], point[0])).toList(),
          color: lineColor,
          strokeWidth: 4.0,
        );
      }).toList();
    });
  }

  void _onMarkerTap(String stopId, String lineName, String lineId) async {
    setState(() {
      isLoadingDepartures = true;
    });

    try {
      final nextDepartures = await api.fetchNextDepartures(stopId, lineId);

      if (nextDepartures.nextPassages != null &&
          nextDepartures.nextPassages!.isNotEmpty) {
        final groupedDepartures = <String, List<CallUnit>>{};

        for (var passage in nextDepartures.nextPassages!) {
          final destination = passage.destinationName ?? 'Unknown Destination';
          groupedDepartures.putIfAbsent(destination, () => []).add(passage);
        }

        _showNextDeparturesDialog(lineName, groupedDepartures);
      } else {
        _showNoDeparturesDialog();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching departures: $e')),
      );
    } finally {
      setState(() {
        isLoadingDepartures = false;
      });
    }
  }

  void _showNextDeparturesDialog(String lineName, Map<String, List<CallUnit>> groupedDepartures) {
    showDialog(
      context: AppSettings.navigatorState.currentContext!,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(lineName),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: groupedDepartures.entries.map((entry) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16.0,
                      ),
                    ),
                    ...entry.value.map((callUnit) {
                      return ListTile(
                        title: Text(
                          'Departure: ${_formatTimeRelativeToNow(callUnit.expectedDepartureTime)}',
                        ),
                        subtitle: callUnit.arrivalPlatformName != null ? Text(
                          'Platform: ${callUnit.arrivalPlatformName}',
                        ) : null,
                        trailing: Text(
                          callUnit.departureStatus ?? '',
                          style: const TextStyle(color: Colors.green),
                        ),
                      );
                    }),
                  ],
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showNoDeparturesDialog() {
    showDialog(
      context: AppSettings.navigatorState.currentContext!,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Next Departures'),
          content: const Text('No departures available.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  String _formatTimeRelativeToNow(String? timestamp) {
    if (timestamp == null) return 'N/A';

    final departureTime = DateTime.tryParse(timestamp);
    if (departureTime == null) return 'N/A';

    final now = DateTime.now();
    final difference = departureTime.difference(now);

    if (difference.inMinutes < 1) {
      return 'Now';
    } else if (difference.inMinutes < 60) {
      return 'in ${difference.inMinutes} min';
    } else {
      return 'in ${difference.inHours} h ${difference.inMinutes % 60} min';
    }
  }

  void _openTransportModeSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return TransportModeSelector(
              transportModeCount: transportModeCount,
              selectedMode: selectedMode,
              lines: lines.where((line) => line.transportMode == selectedMode).toList(),
              onModeSelected: (mode) {
                setModalState(() {
                  selectedMode = mode;
                });
                setState(() {
                  selectedMode = mode;
                });
              },
              onLineSelected: (line) {
                fetchStopsAndShape(line.id!, lineIdBackgroundColor: line.lineIdBackgroundColor!);
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }
}
