import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geojson_vi/geojson_vi.dart';

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

  final api = ApiRepository();

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
      _addStopsMarkers(response.stops, lineColor);
    }
  }

  void _addStopsMarkers(List<IDFMStopArea> stops, Color lineColor) {
    setState(() {
      markers.clear();
      for (final stop in stops) {
        if (stop.latitude != null && stop.longitude != null) {
          markers.add(Marker(
            point: LatLng(stop.latitude!, stop.longitude!),
            alignment: const Alignment(0, -0.5),
            child: Icon(
              Icons.location_on,
              color: lineColor,
              size: 20.0,
            ),
          ));
        }
      }
    });
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

  @override
  void initState() {
    super.initState();
    fetchLines();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          FlutterMap(
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
                markers: markers
              ),
            ],
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              onPressed: () => _openTransportModeSelector(context),
              child: const Icon(Icons.directions_transit),
            ),
          ),
        ],
      ),
    );
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
