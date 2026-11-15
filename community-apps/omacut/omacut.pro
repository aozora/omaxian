# Omaxian qmake build (fallback). Upstream's primary build is CMake.
QT += core gui qml quick quickcontrols2 multimedia dbus

CONFIG += c++17 release
TARGET = omacut
TEMPLATE = app

HEADERS += \
    src/backend.h \
    src/edit.h \
    src/ffmpeg.h \
    src/filepicker.h \
    src/portalfilepicker.h \
    src/theme.h \
    src/thumbprovider.h \
    src/timeline.h \
    src/translator.h

SOURCES += \
    src/backend.cpp \
    src/edit.cpp \
    src/ffmpeg.cpp \
    src/main.cpp \
    src/portalfilepicker.cpp \
    src/theme.cpp \
    src/thumbprovider.cpp \
    src/timeline.cpp \
    src/translator.cpp

RESOURCES += src/resources.qrc
