QT += core gui qml quick quickcontrols2 dbus

# operator== = default in items.h is C++20. qmake's c++17 flag hides that
# from GCC 14, which does not accept it as an extension.
CONFIG += c++20 release link_pkgconfig
unix: QMAKE_RPATHDIR += $$(HOME)/.local/lib
PKGCONFIG += poppler-qt6 libqpdf
TARGET = signed
TEMPLATE = app

HEADERS += \
    src/cli.h \
    src/backend.h \
    src/filepicker.h \
    src/items.h \
    src/pageprovider.h \
    src/portalfilepicker.h \
    src/signatures.h \
    src/signer.h \
    src/stamper.h \
    src/textitem.h \
    src/textlayout.h \
    src/theme.h

SOURCES += \
    src/cli.cpp \
    src/main.cpp \
    src/backend.cpp \
    src/items.cpp \
    src/pageprovider.cpp \
    src/portalfilepicker.cpp \
    src/signatures.cpp \
    src/signer.cpp \
    src/stamper.cpp \
    src/textitem.cpp \
    src/textlayout.cpp \
    src/theme.cpp

RESOURCES += src/resources.qrc
