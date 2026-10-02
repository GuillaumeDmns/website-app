import 'package:freezed_annotation/freezed_annotation.dart';

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

  String get label => switch (this) {
        metro => 'Métro',
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
