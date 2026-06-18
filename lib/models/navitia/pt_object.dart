import 'commercial_mode.dart';
import 'embedded_type.dart';
import 'line.dart';
import 'network.dart';
import 'poi.dart';
import 'route.dart';
import 'stop_area.dart';
import 'stop_point.dart';
import 'trip.dart';

class PtObject {
  final String? id;
  final String? name;
  final int? quality;
  final StopArea? stopArea;
  final StopPoint? stopPoint;
  final Poi? poi;
  final Line? line;
  final Network? network;
  final Route? route;
  final CommercialMode? commercialMode;
  final Trip? trip;
  final EmbeddedTypeEnum? embeddedType;

  PtObject({
    this.id,
    this.name,
    this.quality,
    this.stopArea,
    this.stopPoint,
    this.poi,
    this.line,
    this.network,
    this.route,
    this.commercialMode,
    this.trip,
    this.embeddedType,
  });

  factory PtObject.fromJson(Map<String, dynamic> json) {
    return PtObject(
      id: json['id'] as String?,
      name: json['name'] as String?,
      quality: json['quality'] as int?,
      stopArea: json['stop_area'] != null
          ? StopArea.fromJson(json['stop_area'])
          : null,
      stopPoint: json['stop_point'] != null
          ? StopPoint.fromJson(json['stop_point'])
          : null,
      poi: json['poi'] != null ? Poi.fromJson(json['poi']) : null,
      line: json['line'] != null ? Line.fromJson(json['line']) : null,
      network:
          json['network'] != null ? Network.fromJson(json['network']) : null,
      route: json['route'] != null ? Route.fromJson(json['route']) : null,
      commercialMode: json['commercial_mode'] != null
          ? CommercialMode.fromJson(json['commercial_mode'])
          : null,
      trip: json['trip'] != null ? Trip.fromJson(json['trip']) : null,
      embeddedType: json['embedded_type'] as EmbeddedTypeEnum,
    );
  }
}
