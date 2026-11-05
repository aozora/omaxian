QT += core gui qml quick quickcontrols2 multimedia dbus concurrent
CONFIG += c++17 release
# Multimedia (and any other library staged beside the system Qt) lives here
# when apt's Qt packages would downgrade the desktop.
unix: QMAKE_RPATHDIR += $$(HOME)/.local/lib
TARGET = monologue
TEMPLATE = app
include(src/common.pri)
SOURCES += src/main.cpp
RESOURCES += src/resources.qrc
