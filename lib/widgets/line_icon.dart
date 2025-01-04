import 'package:flutter/material.dart';

import '../models/line_dto.dart';

class LineIcon extends StatelessWidget {
  final LineDTO line;

  const LineIcon({
    super.key,
    required this.line,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: 40,
        maxHeight: 40,
      ),
      decoration: BoxDecoration(
        color: getLineBackgroundColor(line),
        borderRadius: getLineBorderRadius(line),
        border: getLineBorder(line),
      ),
      padding: getLinePadding(line),
      alignment: Alignment.center,
      child: Text(
        line.name ?? '',
        style: TextStyle(
          color: getLineTextColor(line),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }


  Color getLineBackgroundColor(LineDTO line) {
    switch (line.transportMode) {
      case "TRAM":
        return Colors.white;
      case "BUS":
      case "NOCTILIEN":
      case "RER":
      case "METRO":
      case "TER":
      default:
        return Color(int.parse("0xFF${line.lineIdBackgroundColor}"));
    }
  }

  Color getLineTextColor(LineDTO line) {
    switch (line.transportMode) {
      case "TRAM":
        return Colors.black;
      case "BUS":
      case "NOCTILIEN":
      case "RER":
      case "METRO":
      case "TER":
      default:
        return Color(int.parse("0xFF${line.lineIdColor}"));
    }
  }

  BorderRadius getLineBorderRadius(LineDTO line) {
    switch (line.transportMode) {
      case "METRO":
        return BorderRadius.circular(20.0);
      case "RER":
      case "TRANSILIEN":
        return BorderRadius.circular(10.0);
      case "BUS":
      case "NOCTILIEN":
      case "TRAM":
      case "TER":
      default:
        return BorderRadius.zero;
    }
  }

  Border getLineBorder(LineDTO line) {
    switch (line.transportMode) {
      case "TRAM":
        BorderSide borderSide = BorderSide(width: 5, color: Color(int.parse('0xFF${line.lineIdBackgroundColor}')));
        return Border(
          top: borderSide,
          bottom: borderSide,
        );
      case "METRO":
      case "BUS":
      case "NOCTILIEN":
      case "RER":
      case "TER":
      default:
        return Border.all(color: Colors.transparent, width: 0.0);
    }
  }

  EdgeInsets getLinePadding(LineDTO line) {
    switch (line.transportMode) {
      case "BUS":
      case "NOCTILIEN":
        return const EdgeInsets.symmetric(horizontal: 5.0);
      case "TRAM":
      case "METRO":
      case "RER":
      case "TER":
      default:
        return const EdgeInsets.all(5.0);
    }
  }
}
