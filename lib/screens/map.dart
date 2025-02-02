import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/models/navitia/embedded_type.dart';

import '../models/navitia/journey.dart';
import '../models/navitia/place.dart';
import '../services/api_repository.dart';

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
  Marker? _userMarker;

  final TextEditingController startController = TextEditingController();
  final TextEditingController destinationController = TextEditingController();
  List<String?> suggestions = [];
  Timer? debounceTimer;

  Place? selectedStartPlace;
  Place? selectedDestinationPlace;

  Future<List<Place>> fetchSuggestions(String query) async {
    if (query.isEmpty) return [];

    final response = await api.autocompletePlaces(query);

    return response.places ?? [];
  }

  Future<List<Journey>> getJourneys(String startPoint, String endPoint) async {
    if (startPoint.isEmpty || endPoint.isEmpty) return [];

    final response = await api.getJourneys(startPoint, endPoint);

    return response.journeys ?? [];
  }


  void onDebouncedTextChange(String query, ValueChanged<List<Place>> onSuggestionsReady) {
    if (debounceTimer?.isActive ?? false) debounceTimer!.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final results = await fetchSuggestions(query);
      onSuggestionsReady(results);
    });
  }

  void fetchJourneysIfBothPlacesSelected() async {
    if (selectedStartPlace != null && selectedDestinationPlace != null) {
      final startPoint = switch (selectedStartPlace?.embeddedType) {
        EmbeddedTypeEnum.address => '${selectedStartPlace?.address?.coord?.lon};${selectedStartPlace?.address?.coord?.lat}',
        EmbeddedTypeEnum.stopArea => '${selectedStartPlace?.stopArea?.id}',
        _ => ''
      };

      final endPoint = switch (selectedDestinationPlace?.embeddedType) {
        EmbeddedTypeEnum.address => '${selectedDestinationPlace?.address?.coord?.lon};${selectedDestinationPlace?.address?.coord?.lat}',
        EmbeddedTypeEnum.stopArea => '${selectedDestinationPlace?.stopArea?.id}',
        _ => ''
      };

      final journeys = await getJourneys(startPoint, endPoint);
      print("object");
    }
  }


  Widget buildAutocomplete({
    required String labelText,
    required TextEditingController controller,
    required ValueChanged<Place> onSelected,
  }) {
    return Autocomplete<Place>(
      displayStringForOption: (option) => option.name ?? '',
      optionsBuilder: (TextEditingValue textEditingValue) {
        return Future.delayed(Duration.zero, () async {
          if (textEditingValue.text == '') {
            return const Iterable<Place>.empty();
          }
          final completer = Completer<List<Place>>();
          onDebouncedTextChange(textEditingValue.text, completer.complete);
          final results = await completer.future;
          return results.whereType<Place>();
        });
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, textController, focusNode, onEditingComplete) {
        return TextField(
          controller: textController,
          focusNode: focusNode,
          onEditingComplete: onEditingComplete,
          decoration: InputDecoration(
            labelText: labelText,
            border: const OutlineInputBorder(),
          ),
        );
      },
        optionsViewBuilder: (context, onSelected, options) {
          final RenderBox renderBox = context.findRenderObject() as RenderBox;
          final double fieldWidth = renderBox.size.width;

          return Material(
            elevation: 4.0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: fieldWidth, // Match dropdown width to input field width
              ),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final place = options.elementAt(index);
                  return ListTile(
                    onTap: () => onSelected(place),
                    title: Text(place.name ?? 'Unknown Place'),
                    subtitle: place.address?.name != null ? Text(place.address?.name ?? 'No address available') : null,
                    trailing: const Icon(Icons.location_pin),
                  );
                },
              ),
            ),
          );
        }
    );
  }

  @override
  void dispose() {
    startController.dispose();
    destinationController.dispose();
    debounceTimer?.cancel();
    super.dispose();
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
        DraggableScrollableSheet(
          initialChildSize: 0.2,
          minChildSize: 0.2,
          maxChildSize: 0.5,
          builder: (context, scrollController) {
            return Container(
              color: Colors.white,
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  buildAutocomplete(
                    labelText: 'Start',
                    controller: startController,
                    onSelected: (place) {
                      setState(() {
                        selectedStartPlace = place;
                      });
                      fetchJourneysIfBothPlacesSelected();
                    },
                  ),
                  const SizedBox(height: 16),
                  buildAutocomplete(
                    labelText: 'Destination',
                    controller: destinationController,
                    onSelected: (place) {
                      setState(() {
                        selectedDestinationPlace = place;
                      });
                      fetchJourneysIfBothPlacesSelected();
                    },
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
