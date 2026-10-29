cmake_minimum_required(VERSION 3.20)
project(rizzgame_backend LANGUAGES C)
include(FetchContent)

# Pinned source and checksum keep every release on the ABI tested by the Nim FFI.
set(BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_GAMES OFF CACHE BOOL "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(APPLE)
  set(CMAKE_OSX_DEPLOYMENT_TARGET 12.0 CACHE STRING "" FORCE)
endif()
FetchContent_Declare(raylib
  URL https://github.com/raysan5/raylib/archive/refs/tags/5.5.tar.gz
  URL_HASH SHA256=aea98ecf5bc5c5e0b789a76de0083a21a70457050ea4cc2aec7566935f5e258e
  DOWNLOAD_EXTRACT_TIMESTAMP FALSE)
FetchContent_MakeAvailable(raylib)

if(NOT RIZZGAME_OUTPUT_DIR)
  set(RIZZGAME_OUTPUT_DIR "${CMAKE_BINARY_DIR}/dist")
endif()
if(WIN32)
  set(RIZZGAME_LIBRARY "raylib.dll")
elseif(APPLE)
  set(RIZZGAME_LIBRARY "libraylib.dylib")
else()
  set(RIZZGAME_LIBRARY "libraylib.so")
endif()
add_custom_target(rizzgame_backend ALL
  COMMAND ${CMAKE_COMMAND} -E make_directory "${RIZZGAME_OUTPUT_DIR}"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:raylib>" "${RIZZGAME_OUTPUT_DIR}/${RIZZGAME_LIBRARY}"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE.raylib" "${RIZZGAME_OUTPUT_DIR}/LICENSE.raylib"
  DEPENDS raylib
  VERBATIM)
