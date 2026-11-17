#include "picture.h"

#include <QFileInfo>
#include <QHash>
#include <QImageReader>
#include <QPixelFormat>
#include <QTransform>

namespace picture {

namespace {

QString formatName(const QByteArray &format) {
    static const QHash<QByteArray, QString> names{
        {"jpeg", "JPEG"}, {"jpg", "JPEG"}, {"png", "PNG"}, {"webp", "WebP"}, {"gif", "GIF"}, {"bmp", "BMP"},
        {"tiff", "TIFF"}, {"tif", "TIFF"}, {"svg", "SVG"}, {"svgz", "SVG"}, {"heic", "HEIF"}, {"heif", "HEIF"},
        {"avif", "AVIF"}, {"jxl", "JPEG XL"}, {"ico", "ICO"}, {"icns", "ICNS"}, {"tga", "TGA"},
    };
    return names.value(format.toLower(), QString::fromLatin1(format).toUpper());
}

}  // namespace

QJsonObject Info::toJson() const {
    QJsonObject object{{"type", "picture"},  {"format", format},           {"width", size.width()},
                       {"height", size.height()}, {"size", bytes},        {"frames", frames},
                       {"animated", animated},   {"transparent", transparent}};
    if (exif.taken.isValid())
        object.insert("taken", exif.taken.toString(Qt::ISODate));
    if (!exif.camera().isEmpty())
        object.insert("camera", exif.camera());
    if (!exif.lens.isEmpty())
        object.insert("lens", exif.lens);
    if (exif.exposure > 0)
        object.insert("exposure", exif.exposure);
    if (exif.aperture > 0)
        object.insert("aperture", exif.aperture);
    if (exif.iso > 0)
        object.insert("iso", exif.iso);
    if (exif.focalLength > 0)
        object.insert("focalLength", exif.focalLength);
    return object;
}

Info read(const QString &path) {
    Info info;
    const QFileInfo file(path);
    info.bytes = file.size();
    QImageReader reader(path);
    reader.setAutoTransform(true);
    if (!reader.canRead()) {
        // The window says it in its own, translated words; this is for the
        // command line, which stays English.
        info.error = QStringLiteral("Not a picture format Omaview can read: ") + file.fileName();
        return info;
    }
    info.format = formatName(reader.format());
    info.vector = reader.format().startsWith("svg");
    QSize size = reader.size();
    if (reader.transformation() & QImageIOHandler::TransformationRotate90)
        size.transpose();
    info.size = size;
    info.frames = std::max(1, reader.imageCount());
    info.animated = reader.supportsAnimation() && info.frames > 1;
    const QImage::Format pixels = reader.imageFormat();
    info.transparent = info.vector
                       || (pixels != QImage::Format_Invalid
                           && QImage::toPixelFormat(pixels).alphaUsage() == QPixelFormat::UsesAlpha);
    info.exif = exif::read(path);
    return info;
}

QImage load(const QString &path, int rotation, QString *error) {
    QImageReader reader(path);
    reader.setAutoTransform(true);
    QImage image = reader.read();
    if (image.isNull()) {
        if (error)
            *error = reader.errorString();
        return image;
    }
    if (rotation % 360 != 0)
        image = image.transformed(QTransform().rotate(rotation));
    return image;
}

}  // namespace picture
