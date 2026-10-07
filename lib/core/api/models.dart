import 'package:freezed_annotation/freezed_annotation.dart';

import '../../l10n/l10n.dart';

part 'models.freezed.dart';
part 'models.g.dart';

/// Models of the backend mobility API (`/api/v2`) and auth endpoints.

enum TransportMode {
  @JsonValue('METRO')
  metro,
  @JsonValue('RER')
  rer,
  @JsonValue('TRANSILIEN')
  transilien,
  @JsonValue('TER')
  ter,
  @JsonValue('TRAM')
  tram,
  @JsonValue('BUS')
  bus,
  @JsonValue('NOCTILIEN')
  noctilien;

  /// Value used by the API (`METRO`…)
  String get apiName => name.toUpperCase();

  String get label => switch (this) {
        metro => currentL10n.modeMetro,
        rer => 'RER',
        transilien => 'Transilien',
        ter => 'TER',
        tram => 'Tram',
        bus => 'Bus',
        noctilien => 'Noctilien',
      };
}

@freezed
abstract class AuthTokens with _$AuthTokens {
  const factory AuthTokens({
    required String jwt,
    String? refreshToken,

    /// Access token lifetime in seconds
    int? expiresIn,
  }) = _AuthTokens;

  factory AuthTokens.fromJson(Map<String, dynamic> json) => _$AuthTokensFromJson(json);
}

@freezed
abstract class LineSummary with _$LineSummary {
  const factory LineSummary({
    /// IDFM line id, e.g. `C01371`
    required String id,
    String? name,
    String? longName,
    @JsonKey(unknownEnumValue: TransportMode.bus) required TransportMode mode,

    /// Hex colors without `#`
    String? color,
    String? textColor,
  }) = _LineSummary;

  factory LineSummary.fromJson(Map<String, dynamic> json) => _$LineSummaryFromJson(json);
}

@freezed
abstract class StopAreaSummary with _$StopAreaSummary {
  const factory StopAreaSummary({
    /// Stop area id, e.g. `IDFM:71264`
    required String id,
    required String name,
    required double lat,
    required double lon,

    /// Meters from the requested position (nearby results only)
    int? distance,
    @Default([]) List<LineSummary> lines,
  }) = _StopAreaSummary;

  factory StopAreaSummary.fromJson(Map<String, dynamic> json) => _$StopAreaSummaryFromJson(json);
}

@freezed
abstract class Departure with _$Departure {
  const factory Departure({
    /// Expected time when real time, scheduled otherwise
    required DateTime time,
    DateTime? aimedTime,
    required bool realtime,

    /// `onTime`, `delayed`, `cancelled`…
    String? status,
    String? platform,
    bool? atStop,

    /// SNCF mission code (`POPI`)
    String? mission,

    /// SNCF train number
    String? trainNumber,
  }) = _Departure;

  const Departure._();

  bool get cancelled => status == 'cancelled';

  bool get delayed => status == 'delayed';

  factory Departure.fromJson(Map<String, dynamic> json) => _$DepartureFromJson(json);
}

@freezed
abstract class LineDepartures with _$LineDepartures {
  const factory LineDepartures({
    required LineSummary line,
    required String destination,
    @Default([]) List<Departure> departures,
  }) = _LineDepartures;

  factory LineDepartures.fromJson(Map<String, dynamic> json) => _$LineDeparturesFromJson(json);
}

/// How a ride's arrival is known
enum ArrivalSource {
  /// The vehicle's real-time calls
  realtime,

  /// Its scheduled trip, shifted by its delay
  scheduled,

  /// The line's usual ride time
  typical,
}

/// A departure of a line from a stop, with its arrival at a further stop (`/lines/{id}/rides`)
@freezed
abstract class Ride with _$Ride {
  const factory Ride({
    required Departure departure,
    required String destination,
    DateTime? arrivalAt,
    @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) ArrivalSource? arrivalSource,
  }) = _Ride;

  factory Ride.fromJson(Map<String, dynamic> json) => _$RideFromJson(json);
}

@freezed
abstract class StopDepartures with _$StopDepartures {
  const factory StopDepartures({
    required StopAreaSummary stop,

    /// False when the real-time feed could not be reached (scheduled departures only)
    required bool realtimeAvailable,
    @Default([]) List<LineDepartures> lines,
  }) = _StopDepartures;

  factory StopDepartures.fromJson(Map<String, dynamic> json) => _$StopDeparturesFromJson(json);
}

@freezed
abstract class Quay with _$Quay {
  const factory Quay({
    required String id,
    required String name,
    required double lat,
    required double lon,
    String? platformCode,

    /// 0 unknown, 1 accessible, 2 not accessible
    int? wheelchairBoarding,
    @Default([]) List<String> lineIds,
  }) = _Quay;

  factory Quay.fromJson(Map<String, dynamic> json) => _$QuayFromJson(json);
}

@freezed
abstract class Connection with _$Connection {
  const factory Connection({
    required String id,
    required String name,
    int? minTransferSeconds,
  }) = _Connection;

  factory Connection.fromJson(Map<String, dynamic> json) => _$ConnectionFromJson(json);
}

@freezed
abstract class StopAreaDetail with _$StopAreaDetail {
  const factory StopAreaDetail({
    required String id,
    required String name,
    required double lat,
    required double lon,

    /// 1 every quay accessible, 2 none, 0 otherwise or unknown
    @Default(0) int wheelchairBoarding,
    @Default([]) List<LineSummary> lines,
    @Default([]) List<Quay> quays,
    @Default([]) List<Connection> connections,
  }) = _StopAreaDetail;

  factory StopAreaDetail.fromJson(Map<String, dynamic> json) => _$StopAreaDetailFromJson(json);
}

@freezed
abstract class StopRef with _$StopRef {
  const factory StopRef({
    required String id,
    required String name,
    required double lat,
    required double lon,
  }) = _StopRef;

  factory StopRef.fromJson(Map<String, dynamic> json) => _$StopRefFromJson(json);
}

@freezed
abstract class LineBranch with _$LineBranch {
  const factory LineBranch({
    required String headsign,
    required int tripCount,
    @Default([]) List<StopRef> stops,

    /// `[lon, lat]` points of the drawn path
    @Default([]) List<List<double>> shape,
  }) = _LineBranch;

  factory LineBranch.fromJson(Map<String, dynamic> json) => _$LineBranchFromJson(json);
}

@freezed
abstract class LineDirection with _$LineDirection {
  const factory LineDirection({
    required int directionId,

    /// Most frequent first
    @Default([]) List<LineBranch> branches,
  }) = _LineDirection;

  factory LineDirection.fromJson(Map<String, dynamic> json) => _$LineDirectionFromJson(json);
}

@freezed
abstract class LineDetail with _$LineDetail {
  const factory LineDetail({
    required LineSummary line,
    @Default([]) List<LineDirection> directions,
  }) = _LineDetail;

  factory LineDetail.fromJson(Map<String, dynamic> json) => _$LineDetailFromJson(json);
}

enum PlaceType {
  @JsonValue('STOP_AREA')
  stopArea,
  @JsonValue('ADDRESS')
  address,
  @JsonValue('POI')
  poi,
}

@freezed
abstract class PlaceResult with _$PlaceResult {
  const factory PlaceResult({
    @JsonKey(unknownEnumValue: PlaceType.poi) required PlaceType type,

    /// Stop area id for stop areas, Navitia id otherwise
    required String id,

    /// With the town, e.g. `Mairie de Montreuil (Montreuil)`
    required String name,
    required double lat,
    required double lon,
    @Default([]) List<LineSummary> lines,
  }) = _PlaceResult;

  factory PlaceResult.fromJson(Map<String, dynamic> json) => _$PlaceResultFromJson(json);
}

@freezed
abstract class SearchResult with _$SearchResult {
  const factory SearchResult({
    @Default([]) List<LineSummary> lines,
    @Default([]) List<PlaceResult> places,
  }) = _SearchResult;

  factory SearchResult.fromJson(Map<String, dynamic> json) => _$SearchResultFromJson(json);
}

@freezed
abstract class JourneyPoint with _$JourneyPoint {
  const factory JourneyPoint({
    required String name,
    required double lat,
    required double lon,

    /// Set when the point is a stop
    String? stopAreaId,
  }) = _JourneyPoint;

  factory JourneyPoint.fromJson(Map<String, dynamic> json) => _$JourneyPointFromJson(json);
}

@freezed
abstract class JourneyStop with _$JourneyStop {
  const factory JourneyStop({
    required String name,
    required double lat,
    required double lon,
    DateTime? time,
  }) = _JourneyStop;

  factory JourneyStop.fromJson(Map<String, dynamic> json) => _$JourneyStopFromJson(json);
}

@freezed
abstract class WalkStep with _$WalkStep {
  const factory WalkStep({
    required String instruction,

    /// Meters
    @Default(0) int length,

    /// Seconds
    @Default(0) int duration,
  }) = _WalkStep;

  factory WalkStep.fromJson(Map<String, dynamic> json) => _$WalkStepFromJson(json);
}

enum SectionKind {
  @JsonValue('WALK')
  walk,
  @JsonValue('TRANSIT')
  transit,
  @JsonValue('TRANSFER')
  transfer,
  @JsonValue('WAIT')
  wait,
  @JsonValue('BIKE')
  bike,
  @JsonValue('CAR')
  car,
  @JsonValue('OTHER')
  other,
}

@freezed
abstract class JourneySection with _$JourneySection {
  const factory JourneySection({
    @JsonKey(unknownEnumValue: SectionKind.other) required SectionKind kind,
    required DateTime departure,
    required DateTime arrival,

    /// Seconds
    required int duration,
    JourneyPoint? from,
    JourneyPoint? to,
    LineSummary? line,
    String? headsign,

    /// `front`, `middle`, `back`
    @Default([]) List<String> boardingPositions,

    /// Served stops, boarding and alighting included
    @Default([]) List<JourneyStop> stops,
    @Default([]) List<WalkStep> steps,
    bool? realtime,

    /// Seconds late (real time only)
    int? delay,

    /// Meters
    int? length,

    /// `[lon, lat]` points
    @Default([]) List<List<double>> shape,
  }) = _JourneySection;

  factory JourneySection.fromJson(Map<String, dynamic> json) => _$JourneySectionFromJson(json);
}

@freezed
abstract class JourneyOption with _$JourneyOption {
  const factory JourneyOption({
    /// Navitia classification: `best`, `rapid`, `comfort`, `less_fallback_walk`, `non_pt_walk`…
    String? type,
    @Default([]) List<String> tags,
    required DateTime departure,
    required DateTime arrival,

    /// Seconds
    required int duration,
    @Default(0) int transfers,
    int? walkingDuration,
    int? walkingDistance,

    /// Grams per passenger
    double? co2,

    /// Euro cents
    int? fare,
    @Default([]) List<JourneySection> sections,
  }) = _JourneyOption;

  const JourneyOption._();

  /// Public transport sections
  List<JourneySection> get rides => sections.where((section) => section.kind == SectionKind.transit).toList();

  factory JourneyOption.fromJson(Map<String, dynamic> json) => _$JourneyOptionFromJson(json);
}

@freezed
abstract class PageCursor with _$PageCursor {
  const factory PageCursor({required DateTime datetime, required bool arriveBy}) = _PageCursor;

  factory PageCursor.fromJson(Map<String, dynamic> json) => _$PageCursorFromJson(json);
}

@freezed
abstract class JourneyPlan with _$JourneyPlan {
  const factory JourneyPlan({
    @Default([]) List<JourneyOption> journeys,
    PageCursor? earlier,
    PageCursor? later,
  }) = _JourneyPlan;

  factory JourneyPlan.fromJson(Map<String, dynamic> json) => _$JourneyPlanFromJson(json);
}

enum FavoriteKind {
  @JsonValue('HOME')
  home,
  @JsonValue('WORK')
  work,
  @JsonValue('PLACE')
  place,
  @JsonValue('STOP')
  stop,
  @JsonValue('LINE')
  line;

  String get apiName => name.toUpperCase();
}

@freezed
abstract class Favorite with _$Favorite {
  const factory Favorite({
    required int id,
    @JsonKey(unknownEnumValue: FavoriteKind.place) required FavoriteKind kind,

    /// Address, place or stop name; null for lines
    String? label,
    double? lat,
    double? lon,

    /// Stop favorites, and places that are stop areas
    String? stopAreaId,

    /// Stop area with its lines (stop favorites)
    StopAreaSummary? stop,

    /// Line favorites
    LineSummary? line,
  }) = _Favorite;

  factory Favorite.fromJson(Map<String, dynamic> json) => _$FavoriteFromJson(json);
}

enum DisruptionSeverity {
  @JsonValue('INFO')
  info,
  @JsonValue('DISRUPTED')
  disrupted,
  @JsonValue('BLOCKING')
  blocking,
}

enum DisruptionCategory {
  @JsonValue('TRAFFIC')
  traffic,
  @JsonValue('WORKS')
  works,
  @JsonValue('ELEVATOR')
  elevator,
}

@freezed
abstract class Disruption with _$Disruption {
  const factory Disruption({
    required String id,
    @JsonKey(unknownEnumValue: DisruptionSeverity.info) required DisruptionSeverity severity,
    @JsonKey(unknownEnumValue: DisruptionCategory.traffic) required DisruptionCategory category,
    String? title,

    /// Plain text, paragraphs separated by blank lines
    String? message,
    String? cause,

    /// Current period, or the next one when not active
    DateTime? start,
    DateTime? end,

    /// False for an upcoming disruption
    required bool active,
    DateTime? updatedAt,

    /// Impacted lines, empty for a stop-only disruption (elevator…)
    @Default([]) List<String> lineIds,
  }) = _Disruption;

  factory Disruption.fromJson(Map<String, dynamic> json) => _$DisruptionFromJson(json);
}

@freezed
abstract class LineTraffic with _$LineTraffic {
  const factory LineTraffic({
    required LineSummary line,

    /// Worst active disruption, null when the traffic is normal
    @JsonKey(unknownEnumValue: DisruptionSeverity.info) DisruptionSeverity? severity,

    /// Titles of the active disruptions, worst first
    @Default([]) List<String> titles,
  }) = _LineTraffic;

  factory LineTraffic.fromJson(Map<String, dynamic> json) => _$LineTrafficFromJson(json);
}

/// Vehicle of a line between two stops of one of its branches (directions/branches of [LineDetail])
@freezed
abstract class Vehicle with _$Vehicle {
  const factory Vehicle({
    required String id,

    /// Mission code or train number, when given (RER, Transilien)
    String? name,
    String? destination,
    required int direction,
    required int branch,

    /// Stop area just left, null when waiting at the first stop of the branch
    String? fromStopId,
    required String toStopId,
    String? toStopName,

    /// 0 (just left) to 1 (at the next stop), when fetched
    required double progress,
    required DateTime expectedAt,
    int? delaySeconds,

    /// Next stops with their times, from the next one (as far as the real time goes)
    @Default([]) List<VehicleCall> calls,
  }) = _Vehicle;

  factory Vehicle.fromJson(Map<String, dynamic> json) => _$VehicleFromJson(json);
}

/// A next stop of a vehicle
@freezed
abstract class VehicleCall with _$VehicleCall {
  const factory VehicleCall({
    required String stopId,
    String? stopName,
    required DateTime expectedAt,
    int? delaySeconds,
    String? platform,
  }) = _VehicleCall;

  factory VehicleCall.fromJson(Map<String, dynamic> json) => _$VehicleCallFromJson(json);
}

/// Scheduled departures of a line from a stop area over a service day (`/stops/{id}/timetable`)
@freezed
abstract class Timetable with _$Timetable {
  const factory Timetable({
    required StopAreaSummary stop,
    required LineSummary line,

    /// Service day: departures after midnight belong to the day before
    required DateTime date,
    @Default([]) List<TimetableDirection> directions,
  }) = _Timetable;

  factory Timetable.fromJson(Map<String, dynamic> json) => _$TimetableFromJson(json);
}

@freezed
abstract class TimetableDirection with _$TimetableDirection {
  const factory TimetableDirection({
    /// Main destinations, most served first
    required String name,
    @Default([]) List<TimetableEntry> departures,
  }) = _TimetableDirection;

  factory TimetableDirection.fromJson(Map<String, dynamic> json) => _$TimetableDirectionFromJson(json);
}

@freezed
abstract class TimetableEntry with _$TimetableEntry {
  const factory TimetableEntry({
    required DateTime time,
    required String destination,

    /// SNCF mission code
    String? mission,
  }) = _TimetableEntry;

  factory TimetableEntry.fromJson(Map<String, dynamic> json) => _$TimetableEntryFromJson(json);
}

/// A Vélib station with its availability
@freezed
abstract class BikeStation with _$BikeStation {
  const factory BikeStation({
    required String id,
    String? code,
    required String name,
    required double lat,
    required double lon,
    @Default(0) int capacity,
    @Default(0) int mechanical,
    @Default(0) int electric,

    /// Free docks
    @Default(0) int docks,
    @Default(true) bool renting,
    @Default(true) bool returning,

    /// Meters, when asked around a position
    int? distance,
    DateTime? reportedAt,
  }) = _BikeStation;

  const BikeStation._();

  int get bikes => mechanical + electric;

  factory BikeStation.fromJson(Map<String, dynamic> json) => _$BikeStationFromJson(json);
}
