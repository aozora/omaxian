# Omaxian qmake build (fallback). Upstream's primary build is CMake.
QT += core gui qml quick quickcontrols2 dbus concurrent

CONFIG += c++17 release link_pkgconfig
PKGCONFIG += gio-2.0 gio-unix-2.0 zlib
TARGET = folio
TEMPLATE = app

HEADERS += \
    src/backend.h \
    src/chooser.h \
    src/disks.h \
    src/filemanager1.h \
    src/fileops.h \
    src/foldermodel.h \
    src/mounter.h \
    src/places.h \
    src/plugins.h \
    src/previewer.h \
    src/theme.h \
    src/thumbnails.h \
    src/translator.h \
    src/windows.h

SOURCES += \
    src/backend.cpp \
    src/chooser.cpp \
    src/disks.cpp \
    src/filemanager1.cpp \
    src/fileops.cpp \
    src/foldermodel.cpp \
    src/main.cpp \
    src/mounter.cpp \
    src/places.cpp \
    src/plugins.cpp \
    src/previewer.cpp \
    src/theme.cpp \
    src/thumbnails.cpp \
    src/translator.cpp \
    src/windows.cpp

RESOURCES += src/resources.qrc
