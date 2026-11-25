cmake_minimum_required(VERSION 3.21)
project(plain LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 DBus Network Test)

# Everything but main.cpp, shared by the app and the tests, so each source
# compiles once and a new file in src/ needs no line here.
file(GLOB plain_sources CONFIGURE_DEPENDS src/*.cpp src/*.h)
list(REMOVE_ITEM plain_sources ${CMAKE_SOURCE_DIR}/src/main.cpp)
add_library(plain_core STATIC ${plain_sources})
target_include_directories(plain_core PUBLIC src)
target_link_libraries(plain_core PUBLIC
  Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2 Qt6::DBus Qt6::Network)
target_compile_options(plain_core PUBLIC -Wall -Wextra)

# The version comes from the release, never from the code: a tag's tarball
# unpacks as plain-<version>, and a checkout asks git.
get_filename_component(source_dir_name "${CMAKE_CURRENT_SOURCE_DIR}" NAME)
if(source_dir_name MATCHES "^plain-([0-9][0-9.]*)$")
  set(PLAIN_VERSION "${CMAKE_MATCH_1}")
else()
  execute_process(COMMAND git describe --tags --always --dirty
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    OUTPUT_VARIABLE PLAIN_VERSION OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
  string(REGEX REPLACE "^v" "" PLAIN_VERSION "${PLAIN_VERSION}")
  if(NOT PLAIN_VERSION)
    set(PLAIN_VERSION dev)
  endif()
endif()

add_executable(plain src/main.cpp src/resources.qrc)
target_link_libraries(plain PRIVATE plain_core)
target_compile_definitions(plain PRIVATE PLAIN_VERSION="${PLAIN_VERSION}")

enable_testing()
add_executable(plain_tests tests/plain_tests.cpp)
target_link_libraries(plain_tests PRIVATE plain_core Qt6::Test)
add_test(NAME plain_tests COMMAND plain_tests)
set_tests_properties(plain_tests PROPERTIES ENVIRONMENT QT_QPA_PLATFORM=offscreen)

# --help and --version answer without a display, as on a TTY or over SSH.
add_test(NAME plain_version_without_display
  COMMAND ${CMAKE_COMMAND} -E env --unset=QT_QPA_PLATFORM --unset=WAYLAND_DISPLAY --unset=DISPLAY
          $<TARGET_FILE:plain> --version)
# A checkout without tags reports git's commit or "dev" rather than a number.
set_tests_properties(plain_version_without_display PROPERTIES PASS_REGULAR_EXPRESSION "^plain [0-9a-z]")
