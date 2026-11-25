#pragma once

// Pictures the tests make for themselves: a camera's EXIF written into a
// JPEG, and a made-up fjord to look at in the README's screenshots.

#include <QBuffer>
#include <QByteArray>
#include <QImage>
#include <QLinearGradient>
#include <QList>
#include <QPainter>
#include <QPainterPath>
#include <QRadialGradient>
#include <QtEndian>

namespace fixtures {

// A camera's EXIF, as the TIFF structure inside a JPEG's APP1 segment.
struct Tag {
    quint16 tag;
    quint16 type;
    quint32 count;
    QByteArray value;
};
inline Tag ascii(quint16 tag, const QByteArray &text) { return {tag, 2, quint32(text.size() + 1), text + '\0'}; }
inline Tag shortTag(quint16 tag, quint16 value) {
    QByteArray bytes(2, 0);
    qToLittleEndian(value, bytes.data());
    return {tag, 3, 1, bytes};
}
inline Tag longTag(quint16 tag, quint32 value) {
    QByteArray bytes(4, 0);
    qToLittleEndian(value, bytes.data());
    return {tag, 4, 1, bytes};
}
inline Tag rational(quint16 tag, quint32 numerator, quint32 denominator) {
    QByteArray bytes(8, 0);
    qToLittleEndian(numerator, bytes.data());
    qToLittleEndian(denominator, bytes.data() + 4);
    return {tag, 5, 1, bytes};
}

inline QByteArray tiff(QList<Tag> image, const QList<Tag> &photo) {
    const quint32 imageAt = 8, photoAt = imageAt + 2 + quint32(image.size() + 1) * 12 + 4;
    const quint32 dataAt = photoAt + 2 + quint32(photo.size()) * 12 + 4;
    image.append(longTag(0x8769, photoAt));
    QByteArray out("II*\0", 4), data;
    auto u16 = [&](quint16 v) { QByteArray b(2, 0); qToLittleEndian(v, b.data()); out += b; };
    auto u32 = [&](quint32 v) { QByteArray b(4, 0); qToLittleEndian(v, b.data()); out += b; };
    u32(imageAt);
    for (const QList<Tag> &ifd : {image, photo}) {
        u16(quint16(ifd.size()));
        for (const Tag &tag : ifd) {
            u16(tag.tag);
            u16(tag.type);
            u32(tag.count);
            if (tag.value.size() <= 4) {
                out += tag.value + QByteArray(4 - tag.value.size(), 0);
            } else {
                u32(dataAt + quint32(data.size()));
                data += tag.value;
            }
        }
        u32(0);
    }
    return out + data;
}

// A JPEG of the image with the camera's tags in it.
inline QByteArray jpegWithExif(const QImage &image, const QList<Tag> &camera, const QList<Tag> &photo, int quality = 90) {
    QByteArray jpeg;
    QBuffer buffer(&jpeg);
    buffer.open(QIODevice::WriteOnly);
    if (!image.save(&buffer, "JPEG", quality))
        return {};
    const QByteArray exif = QByteArray("Exif\0\0", 6) + tiff(camera, photo);
    QByteArray segment("\xFF\xE1");
    segment += char((exif.size() + 2) >> 8);
    segment += char((exif.size() + 2) & 0xFF);
    jpeg.insert(2, segment + exif);
    return jpeg;
}

// A fjord in flat colours: a sky, a sun low between two ranges of peaks,
// still water with its light on it, and a dark shore with two spruces.
// `light` runs from night (0) through dusk to day (1); `shift` moves the
// peaks along, so a set of them reads as different shots of one place.
struct Palette {
    QColor skyTop, skyLow, glow, far, near, water, shore;
};

inline Palette palette(int kind) {
    switch (kind % 6) {
    case 0: return {"#0e1422", "#5a4a3c", "#e8a860", "#2f3748", "#1d2232", "#3c3a3c", "#06090f"};  // dusk
    case 1: return {"#3d6fa8", "#cfe0ee", "#fff6d8", "#7a93ad", "#4f6884", "#6f93b4", "#1e2a36"};  // noon
    case 2: return {"#2a2140", "#e59a7a", "#ffd6a0", "#5b5070", "#3a3352", "#7a6377", "#130f1f"};  // dawn
    case 3: return {"#05070d", "#141b2e", "#c8d4f0", "#1a2133", "#10141f", "#161c2a", "#020305"};  // night
    case 4: return {"#8a97a3", "#d6dbdf", "#f4f2ea", "#a6b0b9", "#8c98a4", "#b4bdc5", "#3c444c"};  // fog
    default: return {"#1f3b54", "#9fc3d6", "#ffffff", "#e8eef3", "#b9c9d6", "#6e8fa8", "#2c3a46"};  // snow
    }
}

inline QImage fjord(QSize size, int kind, double shift = 0) {
    const Palette p = palette(kind);
    QImage image(size, QImage::Format_RGB32);
    QPainter painter(&image);
    painter.setRenderHint(QPainter::Antialiasing);
    const double w = size.width(), h = size.height(), horizon = h * 0.62;
    auto x = [&](double f) { return w * f; };
    auto y = [&](double f) { return h * f; };

    QLinearGradient sky(0, 0, 0, horizon);
    sky.setColorAt(0, p.skyTop);
    sky.setColorAt(1, p.skyLow);
    painter.fillRect(QRectF(0, 0, w, horizon), sky);
    const QPointF sun(x(0.46 + shift * 0.1), horizon - y(0.02));
    QRadialGradient glow(sun, h * 0.35);
    QColor bright = p.glow;
    bright.setAlpha(150);
    glow.setColorAt(0, bright);
    glow.setColorAt(1, Qt::transparent);
    painter.fillRect(QRectF(0, 0, w, horizon), glow);
    painter.setPen(Qt::NoPen);
    painter.setBrush(p.glow);
    painter.drawEllipse(sun, h * 0.045, h * 0.045);

    auto range = [&](const QList<QPointF> &peaks, const QColor &colour) {
        QPainterPath path(QPointF(0, horizon));
        for (const QPointF &peak : peaks)
            path.lineTo(x(peak.x() + shift * 0.05), y(peak.y()));
        path.lineTo(w, horizon);
        path.closeSubpath();
        painter.setBrush(colour);
        painter.drawPath(path);
    };
    range({{0, 0.38}, {0.09, 0.31}, {0.17, 0.39}, {0.25, 0.27}, {0.36, 0.40}, {0.6, 0.43}, {0.78, 0.38},
           {0.88, 0.46}, {1, 0.35}},
          p.far);
    range({{0, 0.48}, {0.11, 0.41}, {0.21, 0.50}, {0.3, 0.45}, {0.41, 0.56}, {0.62, 0.58}, {0.7, 0.53},
           {0.79, 0.50}, {0.87, 0.55}, {0.95, 0.48}, {1, 0.50}},
          p.near);

    QLinearGradient water(0, horizon, 0, h);
    QColor lit = p.water.lighter(115);
    water.setColorAt(0, lit);
    water.setColorAt(1, p.water.darker(160));
    painter.fillRect(QRectF(0, horizon, w, h - horizon), water);
    QColor shine = p.glow;
    shine.setAlpha(70);
    painter.setBrush(shine);
    for (int i = 0; i < 4; ++i) {
        const double band = horizon + y(0.03 + i * 0.045), half = w * (0.07 - i * 0.014);
        painter.drawRect(QRectF(sun.x() - half, band, half * 2, y(0.012)));
    }

    QPainterPath shore(QPointF(0, y(0.82)));
    shore.cubicTo(x(0.12), y(0.76), x(0.24), y(0.79), x(0.33), y(0.86));
    shore.cubicTo(x(0.4), y(0.92), x(0.44), y(1.0), x(0.45), h);
    shore.lineTo(0, h);
    shore.closeSubpath();
    QPainterPath right(QPointF(w, y(0.85)));
    right.cubicTo(x(0.9), y(0.87), x(0.83), y(0.92), x(0.79), h);
    right.lineTo(w, h);
    right.closeSubpath();
    painter.setBrush(p.shore);
    painter.drawPath(shore);
    painter.drawPath(right);
    for (const auto &[at, tall] : QList<std::pair<double, double>>{{0.085, 0.13}, {0.115, 0.09}}) {
        QPolygonF tree({QPointF(x(at), y(0.79) - y(tall)), QPointF(x(at) - y(0.012), y(0.80)),
                        QPointF(x(at) + y(0.012), y(0.80))});
        painter.drawPolygon(tree);
    }
    return image;
}

}  // namespace fixtures
