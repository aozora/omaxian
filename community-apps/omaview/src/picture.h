#pragma once

#include <QImage>
#include <QJsonObject>
#include <QSize>
#include <QString>

#include "exif.h"

// What a picture is, read from its header without decoding it, for the info
// card, the window's size and the command line. The window decodes the
// picture itself, through Qt Quick's Image, off the GUI thread.
namespace picture {

struct Info {
    QString error;      // empty when the picture can be read
    QString format;     // as people know it: "JPEG", "WebP", "HEIF"
    QSize size;         // as shown, the EXIF orientation applied
    qint64 bytes = 0;
    int frames = 1;
    bool animated = false;
    bool transparent = false;
    bool vector = false;
    exif::Tags exif;

    bool ok() const { return error.isEmpty(); }
    QJsonObject toJson() const;
};

// Reads only the header, but call it off the GUI thread all the same: the
// file may be on a slow disk.
Info read(const QString &path);

// The whole picture as it is shown, turned upright by its EXIF orientation
// and then by a further quarter turns clockwise (90, 180, 270).
QImage load(const QString &path, int rotation = 0, QString *error = nullptr);

}  // namespace picture
