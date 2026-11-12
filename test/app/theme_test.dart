import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:website_app/app/theme.dart';

void main() {
  List<TextStyle?> styles(TextTheme theme) => [
        theme.displayLarge,
        theme.displayMedium,
        theme.displaySmall,
        theme.headlineLarge,
        theme.headlineMedium,
        theme.headlineSmall,
        theme.titleLarge,
        theme.titleMedium,
        theme.titleSmall,
        theme.bodyLarge,
        theme.bodyMedium,
        theme.bodySmall,
        theme.labelLarge,
        theme.labelMedium,
        theme.labelSmall,
      ];

  test('every text style of both themes is in Inter', () {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      for (final style in [...styles(theme.textTheme), ...styles(theme.primaryTextTheme)]) {
        expect(style?.fontFamily, startsWith('Inter'));
      }
    }
  });

  test('the sizes Material gives the styles the theme does not set are kept', () {
    final material = ThemeData(useMaterial3: true).textTheme;
    final theme = AppTheme.lightTheme.textTheme;
    expect(theme.displayLarge?.fontSize, material.displayLarge?.fontSize);
    expect(theme.labelSmall?.fontSize, material.labelSmall?.fontSize);
    expect(theme.titleLarge?.fontSize, 21);
  });
}
