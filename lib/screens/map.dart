import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/navitia/place.dart';
import '../services/api_repository.dart';
import '../utils/debounce_utils.dart';

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
  Marker? _userMarker;

  final _startDebouncer = AsyncDebouncer(delay: const Duration(milliseconds: 300));
  final _destinationDebouncer = AsyncDebouncer(delay: const Duration(milliseconds: 300));

  Place? selectedStartPlace;
  Place? selectedDestinationPlace;

  bool _showRoutes = false;


  @override
  void dispose() {
    _startDebouncer.dispose();
    _destinationDebouncer.dispose();
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
                    color: Colors.black.withOpacity(0.2),
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
                        Autocomplete<Place>(
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text.isEmpty) {
                              return const Iterable<Place>.empty();
                            }
                            return _startDebouncer.debounce<Iterable<Place>>(() async {
                              final response = await api.autocompletePlaces(textEditingValue.text);
                              return response.places ?? [];
                            });
                          },
                          onSelected: (Place selection) {
                            setState(() {
                              selectedStartPlace = selection;
                            });
                          },
                          displayStringForOption: (Place option) => option.name ?? '',
                          fieldViewBuilder: (BuildContext context, TextEditingController fieldController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
                            return TextField(
                              controller: fieldController,
                              focusNode: fieldFocusNode,
                              decoration: const InputDecoration(
                                labelText: 'Start',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.trip_origin),
                              ),
                            );
                          },
                          optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<Place> onSelected, Iterable<Place> options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 4.0,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxHeight: 200),
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    itemBuilder: (BuildContext context, int index) {
                                      final Place option = options.elementAt(index);
                                      return ListTile(
                                        leading: const Icon(Icons.location_on_outlined),
                                        title: Text(option.name ?? ''),
                                        onTap: () {
                                          onSelected(option);
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        Autocomplete<Place>(
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text.isEmpty) {
                              return const Iterable<Place>.empty();
                            }
                            return _destinationDebouncer.debounce<Iterable<Place>>(() async {
                              final response = await api.autocompletePlaces(textEditingValue.text);
                              return response.places ?? [];
                            });
                          },
                          onSelected: (Place selection) {
                            setState(() {
                                selectedDestinationPlace = selection;
                            });
                          },
                          displayStringForOption: (Place option) => option.name ?? '',
                          fieldViewBuilder: (BuildContext context, TextEditingController fieldController, FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
                            return TextField(
                              controller: fieldController,
                              focusNode: fieldFocusNode,
                              decoration: const InputDecoration(
                                labelText: 'Destination',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.trip_origin),
                              ),
                            );
                          },
                          optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<Place> onSelected, Iterable<Place> options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 4.0,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxHeight: 200),
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    itemBuilder: (BuildContext context, int index) {
                                      final Place option = options.elementAt(index);
                                      return ListTile(
                                        leading: const Icon(Icons.location_on_outlined),
                                        title: Text(option.name ?? ''),
                                        onTap: () {
                                          onSelected(option);
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 21, thickness: 1),

                  if (_showRoutes)
                    ...List.generate(20, (index) {
                      return ListTile(
                        title: Text('Suggestion ${index + 1}'),
                        onTap: () {
                          print('Suggestion ${index + 1} cliquée !');
                        },
                      );
                    }),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
