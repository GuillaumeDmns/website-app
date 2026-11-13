# Flutter 3.50.0's Linux engine draws each frame half a window down and to the left where it can't use
# glBlitFramebuffer (NVIDIA's drivers among others): the app shows in the bottom left quarter of its window, and taps
# land where the hidden layout is. https://github.com/flutter/flutter/issues/195885, fixed for Flutter 3.50.1
# (https://github.com/flutter/flutter/pull/196083: the layer's offset left out its own half size).
#
# Until then, the bundle's copy of exactly that engine (debug, profile and release, by their SHA-256) gets a corrected
# compositing shader, a string of the same length: the vertex `offset + position * scale` becomes `position * scale`.
# The engine draws with that shader twice on Wayland (the layers into the frame, `offset` 2x/width - 1, the bug; then
# the frame onto the window's subsurface, `offset` 0, right) and once on X11 (the layers): leaving the offset out is
# right for both as long as the app has a single layer, at 0,0, the size of the frame (no platform views on Linux).
# Correcting the layers' offset alone (`offset + scale + …`, as Flutter's fix does) drew the app half a window up and to
# the right on Wayland. Any other engine is left alone. Remove this file and its call in CMakeLists.txt with 3.50.1.
function(fix_flutter_3_50_0_engine library)
  file(SHA256 "${library}" hash)
  # Engine bf601093ad (Flutter 3.50.0): debug, profile, release, then the same corrected
  set(broken
    f38c8d6a0ef588b58daccdecaf2000f5cbdad267979369560c347a40af3eb258
    c31a78ca3aec4413815cb277b60ab4c1d42d4f00dd15bb3c1c21496f718e9786
    cb40d5867033badfa1a38072fab83f1c60ec1520c303a4810f49979f0ba5df04)
  set(fixed
    427be845e9db979ee9edb8e7f98ea16ed4649057f3a157aee29b0cb747d77aed
    73d5f211481b4873b01fce0dd787a5a8128956037d5467f5e45e8e333d2ae21d
    aac5c00afbeef6d3693034ddfc821727592e552db346d77bafb680dab09f1c34)
  list(FIND broken "${hash}" index)
  if(index EQUAL -1)
    return()
  endif()
  list(GET fixed ${index} expected)
  # Byte for byte, whatever the locale
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env LC_ALL=C sed -i "s/gl_Position = vec4(offset + position \\* scale, 0, 1);/gl_Position=vec4(position*scale,0,1);               /" "${library}"
    RESULT_VARIABLE result)
  file(SHA256 "${library}" hash)
  if(NOT result EQUAL 0 OR NOT hash STREQUAL expected)
    message(FATAL_ERROR "Could not correct the Flutter 3.50.0 engine in ${library} (flutter_3_50_0_fix.cmake)")
  endif()
  message(STATUS "Corrected the Flutter 3.50.0 engine's compositing shader: ${library}")
endfunction()
