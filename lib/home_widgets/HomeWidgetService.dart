import 'package:flutter/cupertino.dart';
import 'package:home_widget/home_widget.dart';

import '../models/call_unit.dart';
import '../services/api_repository.dart';

class HomeWidgetService {
  static const String _androidWidgetName = 'NextDepartures';

  static Future<void> _saveWidgetConfig(String lineId, String stopId, String stopName) async {
    await HomeWidget.saveWidgetData<String>('saved_line_id', lineId);
    await HomeWidget.saveWidgetData<String>('saved_stop_id', stopId);
    await HomeWidget.saveWidgetData<String>('stop_name', stopName);
  }

  static Future<void> saveCurrentStation(
      String lineId, String stopId, String stopName) async {
    await _saveWidgetConfig(lineId, stopId, stopName);
    await HomeWidget.saveWidgetData<String>(
        'departures_list', "Appuyez pour charger");
    await HomeWidget.updateWidget(
        name: _androidWidgetName, androidName: _androidWidgetName);
  }

  static Future<void> updateWidgetData(
      String lineId, String stopId, String stopName, List<CallUnit> departures) async {

    await _saveWidgetConfig(lineId, stopId, stopName);

    String formattedDepartures;
    if (departures.isEmpty) {
      formattedDepartures = "Aucun départ prévu";
    } else {
      formattedDepartures = departures.take(4).map((d) {
        String time = d.expectedDepartureTime?.substring(11, 16) ?? "--:--";
        String direction = d.destinationName ?? "";
        return "🕒 $time  ➜ $direction";
      }).join('\n');
    }

    await HomeWidget.saveWidgetData<String>(
        'departures_list', formattedDepartures);

    await HomeWidget.updateWidget(
      name: _androidWidgetName,
      androidName: _androidWidgetName,
    );
  }
}

@pragma('vm:entry-point')
Future<void> refreshCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();

  await HomeWidget.saveWidgetData<String>('departures_list', "Chargement en cours...");
  await HomeWidget.updateWidget(name: 'NextDepartures', androidName: 'NextDepartures');

  try {
    final lineId = await HomeWidget.getWidgetData<String>('saved_line_id');
    final stopId = await HomeWidget.getWidgetData<String>('saved_stop_id');
    final stopName = await HomeWidget.getWidgetData<String>('stop_name') ?? "Station";

    if (stopId == null || lineId == null) {
      await HomeWidget.saveWidgetData<String>('departures_list', "Ouvrez l'app pour configurer un arrêt");
      await HomeWidget.updateWidget(name: 'NextDepartures', androidName: 'NextDepartures');
      return;
    }

    final api = ApiRepository();
    final departures = await api.fetchNextDepartures(stopId, lineId);

    await HomeWidgetService.updateWidgetData(lineId, stopId, stopName, departures.nextPassages);

  } catch (e) {
    await HomeWidget.saveWidgetData<String>('departures_list', "Erreur de connexion");
    await HomeWidget.updateWidget(name: 'NextDepartures', androidName: 'NextDepartures');
  }
}
