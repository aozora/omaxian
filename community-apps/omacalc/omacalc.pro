# Omaxian qmake build (fallback). Upstream's primary build is CMake.
QT += core gui qml quick quickcontrols2 dbus

CONFIG += c++17 release
TARGET = omacalc
TEMPLATE = app

HEADERS += \
    src/backend.h \
    src/systemtheme.h \
    src/translator.h

SOURCES += \
    src/backend.cpp \
    src/main.cpp \
    src/systemtheme.cpp \
    src/translator.cpp

RESOURCES += src/resources.qrc
