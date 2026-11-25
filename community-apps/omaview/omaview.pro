# Omaxian qmake build (fallback). Upstream's primary build is CMake.
QT += core gui network qml quick quickcontrols2 multimedia dbus concurrent

CONFIG += c++17 release
TARGET = omaview
TEMPLATE = app

HEADERS += \
    src/backend.h \
    src/cli.h \
    src/exif.h \
    src/filepicker.h \
    src/frames.h \
    src/hyprland.h \
    src/inhibit.h \
    src/mpris.h \
    src/picture.h \
    src/playlist.h \
    src/portalfilepicker.h \
    src/positions.h \
    src/probe.h \
    src/subtitles.h \
    src/texts.h \
    src/theme.h \
    src/thumbnails.h \
    src/translator.h

SOURCES += \
    src/backend.cpp \
    src/cli.cpp \
    src/exif.cpp \
    src/frames.cpp \
    src/hyprland.cpp \
    src/inhibit.cpp \
    src/main.cpp \
    src/mpris.cpp \
    src/picture.cpp \
    src/playlist.cpp \
    src/portalfilepicker.cpp \
    src/positions.cpp \
    src/probe.cpp \
    src/subtitles.cpp \
    src/theme.cpp \
    src/thumbnails.cpp \
    src/translator.cpp

RESOURCES += src/resources.qrc
