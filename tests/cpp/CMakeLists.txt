# Qt-only unit tests for tray logic that does not need Plasma to build.
#
#   cmake -S tests/cpp -B build-tests && cmake --build build-tests && ctest --test-dir build-tests --output-on-failure
#
# The real sources are compiled against small stand-ins for the KDE types they
# touch (see stubs/), so only Qt6 Core, DBus and Test are required.
cmake_minimum_required(VERSION 3.20)
project(windowsmodern-systemtray-tests LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
enable_testing()

find_package(Qt6 REQUIRED COMPONENTS Core DBus Test)

# Copy the real sources next to the stubs, so that their quoted includes
# ("systemtraysettings.h", "debug.h") resolve to the stand-ins.
set(SRC "${CMAKE_CURRENT_SOURCE_DIR}/../../system-tray")
set(WORK "${CMAKE_CURRENT_BINARY_DIR}/work")
file(MAKE_DIRECTORY "${WORK}")
foreach(f dbusserviceobserver.h dbusserviceobserver.cpp)
    configure_file("${SRC}/${f}" "${WORK}/${f}" COPYONLY)
endforeach()
foreach(f debug.h systemtraysettings.h KPluginMetaData)
    configure_file("${CMAKE_CURRENT_SOURCE_DIR}/stubs/${f}" "${WORK}/${f}" COPYONLY)
endforeach()

add_executable(dbusserviceobserver_test
    dbusserviceobserver_test.cpp
    "${WORK}/dbusserviceobserver.cpp"
    "${WORK}/systemtraysettings.h"
)
target_include_directories(dbusserviceobserver_test PRIVATE "${WORK}")
target_link_libraries(dbusserviceobserver_test PRIVATE Qt6::Core Qt6::DBus Qt6::Test)
add_test(NAME dbusserviceobserver COMMAND dbusserviceobserver_test)
