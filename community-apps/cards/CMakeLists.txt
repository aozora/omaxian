cmake_minimum_required(VERSION 3.21)
project(cards LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Qt6 REQUIRED COMPONENTS Core Gui Network Qml Quick QuickControls2)

# Everything but main.cpp, shared by the app and the tests, so each source
# compiles once and a new file in src/ needs no line here.
file(GLOB cards_sources CONFIGURE_DEPENDS src/*.cpp src/*.h)
list(REMOVE_ITEM cards_sources ${CMAKE_SOURCE_DIR}/src/main.cpp)
add_library(cards_core STATIC ${cards_sources})
target_include_directories(cards_core PUBLIC src)
target_link_libraries(cards_core PUBLIC
  Qt6::Core Qt6::Gui Qt6::Network Qt6::Qml Qt6::Quick Qt6::QuickControls2)
target_compile_options(cards_core PUBLIC -Wall -Wextra)

add_executable(cards src/main.cpp src/resources.qrc)
target_link_libraries(cards PRIVATE cards_core)

# The tests load the real Main.qml, so they carry the resources too, and they
# run the built binary for its headless commands.
# Omaxian: Qt Test is only for the tests. Probe the .so first — an incomplete
# local Qt overlay can ship Qt6TestConfig.cmake without the library, and
# find_package then fatals inside Qt6TestTargets.cmake.
enable_testing()
set(_cards_have_qt6_test FALSE)
file(GLOB _cards_qt6_test_so
  /usr/lib/*/libQt6Test.so
  $ENV{HOME}/.local/opt/omaxian-qt6-*/usr/lib/*/libQt6Test.so)
foreach(_cards_qt6_test_candidate IN LISTS _cards_qt6_test_so)
  get_filename_component(_cards_qt6_test_real "${_cards_qt6_test_candidate}" REALPATH)
  if(EXISTS "${_cards_qt6_test_real}")
    set(_cards_have_qt6_test TRUE)
  endif()
endforeach()
if(_cards_have_qt6_test)
  find_package(Qt6 COMPONENTS Test)
endif()
if(TARGET Qt6::Test)
  add_executable(cards_tests tests/cards_tests.cpp src/resources.qrc)
  target_link_libraries(cards_tests PRIVATE cards_core Qt6::Test)
  add_dependencies(cards_tests cards)
  add_test(NAME cards_tests COMMAND cards_tests)
  set_tests_properties(cards_tests PROPERTIES ENVIRONMENT QT_QPA_PLATFORM=offscreen)
endif()

# `cmake --install build --prefix ~/.local` puts the app in the launcher
# before it is packaged; a package installs the same files under /usr.
include(GNUInstallDirs)
install(TARGETS cards RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES share/cards.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES share/cards.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
install(FILES LICENSE DESTINATION ${CMAKE_INSTALL_DATADIR}/licenses/cards)
