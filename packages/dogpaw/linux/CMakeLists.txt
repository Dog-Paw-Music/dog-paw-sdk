# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. Keep this aligned with Flutter's generated plugin templates so the
# package can be consumed as a normal Linux FFI plugin by app bundles.
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "dogpaw")
project(${PROJECT_NAME} LANGUAGES CXX)

get_filename_component(DOGPAW_PACKAGE_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." REALPATH)
set(DOGPAW_PREBUILT_ROOT "${DOGPAW_PACKAGE_ROOT}/linux/prebuilt")
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64)$")
  set(DOGPAW_PREBUILT_BRIDGE
    "${DOGPAW_PREBUILT_ROOT}/linux-x64/libdogpaw_bridge.so"
  )
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
  set(DOGPAW_PREBUILT_BRIDGE
    "${DOGPAW_PREBUILT_ROOT}/linux-arm64/libdogpaw_bridge.so"
  )
else()
  message(FATAL_ERROR
    "dogpaw: unsupported Linux processor '${CMAKE_SYSTEM_PROCESSOR}'. "
    "Package a matching prebuilt libdogpaw_bridge.so artifact."
  )
endif()

if(NOT EXISTS "${DOGPAW_PREBUILT_BRIDGE}")
  message(FATAL_ERROR
    "dogpaw: missing packaged bridge library '${DOGPAW_PREBUILT_BRIDGE}'. "
    "Build the repo-local dogpaw_bridge target to refresh package artifacts "
    "or provide a matching prebuilt libdogpaw_bridge.so artifact."
  )
endif()

# Expose the bridge library to consuming Flutter app bundles.
set(dogpaw_bundled_libraries
  "${DOGPAW_PREBUILT_BRIDGE}"
  PARENT_SCOPE
)
