import 'context.dart';
import 'disruption.dart';
import 'feed_publisher.dart';
import 'link_schema.dart';
import 'pagination.dart';
import 'stop_area.dart';
import 'vehicle_journey.dart';

class VehicleJourneys {
  final Pagination? pagination;
  final List<FeedPublisher>? feedPublishers;
  final List<Disruption>? disruptions;
  final List<StopArea>? origins;
  final List<StopArea>? terminus;
  final Context? context;
  final List<VehicleJourney>? vehicleJourneys;
  final List<LinkSchema>? links;

  VehicleJourneys({
    this.pagination,
    this.feedPublishers,
    this.disruptions,
    this.origins,
    this.terminus,
    this.context,
    this.vehicleJourneys,
    this.links,
  });

  factory VehicleJourneys.fromJson(Map<String, dynamic> json) {
    return VehicleJourneys(
      pagination: json['pagination'] != null
          ? Pagination.fromJson(json['pagination'])
          : null,
      feedPublishers: (json['feedPublishers'] as List?)
          ?.map((e) => FeedPublisher.fromJson(e))
          .toList(),
      disruptions: (json['disruptions'] as List?)
          ?.map((e) => Disruption.fromJson(e))
          .toList(),
      origins: (json['origins'] as List?)
          ?.map((e) => StopArea.fromJson(e))
          .toList(),
      terminus: (json['terminus'] as List?)
          ?.map((e) => StopArea.fromJson(e))
          .toList(),
      context:
      json['context'] != null ? Context.fromJson(json['context']) : null,
      vehicleJourneys: (json['vehicleJourneys'] as List?)
          ?.map((e) => VehicleJourney.fromJson(e))
          .toList(),
      links: (json['links'] as List?)
          ?.map((e) => LinkSchema.fromJson(e))
          .toList(),
    );
  }
}