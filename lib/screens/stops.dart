import 'package:flutter/material.dart';
import 'package:website_app/models/stops_by_line_dto.dart';
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
    setState(() {
      isLoading = true;
    });

    try {
      final response = await api.fetchStopsAndShape(widget.line.id!);
      stops = response.stops;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching stops: $e')),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    fetchStops();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: LineIcon(line: widget.line),
      ),
      body: Column(
        children: [
          if (isLoading) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              children: [
                for (var stop in stops) ...[
                  ListTile(
                    leading: CircleAvatar(child: Text(stop.name![0])),
                    title: Text(stop.name!),
                    subtitle: Text('${stop.latitude} / ${stop.longitude}'),
                    trailing: Icon(Icons.favorite_outline_rounded),
                  ),
                  if (stop != stops.last) Divider(height: 0),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
