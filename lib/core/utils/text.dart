/// Lower case, no accents, words separated by single spaces: to compare destinations from different sources
/// (`Gare de Lyon (Paris)` / `GARE DE LYON`).
String normalizeName(String value) => value
    .toLowerCase()
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[àâä]'), 'a')
    .replaceAll(RegExp('[îï]'), 'i')
    .replaceAll(RegExp('[ôö]'), 'o')
    .replaceAll(RegExp('[ùûü]'), 'u')
    .replaceAll('ç', 'c')
    .replaceAll(RegExp('[^a-z0-9]+'), ' ')
    .trim();

/// One of the names contains the other (a headsign often is a shorter form of the real-time destination)
bool sameDestination(String a, String b) {
  final x = normalizeName(a);
  final y = normalizeName(b);
  return x.isNotEmpty && y.isNotEmpty && (x.contains(y) || y.contains(x));
}
