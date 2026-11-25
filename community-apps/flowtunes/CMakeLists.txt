cmake_minimum_required(VERSION 3.21)
project(flowtunes LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Qt6 REQUIRED COMPONENTS Core Gui Network Qml Quick QuickControls2 DBus ShaderTools)

# Everything but main.cpp, shared by the app and the tests, so each source
# compiles once and a new file in src/ needs no line here.
file(GLOB flowtunes_sources CONFIGURE_DEPENDS src/*.cpp src/*.h)
list(REMOVE_ITEM flowtunes_sources ${CMAKE_SOURCE_DIR}/src/main.cpp)
add_library(flowtunes_core STATIC ${flowtunes_sources})
target_include_directories(flowtunes_core PUBLIC src)
target_link_libraries(flowtunes_core PUBLIC
  Qt6::Core Qt6::Gui Qt6::Network Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::DBus)
target_compile_options(flowtunes_core PUBLIC -Wall -Wextra)

add_executable(flowtunes src/main.cpp src/resources.qrc)
target_link_libraries(flowtunes PRIVATE flowtunes_core)
# The aurora's shader, compiled for every graphics API Qt might use.
qt_add_shaders(flowtunes "shaders" PREFIX "/" BASE src FILES src/aurora.frag)

# The tests load the real Main.qml, so they carry the resources too.
# Omaxian: Qt Test is only for the tests. Probe the .so first: an incomplete
# local Qt overlay can ship Qt6TestConfig.cmake without the library, and
# find_package then fatals inside Qt6TestTargets.cmake.
enable_testing()
set(_flowtunes_have_qt6_test FALSE)
file(GLOB _flowtunes_qt6_test_so
  /usr/lib/*/libQt6Test.so
  $ENV{HOME}/.local/opt/omaxian-qt6-*/usr/lib/*/libQt6Test.so)
foreach(_flowtunes_qt6_test_candidate IN LISTS _flowtunes_qt6_test_so)
  get_filename_component(_flowtunes_qt6_test_real "${_flowtunes_qt6_test_candidate}" REALPATH)
  if(EXISTS "${_flowtunes_qt6_test_real}")
    set(_flowtunes_have_qt6_test TRUE)
  endif()
endforeach()
if(_flowtunes_have_qt6_test)
  find_package(Qt6 COMPONENTS Test)
endif()
if(TARGET Qt6::Test)
  add_executable(flowtunes_tests tests/flowtunes_tests.cpp src/resources.qrc)
  target_link_libraries(flowtunes_tests PRIVATE flowtunes_core Qt6::Test)
  qt_add_shaders(flowtunes_tests "shaders" PREFIX "/" BASE src FILES src/aurora.frag)
  add_test(NAME flowtunes_tests COMMAND flowtunes_tests)
  set_tests_properties(flowtunes_tests PROPERTIES ENVIRONMENT QT_QPA_PLATFORM=offscreen)
else()
  message(STATUS "Qt6::Test not found: building without the tests")
endif()

# `cmake --install build --prefix ~/.local` puts the app in the launcher
# before it is packaged; a package installs the same files under /usr.
include(GNUInstallDirs)
install(TARGETS flowtunes RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES share/flowtunes.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES share/flowtunes.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
install(FILES LICENSE DESTINATION ${CMAKE_INSTALL_DATADIR}/licenses/flowtunes)
