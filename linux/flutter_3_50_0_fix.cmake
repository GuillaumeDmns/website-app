# Flutter 3.50.0's Linux engine draws each frame half a window down and to the left where it can't use
# glBlitFramebuffer (NVIDIA's drivers among others): the app shows in the bottom left quarter of its window, and taps
# land where the hidden layout is. https://github.com/flutter/flutter/issues/195885, fixed for Flutter 3.50.1
# (https://github.com/flutter/flutter/pull/196083: the layer's offset left out its own half size).
#
# Until then, the bundle's copy of exactly that engine (debug, profile and release, by their SHA-256) gets the same
# correction in its compositing shader, a string of the same length: the vertex `offset + position * scale` becomes
# `offset + scale + position * scale`, as the fixed offset computes it (for the single layer the app has, at 0,0).
# Any other engine is left alone. Remove this file and its call in CMakeLists.txt with Flutter 3.50.1.
function(fix_flutter_3_50_0_engine library)
  file(SHA256 "${library}" hash)
  # Engine bf601093ad (Flutter 3.50.0): debug, profile, release, then the same corrected
  set(broken
    f38c8d6a0ef588b58daccdecaf2000f5cbdad267979369560c347a40af3eb258
    c31a78ca3aec4413815cb277b60ab4c1d42d4f00dd15bb3c1c21496f718e9786
    cb40d5867033badfa1a38072fab83f1c60ec1520c303a4810f49979f0ba5df04)
  set(fixed
    417a8693507627d15b02047b5de3091d793f8c0c0af5425b28d48cb2481916b9
    adf906b641aafb80b849c21ca233ec4320dc323dfbda370f54f9b3c0ce397d10
    27c50abf4f58e3ca8c4f7654a9bb3dff0e4f5a26e78e9d82f5b63d06e817e3a0)
  list(FIND broken "${hash}" index)
  if(index EQUAL -1)
    return()
  endif()
  list(GET fixed ${index} expected)
  # Byte for byte, whatever the locale
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env LC_ALL=C sed -i "s/gl_Position = vec4(offset + position \\* scale, 0, 1);/gl_Position=vec4(offset+scale+position*scale,0,1);  /" "${library}"
    RESULT_VARIABLE result)
  file(SHA256 "${library}" hash)
  if(NOT result EQUAL 0 OR NOT hash STREQUAL expected)
    message(FATAL_ERROR "Could not correct the Flutter 3.50.0 engine in ${library} (flutter_3_50_0_fix.cmake)")
  endif()
  message(STATUS "Corrected the Flutter 3.50.0 engine's compositing shader: ${library}")
endfunction()
