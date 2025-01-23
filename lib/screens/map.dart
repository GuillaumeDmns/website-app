import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/models/navitia/place.dart';

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

  Future<List<Place>> fetchSuggestions(String query) async {
    if (query.isEmpty) return [];

    final response = await api.autocompletePlaces(query);

    return response.places ?? [];
  }

  void onDebouncedTextChange(String query, ValueChanged<List<Place>> onSuggestionsReady) {
    if (debounceTimer?.isActive ?? false) debounceTimer!.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final results = await fetchSuggestions(query);
      onSuggestionsReady(results);
    });
  }

  Widget buildAutocomplete({
    required String labelText,
    required TextEditingController controller,
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
                  ),
                  const SizedBox(height: 16),
                  buildAutocomplete(
                    labelText: 'Destination',
                    controller: destinationController,
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
