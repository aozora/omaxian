QT += core gui qml quick quickcontrols2 testlib dbus
CONFIG += c++17 testcase link_pkgconfig
PKGCONFIG += poppler-qt6 libqpdf
TARGET = signed_tests
TEMPLATE = app

INCLUDEPATH += ../src

HEADERS += \
    ../src/backend.h \
    ../src/filepicker.h \
    ../src/items.h \
    ../src/pageprovider.h \
    ../src/signatures.h \
    ../src/signer.h \
    ../src/stamper.h \
    ../src/textlayout.h \
    ../src/theme.h

SOURCES += \
    signed_tests.cpp \
    ../src/backend.cpp \
    ../src/items.cpp \
    ../src/pageprovider.cpp \
    ../src/signatures.cpp \
    ../src/signer.cpp \
    ../src/stamper.cpp \
    ../src/textlayout.cpp \
    ../src/theme.cpp
