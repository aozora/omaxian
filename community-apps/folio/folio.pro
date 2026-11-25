# Omaxian qmake build (fallback). Upstream's primary build is CMake.
QT += core gui network qml quick quickcontrols2 dbus concurrent

CONFIG += c++17 release link_pkgconfig
PKGCONFIG += gio-2.0 gio-unix-2.0 fontconfig zlib
# Same default as CMake without a prefix. install.sh puts the plugins under
# ~/.local/share/folio/plugins, which Folio reads as well.
DEFINES += FOLIO_QMAKE
DEFINES += FOLIO_PACKAGED_PLUGINS=\\\"/usr/share/folio/plugins\\\"
TARGET = folio
TEMPLATE = app

HEADERS += \
    src/backend.h \
    src/chooser.h \
    src/disks.h \
    src/dragpicture.h \
    src/filemanager1.h \
    src/fileops.h \
    src/foldermodel.h \
    src/foreignparent.h \
    src/kineticscroll.h \
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
    src/dragpicture.cpp \
    src/filemanager1.cpp \
    src/fileops.cpp \
    src/foldermodel.cpp \
    src/foreignparent.cpp \
    src/kineticscroll.cpp \
    src/main.cpp \
    src/mounter.cpp \
    src/places.cpp \
    src/plugins.cpp \
    src/previewer.cpp \
    src/theme.cpp \
    src/thumbnails.cpp \
    src/translator.cpp \
    src/windows.cpp

# Upstream compiles the QML into the FolioUI module (CMake). qmake loads it
# from a plain resource at the same qrc:/FolioUI path; keep src/qml.qrc in step
# with src/*.qml and src/*.js.
RESOURCES += src/resources.qrc src/qml.qrc
