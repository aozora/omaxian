# Omaxian qmake build (fallback). Upstream's primary build is CMake.
QT += core gui concurrent widgets printsupport qml quick quickcontrols2 quickdialogs2 dbus

CONFIG += c++17 release
TARGET = omawrite
TEMPLATE = app

HEADERS += \
    src/backend.h \
    src/cli.h \
    src/markdownhighlighter.h \
    src/systemtheme.h \
    src/translator.h

SOURCES += \
    src/backend.cpp \
    src/cli.cpp \
    src/main.cpp \
    src/markdownhighlighter.cpp \
    src/systemtheme.cpp \
    src/translator.cpp

RESOURCES += src/resources.qrc
