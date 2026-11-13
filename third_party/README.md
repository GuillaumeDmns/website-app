# Third-party code

## maplibre_android

A copy of [`maplibre_android` 0.3.7+1](https://pub.dev/packages/maplibre_android) (BSD 3-Clause, `maplibre_android/LICENSE`), the Android side of the `maplibre` map, used through `dependency_overrides` in `pubspec.yaml`. Only `LICENSE`, `pubspec.yaml`, `lib/` and `android/` are kept (no example, tool nor tests).

Changes from the published package:

- `lib/src/style_controller.dart`, `addImage`: the PNG is decoded at the screen's density (`inDensity = targetDensity`) instead of being scaled up from 160 dpi to it. The app draws its pins at the screen's density already (`MapLibreOverlay`, `overlayIconSize`); scaled up once more, every image came 2.625² too big on a Pixel 10, MapLibre's icon atlas outgrew what the GPU takes and pins showed pieces of others (Vélib, turn callouts, station exits). Drawing them at 1 instead was blurry.
- `pubspec.yaml`: without `resolution: workspace` (the package belongs to its own repository's workspace, not this one).

To drop the copy: once a release of `maplibre_android` decodes images without scaling them (or lets the caller say their density), remove `third_party/maplibre_android`, the `dependency_overrides` and the `.gitignore` exception, then check the pins on an Android phone (`overlayIconSize`).
