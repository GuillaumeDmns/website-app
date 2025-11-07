import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:website_app/models/navitia/journey.dart';
import 'package:website_app/utils/map_utils.dart';

class MainMap extends StatelessWidget {
  final MapController mapController;
  final List<Polyline> polylines;
  final Position? currentPosition;
  final LatLng? animatedLatLng;
  final double? animatedRadius;
  final Journey? activeJourney;

  const MainMap({
    super.key,
    required this.mapController,
    required this.polylines,
    this.currentPosition,
    this.animatedLatLng,
    this.animatedRadius,
    this.activeJourney,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: const MapOptions(
        initialCenter: LatLng(48.864716, 2.349014),
        initialZoom: 11,
        interactionOptions: InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.guillaumedamiens',
        ),
        PolylineLayer(
          polylines: polylines,
        ),
        if (currentPosition != null) ...[
          CircleLayer(
            circles: [
              CircleMarker(
                point: animatedLatLng ??
                    LatLng(
                        currentPosition!.latitude, currentPosition!.longitude),
                radius: animatedRadius ?? currentPosition!.accuracy,
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
                point: animatedLatLng ??
                    LatLng(
                        currentPosition!.latitude, currentPosition!.longitude),
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
        if (activeJourney != null) ...[
          MarkerLayer(
              markers: MapUtils.buildActiveJourneyMarkers(activeJourney!)),
        ]
      ],
    );
  }
}
