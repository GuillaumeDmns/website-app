import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../../../core/api/models.dart';

/// Navy of the stations' signs: a way in or out never looks like a turn of the walk (a white callout pointing at the
/// street) nor a stop (a round dot)
const stationAccessColor = Color(0xFF233A7E);

/// A station's way in or out on the map, like the sign over its stairs: its number on a navy square (a door without
/// one); the one the journey takes green, with its street ([taken])
class StationAccessSign extends StatelessWidget {
  const StationAccessSign({super.key, required this.entrance, this.taken = false});

  final StationEntrance entrance;
  final bool taken;

  /// The box each sign is drawn in (MapLibre makes an image of it): room for a number of three characters, or for the
  /// street of the one taken
  static const size = Size(34, 28);
  static const takenSize = Size(220, 32);

  /// Names the sign's look, the same name for the same look
  static String imageOf(StationEntrance entrance, {bool taken = false}) =>
      taken ? 'access-taken-${entrance.code ?? ''}-${entrance.name}' : 'access-${entrance.code ?? 'door'}';

  /// The map stays light in dark mode too: fixed colors
  static const _edge = Colors.white;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600, height: 1);
    final code = entrance.code;
    final mark = code == null ? const Icon(Icons.door_front_door, size: 14, color: Colors.white) : Text(code, style: style);
    if (!taken) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: _decoration(stationAccessColor),
          child: mark,
        ),
      );
    }
    // The way taken: its number in a white square on green, its street beside it
    return Center(
      child: Container(
        height: 26,
        padding: const EdgeInsets.fromLTRB(3, 3, 8, 3),
        decoration: _decoration(AppTheme.brand),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 18),
              padding: const EdgeInsets.symmetric(horizontal: 3),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _edge, borderRadius: BorderRadius.circular(3)),
              child: code == null
                  ? const Icon(Icons.door_front_door, size: 14, color: AppTheme.brand)
                  : Text(code, style: style?.copyWith(color: AppTheme.brand)),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(entrance.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style?.copyWith(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  static BoxDecoration _decoration(Color color) => BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: _edge, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
      );
}
