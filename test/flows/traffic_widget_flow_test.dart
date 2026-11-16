import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/core/api/models.dart';

import '../support/fake_home_widget.dart';
import '../support/memory_store.dart';
import '../support/samples.dart';
import '../support/standard_backend.dart';
import '../support/test_app.dart';

/// Android's "Mes lignes" widget: the home page keeps it on the favorite lines and the traffic it shows
void main() {
  Map<String, Object?> lines(List<LineSummary> lines) => {
        'favorites': [for (final (index, line) in lines.indexed) Favorite(id: -1 - index, kind: FavoriteKind.line, line: line).toJson()],
      };

  testWidgets('the home page fills the widget with the traffic of the favorite lines, the worst first', (tester) async {
    final widgets = FakeHomeWidget(trafficWidgetIds: [5]);
    final backend = standardBackend();
    await pumpApp(tester, backend, store: MemoryStore(lines([rerA, metro1])));

    final rows = widgets.data['traffic_rows']!.trimRight().split('\n');
    // Métro 1 interrupted (standardBackend's traffic) before the RER A, normal
    expect(rows, [startsWith('C01371|1|FFCD00|000000|metro|b|'), 'C01742|A|EB2132|FFFFFF|rer|n|']);
    expect(widgets.data['traffic_lines'], startsWith('C01742|'));
    // The home page's own traffic: the widget asks nothing more
    expect(backend.requestsTo('/api/v2/traffic'), hasLength(1));
    await closeApp(tester);
  });

  testWidgets('without favorite line the widget says how to add one', (tester) async {
    final widgets = FakeHomeWidget(trafficWidgetIds: [5]);
    await pumpApp(tester, standardBackend());

    expect(widgets.data['traffic_lines'], '');
    expect(widgets.data['traffic_rows'], isNull);
    expect(widgets.data['traffic_message'], isNotNull);
    await closeApp(tester);
  });
}
