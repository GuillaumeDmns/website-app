# R8 rules of the release builds (added by the Flutter Gradle plugin to its own).
#
# Classes that Dart reaches by name through JNI (jnigen bindings) must be kept, or a release build fails where a debug
# build doesn't. None of the app's own for now: maplibre_native keeps the two classes its bindings name
# (MaplibreNativeApi, SurfaceListener) with its own consumer rules.
