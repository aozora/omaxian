cmake_minimum_required(VERSION 3.21)
project(checkmate LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Qt6 REQUIRED COMPONENTS Core Gui Network Qml Quick QuickControls2 Quick3D Concurrent)

# Everything but main.cpp, shared by the app and the tests, so each source
# compiles once and a new file in src/ needs no line here.
file(GLOB checkmate_sources CONFIGURE_DEPENDS src/*.cpp src/*.h)
list(REMOVE_ITEM checkmate_sources ${CMAKE_SOURCE_DIR}/src/main.cpp)
add_library(checkmate_core STATIC ${checkmate_sources})
target_include_directories(checkmate_core PUBLIC src)
target_link_libraries(checkmate_core PUBLIC
  Qt6::Core Qt6::Gui Qt6::Network Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::Quick3D Qt6::Concurrent)
target_compile_options(checkmate_core PUBLIC -Wall -Wextra)

# The version comes from the release, never from the code: a tag's tarball
# unpacks as checkmate-<version>, and a checkout asks git.
# Omaxian: vendored in another repository, whose tags git describe would give,
# so the upstream release comes from .omaxian-upstream-version.
get_filename_component(source_dir_name "${CMAKE_CURRENT_SOURCE_DIR}" NAME)
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/.omaxian-upstream-version")
  file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/.omaxian-upstream-version" CHECKMATE_VERSION LIMIT_COUNT 1)
elseif(source_dir_name MATCHES "^checkmate-([0-9][0-9.]*)$")
  set(CHECKMATE_VERSION "${CMAKE_MATCH_1}")
else()
  execute_process(COMMAND git describe --tags --always --dirty
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    OUTPUT_VARIABLE CHECKMATE_VERSION OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
  string(REGEX REPLACE "^v" "" CHECKMATE_VERSION "${CHECKMATE_VERSION}")
  if(NOT CHECKMATE_VERSION)
    set(CHECKMATE_VERSION dev)
  endif()
endif()

add_executable(checkmate src/main.cpp src/resources.qrc)
target_link_libraries(checkmate PRIVATE checkmate_core)
target_compile_definitions(checkmate PRIVATE CHECKMATE_VERSION="${CHECKMATE_VERSION}")

# The tests load the real Main.qml, so they carry the resources too.
# Omaxian: Qt Test and xvfb-run are only for tests; the app builds without them.
# Probe the Test .so first (incomplete local overlays can ship the cmake config
# without the library; find_package then fatals in Qt6TestTargets.cmake).
enable_testing()
set(_checkmate_have_qt6_test FALSE)
file(GLOB _checkmate_qt6_test_so
  /usr/lib/*/libQt6Test.so
  $ENV{HOME}/.local/opt/omaxian-qt6-*/usr/lib/*/libQt6Test.so)
foreach(_checkmate_qt6_test_candidate IN LISTS _checkmate_qt6_test_so)
  get_filename_component(_checkmate_qt6_test_real "${_checkmate_qt6_test_candidate}" REALPATH)
  if(EXISTS "${_checkmate_qt6_test_real}")
    set(_checkmate_have_qt6_test TRUE)
  endif()
endforeach()
if(_checkmate_have_qt6_test)
  find_package(Qt6 COMPONENTS Test)
endif()
find_program(XVFB_RUN xvfb-run)
if(TARGET Qt6::Test AND XVFB_RUN)
  add_executable(checkmate_tests tests/checkmate_tests.cpp src/resources.qrc)
  target_link_libraries(checkmate_tests PRIVATE checkmate_core Qt6::Test)
  add_dependencies(checkmate_tests checkmate)
  add_test(NAME checkmate_tests COMMAND ${XVFB_RUN} -a $<TARGET_FILE:checkmate_tests>)
  set_tests_properties(checkmate_tests PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=rhi;QSG_RHI_BACKEND=opengl;LIBGL_ALWAYS_SOFTWARE=1")
endif()

# --version answers without a display. A checkout without tags reports git's commit or "dev" rather than a number.
add_test(NAME checkmate_version_without_display
  COMMAND ${CMAKE_COMMAND} -E env --unset=QT_QPA_PLATFORM --unset=WAYLAND_DISPLAY --unset=DISPLAY
          $<TARGET_FILE:checkmate> --version)
set_tests_properties(checkmate_version_without_display PROPERTIES PASS_REGULAR_EXPRESSION "^Checkmate [0-9a-z]")

# `cmake --install build --prefix ~/.local` puts the app in the launcher
# before it is packaged; a package installs the same files under /usr.
include(GNUInstallDirs)
install(TARGETS checkmate RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES share/checkmate.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES share/checkmate.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
install(FILES LICENSE DESTINATION ${CMAKE_INSTALL_DATADIR}/licenses/checkmate)
