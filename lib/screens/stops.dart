import 'package:flutter/material.dart';
import 'package:website_app/models/stops_by_line_dto.dart';
import 'package:website_app/screens/next_departures.dart';
import 'package:website_app/widgets/line_icon.dart';

import '../models/line_dto.dart';
import '../services/api_repository.dart';

class StopsScreen extends StatefulWidget {
  const StopsScreen({super.key, required this.line});

  final LineDTO line;

  @override
  State<StopsScreen> createState() => _StopsScreenState();
}

class _StopsScreenState extends State<StopsScreen> {
  final api = ApiRepository();
  List<IDFMStopArea> stops = [];
  bool isLoading = false;

  Future<void> fetchStops() async {
    setState(() => isLoading = true);
    try {
      final response = await api.fetchStopsAndShape(widget.line.id!);
      setState(() => stops = response.stops);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    fetchStops();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LineIcon(line: widget.line),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                widget.line.name ?? '',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (isLoading) LinearProgressIndicator(color: colorScheme.primary),
          Expanded(
            child: stops.isEmpty && !isLoading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_off_outlined,
                            size: 44,
                            color: colorScheme.onSurface.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text('Aucun arrêt trouvé',
                            style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.5))),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: stops.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 70,
                      color: colorScheme.outlineVariant,
                    ),
                    itemBuilder: (context, index) {
                      final stop = stops[index];
                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              stop.name![0].toUpperCase(),
                              style: textTheme.titleSmall?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          stop.name!,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => NextDeparturesScreen(
                                lineId: widget.line.id!,
                                stop: stop,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
