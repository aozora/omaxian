cmake_minimum_required(VERSION 3.21)
project(fantasi LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Qt6 REQUIRED COMPONENTS Core Gui Network Qml Quick QuickControls2 DBus Concurrent ShaderTools)

# Everything but main.cpp, shared by the app and the tests, so each source
# compiles once and a new file in src/ needs no line here.
file(GLOB fantasi_sources CONFIGURE_DEPENDS src/*.cpp src/*.h)
list(REMOVE_ITEM fantasi_sources ${CMAKE_SOURCE_DIR}/src/main.cpp)
add_library(fantasi_core STATIC ${fantasi_sources})
target_include_directories(fantasi_core PUBLIC src)
target_link_libraries(fantasi_core PUBLIC
  Qt6::Core Qt6::Gui Qt6::Network Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::DBus Qt6::Concurrent)
target_compile_options(fantasi_core PUBLIC -Wall -Wextra)

add_executable(fantasi src/main.cpp src/resources.qrc)
target_link_libraries(fantasi PRIVATE fantasi_core)
# The aurora's shader, compiled for every graphics API Qt might use.
qt_add_shaders(fantasi "shaders" PREFIX "/" BASE src FILES src/aurora.frag)

# The tests load the real Main.qml, so they carry the resources too.
# Omaxian: Qt Test is only for the tests. Probe the .so first: an incomplete
# local Qt overlay can ship Qt6TestConfig.cmake without the library, and
# find_package then fatals inside Qt6TestTargets.cmake.
enable_testing()
set(_fantasi_have_qt6_test FALSE)
file(GLOB _fantasi_qt6_test_so
  /usr/lib/*/libQt6Test.so
  $ENV{HOME}/.local/opt/omaxian-qt6-*/usr/lib/*/libQt6Test.so)
foreach(_fantasi_qt6_test_candidate IN LISTS _fantasi_qt6_test_so)
  get_filename_component(_fantasi_qt6_test_real "${_fantasi_qt6_test_candidate}" REALPATH)
  if(EXISTS "${_fantasi_qt6_test_real}")
    set(_fantasi_have_qt6_test TRUE)
  endif()
endforeach()
if(_fantasi_have_qt6_test)
  find_package(Qt6 COMPONENTS Test)
endif()
if(TARGET Qt6::Test)
  add_executable(fantasi_tests tests/fantasi_tests.cpp src/resources.qrc)
  target_link_libraries(fantasi_tests PRIVATE fantasi_core Qt6::Test)
  qt_add_shaders(fantasi_tests "shaders" PREFIX "/" BASE src FILES src/aurora.frag)
  add_test(NAME fantasi_tests COMMAND fantasi_tests)
  set_tests_properties(fantasi_tests PROPERTIES ENVIRONMENT QT_QPA_PLATFORM=offscreen)
else()
  message(STATUS "Qt6::Test not found: building without the tests")
endif()

# `cmake --install build --prefix ~/.local` puts the app in the launcher
# before it is packaged; a package installs the same files under /usr.
include(GNUInstallDirs)
install(TARGETS fantasi RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES share/fantasi.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES share/fantasi.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
install(FILES LICENSE DESTINATION ${CMAKE_INSTALL_DATADIR}/licenses/fantasi)
