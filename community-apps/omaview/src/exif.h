#pragma once

#include <QByteArray>
#include <QDateTime>
#include <QString>

// The few EXIF tags someone asks about a photo: when it was taken, with what,
// and how. Qt reads only the orientation, so this reads the rest from the
// TIFF structure a camera writes into JPEG, PNG, WebP and TIFF files.
namespace exif {

struct Tags {
    QDateTime taken;        // DateTimeOriginal, in the camera's own clock
    QString make;
    QString model;
    QString lens;
    double exposure = 0;    // seconds
    double aperture = 0;    // the f-number
    double focalLength = 0; // millimetres
    int focal35 = 0;        // the 35 mm equivalent
    int iso = 0;

    bool empty() const;
    // "Canon EOS R5", without the make twice when the model repeats it.
    QString camera() const;
};

// Reads a file's tags; an empty Tags when it has none or isn't a format
// that carries them.
Tags read(const QString &path);
// The TIFF structure itself, from its "II" or "MM" header on.
Tags parse(const QByteArray &tiff);

}  // namespace exif
