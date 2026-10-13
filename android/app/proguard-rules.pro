# R8 rules of the release builds (added by the Flutter Gradle plugin to its own).

# maplibre_android drives the MapLibre SDK from Dart through JNI (jnigen): classes, methods and fields are looked up by
# name, and the interfaces implemented in Dart are matched by method name. Its own rules keep org.maplibre.** and Gson
# only; without these the map's platform view comes back null (PlatformViewsController NullPointerException, no map).
-keep class com.github.josxha.maplibre.** { *; }
-keep interface io.flutter.plugin.platform.PlatformView { *; }
-keep class io.flutter.plugin.platform.PlatformViewFactory { *; }
-keep interface io.flutter.plugin.common.PluginRegistry { *; }
-keep interface io.flutter.plugin.common.PluginRegistry$* { *; }
-keep interface io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding { *; }
-keep interface io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding$* { *; }
