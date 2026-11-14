# Omaxian qmake build (fallback). Upstream's primary build is CMake
# (CMakeLists.txt / bin/build). Use this when CMAKE_PREFIX_PATH points at a
# qmake-oriented ~/.local/opt/omaxian-qt6-<mm>/ tree that lacks qtpaths.
QT += core gui qml quick quickcontrols2 dbus

CONFIG += c++17 release
TARGET = plain
TEMPLATE = app

HEADERS += \
    src/arguments.h \
    src/document.h \
    src/editing.h \
    src/highlighter.h \
    src/portalfilepicker.h \
    src/theme.h \
    src/translator.h

SOURCES += \
    src/arguments.cpp \
    src/document.cpp \
    src/editing.cpp \
    src/highlighter.cpp \
    src/main.cpp \
    src/portalfilepicker.cpp \
    src/theme.cpp \
    src/translator.cpp

RESOURCES += src/resources.qrc
