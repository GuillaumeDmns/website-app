import 'package:material_ui/material_ui.dart';

import '../../../app/theme.dart';
import '../../../core/api/models.dart';

/// Navy of the stations' ways in and out: a way in or out never looks like a turn of the walk (a white callout pointing
/// at the street) nor a stop (a round dot)
const stationAccessColor = Color(0xFF1F3270);

/// A station's way in or out on the map, like a label of the map itself: no background, its pictogram (out of the
/// station where the journey gets out, [exit], in otherwise) and its number on the signs when it has one, ringed with
/// white to stand out; the one the journey takes green, with its street ([taken])
class StationAccessSign extends StatelessWidget {
  const StationAccessSign({super.key, required this.entrance, required this.exit, this.taken = false});

  final StationEntrance entrance;
  final bool exit;
  final bool taken;

  /// Every way out, numbered or not, and every way in: never an arrow alone, like a turn of the walk
  static const exitIcon = Icons.exit_to_app;
  static const entranceIcon = Icons.login;

  /// The box each sign is drawn in (MapLibre makes an image of it), its pictogram in the middle, on the way in or out
  /// itself, the rest on its right: room for a number of three characters, or for the street of the one taken
  static const size = Size(72, 26);
  static const takenSize = Size(300, 28);

  /// Names the sign's look, the same name for the same look
  static String imageOf(StationEntrance entrance, {required bool exit, bool taken = false}) =>
      'access-${exit ? 'out' : 'in'}-${entrance.code ?? ''}${taken ? '-taken-${entrance.name}' : ''}';

  @override
  Widget build(BuildContext context) {
    final color = taken ? AppTheme.brand : stationAccessColor;
    final text = [?entrance.code, if (taken) entrance.name].join(' · ');
    final iconSize = taken ? 19.0 : 17.0;
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        // The pictogram in the middle of the box, where the pin stands
        padding: EdgeInsets.only(left: (constraints.maxWidth - iconSize) / 2),
        child: Row(
          children: [
            Icon(exit ? exitIcon : entranceIcon, size: iconSize, color: color, shadows: _halo),
            if (text.isNotEmpty) ...[
              const SizedBox(width: 1),
              Flexible(child: _HaloText(text, color: color, size: taken ? 14 : 13)),
            ],
          ],
        ),
      ),
    );
  }

  /// White all around, like the labels of the map: the map stays light in dark mode too
  static final _halo = [
    for (final offset in [Offset(1.2, 0), Offset(-1.2, 0), Offset(0, 1.2), Offset(0, -1.2), Offset(0.9, 0.9), Offset(-0.9, -0.9), Offset(0.9, -0.9), Offset(-0.9, 0.9)])
      Shadow(color: Colors.white, offset: offset),
  ];
}

/// Bold text ringed with white
class _HaloText extends StatelessWidget {
  const _HaloText(this.text, {required this.color, required this.size});

  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: size, fontWeight: FontWeight.w600, height: 1.1);
    return Stack(
      children: [
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style?.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5
              ..strokeJoin = StrokeJoin.round
              ..color = Colors.white,
          ),
        ),
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style?.copyWith(color: color)),
      ],
    );
  }
}
