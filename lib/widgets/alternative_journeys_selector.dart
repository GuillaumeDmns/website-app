import 'package:flutter/material.dart';
import 'package:website_app/models/navitia/vehicle_journeys.dart';
import 'package:website_app/models/navitia/vehicle_journey.dart';
import 'package:website_app/models/navitia/section.dart';
import 'package:website_app/models/navitia/embedded_type.dart';
import 'package:website_app/services/api_repository.dart';
import 'package:website_app/utils/time_utils.dart';

class AlternativeVehicleSelector extends StatefulWidget {
  final Section originalSection;
  final Function(VehicleJourney) onSelected;

  const AlternativeVehicleSelector({
    super.key,
    required this.originalSection,
    required this.onSelected,
  });

  @override
  State<AlternativeVehicleSelector> createState() =>
      _AlternativeVehicleSelectorState();
}

class _AlternativeVehicleSelectorState
    extends State<AlternativeVehicleSelector> {
  final ApiRepository _api = ApiRepository();
  bool _isLoading = true;
  List<VehicleJourney> _alternatives = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAlternatives();
  }

  DateTime? _getTrueDepartureTime(VehicleJourney journey, DateTime ref) {
    if (journey.stopTimes == null || journey.stopTimes!.isEmpty) return null;

    var targetStop = journey.stopTimes?.firstWhere(
      (st) => st.stopPoint?.id == widget.originalSection.from?.stopPoint?.id,
      orElse: () => journey.stopTimes!.first,
    );
    String? dtStr = targetStop?.departureTime;
    if (dtStr == null) return null;

    if (dtStr.length == 15) {
      try {
        return DateTime.parse(
            "${dtStr.substring(0, 4)}-${dtStr.substring(4, 6)}-${dtStr.substring(6, 8)} ${dtStr.substring(9, 11)}:${dtStr.substring(11, 13)}:${dtStr.substring(13, 15)}");
      } catch (_) {
        return null;
      }
    } else if (dtStr.length >= 6) {
      try {
        int h = int.parse(dtStr.substring(0, 2));
        int m = int.parse(dtStr.substring(2, 4));
        int s = int.parse(dtStr.substring(4, 6));

        int extraDays = h ~/ 24;
        h = h % 24;

        DateTime constructed = DateTime(ref.year, ref.month, ref.day, h, m, s)
            .add(Duration(days: extraDays));

        if (extraDays == 0) {
          if (constructed.difference(ref).inHours > 12) {
            constructed = constructed.subtract(const Duration(days: 1));
          } else if (constructed.difference(ref).inHours < -12) {
            constructed = constructed.add(const Duration(days: 1));
          }
        }
        return constructed;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> _fetchAlternatives() async {
    final String? stopPointId = widget.originalSection.from?.stopPoint?.id;
    if (stopPointId == null) {
      setState(() {
        _error = "Impossible d'identifier l'arrêt";
        _isLoading = false;
      });
      return;
    }

    try {
      DateTime referenceTime;
      if (widget.originalSection.departureDateTime != null) {
        referenceTime = TimeUtils.parseNavitiaTime(
            widget.originalSection.departureDateTime!);
      } else {
        referenceTime = DateTime.now();
      }

      DateTime startTime = referenceTime.subtract(const Duration(hours: 1));
      DateTime endTime = referenceTime.add(const Duration(hours: 2));

      VehicleJourneys result = await _api.getVehiclesJourneys(
        stopPointId,
        TimeUtils.formatNavitiaTime(startTime),
        TimeUtils.formatNavitiaTime(endTime),
      );

      List<VehicleJourney> journeys = result.vehicleJourneys ?? [];

      journeys.sort((a, b) {
        DateTime? ta = _getTrueDepartureTime(a, referenceTime);
        DateTime? tb = _getTrueDepartureTime(b, referenceTime);
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return ta.compareTo(tb);
      });

      setState(() {
        _alternatives = journeys;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle + header
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Text(
                  'Choisir un horaire',
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Divider(height: 1, color: colorScheme.outlineVariant),
              Flexible(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.error_outline,
                                      size: 44,
                                      color: colorScheme.error
                                          .withValues(alpha: 0.6)),
                                  const SizedBox(height: 12),
                                  Text('Erreur : $_error',
                                      textAlign: TextAlign.center,
                                      style: textTheme.bodyMedium),
                                ],
                              ),
                            ),
                          )
                        : _alternatives.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.departure_board_outlined,
                                        size: 44,
                                        color: colorScheme.onSurface
                                            .withValues(alpha: 0.3)),
                                    const SizedBox(height: 12),
                                    Text('Aucun autre départ trouvé',
                                        style: textTheme.bodyMedium?.copyWith(
                                            color: colorScheme.onSurface
                                                .withValues(alpha: 0.5))),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                itemCount: _alternatives.length,
                                separatorBuilder: (_, __) => Divider(
                                    height: 1,
                                    indent: 16,
                                    color: colorScheme.outlineVariant),
                                itemBuilder: (context, index) {
                                  final journey = _alternatives[index];
                                  var firstStopTime =
                                      journey.stopTimes?.firstWhere(
                                    (st) =>
                                        st.stopPoint?.id ==
                                        widget.originalSection.from?.stopPoint
                                            ?.id,
                                    orElse: () => journey.stopTimes!.first,
                                  );

                                  String timeStr = TimeUtils.formatTime(
                                      firstStopTime?.departureTime);
                                  bool isCurrent = firstStopTime
                                          ?.departureTime ==
                                      widget.originalSection.departureDateTime;

                                  return ListTile(
                                    leading: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isCurrent
                                            ? colorScheme.primary
                                            : colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        timeStr,
                                        style: textTheme.labelMedium?.copyWith(
                                          color: isCurrent
                                              ? colorScheme.onPrimary
                                              : colorScheme.onPrimaryContainer,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    subtitle: Builder(builder: (context) {
                                      String titleText = journey.name ??
                                          journey.journeyPattern?.route?.name ??
                                          journey.trip?.name ??
                                          'Trajet inconnu';
                                      return Text(
                                        titleText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.bodySmall?.copyWith(
                                          color: colorScheme.onSurface
                                              .withValues(alpha: 0.6),
                                        ),
                                      );
                                    }),
                                    title: Builder(builder: (context) {
                                      String titleText = journey.name ??
                                          journey.journeyPattern?.route?.name ??
                                          journey.trip?.name ??
                                          '';

                                      List<String> rawSub = [];
                                      if (journey.headsign != null &&
                                          journey.headsign!.isNotEmpty) {
                                        rawSub.add(journey.headsign!);
                                      }

                                      String? dirName;
                                      final direction = journey
                                          .journeyPattern?.route?.direction;
                                      if (direction != null) {
                                        if (direction.embeddedType ==
                                            EmbeddedTypeEnum.stopArea) {
                                          dirName = direction.stopArea?.name ??
                                              direction.name;
                                        } else if (direction.embeddedType ==
                                            EmbeddedTypeEnum.stopPoint) {
                                          dirName = direction.stopPoint?.name ??
                                              direction.name;
                                        } else {
                                          dirName = direction.name;
                                        }
                                      }
                                      dirName ??= journey.journeyPattern?.name;
                                      if (dirName != null &&
                                          dirName.isNotEmpty) {
                                        rawSub.add(dirName);
                                      }

                                      List<String> sub = [];
                                      for (String s in rawSub) {
                                        String bareS = s
                                            .replaceAll('Vers: ', '')
                                            .trim()
                                            .toLowerCase();
                                        String bareT =
                                            titleText.trim().toLowerCase();

                                        if (bareS == bareT ||
                                            bareT.contains(bareS)) {
                                          continue;
                                        }

                                        if (!sub.any((existing) => existing
                                            .toLowerCase()
                                            .contains(bareS))) {
                                          sub.add(s);
                                        }
                                      }

                                      if (sub.isEmpty)
                                        return const SizedBox.shrink();
                                      return Text(
                                        sub.join(' • '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: textTheme.bodyMedium?.copyWith(
                                          fontWeight: isCurrent
                                              ? FontWeight.w700
                                              : null,
                                        ),
                                      );
                                    }),
                                    trailing: isCurrent
                                        ? Icon(Icons.check_rounded,
                                            color: colorScheme.primary)
                                        : null,
                                    onTap: () => widget.onSelected(journey),
                                  );
                                },
                              ),
              ),
            ],
          ),
        )
    );
  }
}
