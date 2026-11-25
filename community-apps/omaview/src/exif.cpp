#include "exif.h"

#include <QFile>
#include <QHash>
#include <limits>

namespace exif {

namespace {

// Every read is checked against the end, since the offsets come from the file.
class Reader {
public:
    explicit Reader(const QByteArray &data) : m_data(data) {
        m_little = data.startsWith("II");
    }
    bool valid() const {
        return m_data.size() >= 8 && (m_data.startsWith("II") || m_data.startsWith("MM")) && u16(2) == 42;
    }
    quint32 size() const { return quint32(m_data.size()); }
    bool fits(quint32 offset, quint32 length) const {
        return offset <= size() && length <= size() - offset;
    }
    quint16 u16(quint32 offset) const {
        if (!fits(offset, 2))
            return 0;
        const auto *p = reinterpret_cast<const uchar *>(m_data.constData() + offset);
        return m_little ? quint16(p[0] | p[1] << 8) : quint16(p[0] << 8 | p[1]);
    }
    quint32 u32(quint32 offset) const {
        if (!fits(offset, 4))
            return 0;
        const auto *p = reinterpret_cast<const uchar *>(m_data.constData() + offset);
        return m_little ? quint32(p[0]) | quint32(p[1]) << 8 | quint32(p[2]) << 16 | quint32(p[3]) << 24
                        : quint32(p[0]) << 24 | quint32(p[1]) << 16 | quint32(p[2]) << 8 | quint32(p[3]);
    }
    QByteArray bytes(quint32 offset, quint32 length) const {
        return fits(offset, length) ? m_data.mid(offset, length) : QByteArray();
    }

private:
    const QByteArray &m_data;
    bool m_little = true;
};

struct Entry {
    quint16 type = 0;
    quint32 count = 0;
    quint32 value = 0;  // where the value is: inline in the entry, or the offset it holds
};

int typeSize(quint16 type) {
    switch (type) {
    case 1: case 2: case 6: case 7: return 1;  // BYTE, ASCII, SBYTE, UNDEFINED
    case 3: case 8: return 2;                  // SHORT, SSHORT
    case 4: case 9: case 11: case 13: return 4;  // LONG, SLONG, FLOAT, IFD
    case 5: case 10: case 12: return 8;        // RATIONAL, SRATIONAL, DOUBLE
    }
    return 0;
}

// One IFD's entries by tag; the next IFD is not followed, since the tags
// wanted are all in the first image's and its EXIF one.
QHash<quint16, Entry> entries(const Reader &reader, quint32 offset) {
    QHash<quint16, Entry> found;
    if (!reader.fits(offset, 2))
        return found;
    const quint16 count = reader.u16(offset);
    if (!reader.fits(offset + 2, quint32(count) * 12))
        return found;
    for (quint16 i = 0; i < count; ++i) {
        const quint32 at = offset + 2 + quint32(i) * 12;
        Entry entry;
        entry.type = reader.u16(at + 2);
        entry.count = reader.u32(at + 4);
        const quint64 length = quint64(typeSize(entry.type)) * entry.count;
        entry.value = length <= 4 ? at + 8 : reader.u32(at + 8);
        if (length > 0 && length < 1 << 20 && reader.fits(entry.value, quint32(length)))
            found.insert(reader.u16(at), entry);
    }
    return found;
}

QString text(const Reader &reader, const QHash<quint16, Entry> &ifd, quint16 tag) {
    const Entry entry = ifd.value(tag);
    if (entry.type != 2)
        return {};
    QByteArray bytes = reader.bytes(entry.value, entry.count);
    const int end = bytes.indexOf('\0');
    if (end >= 0)
        bytes.truncate(end);
    return QString::fromUtf8(bytes).trimmed();
}

double number(const Reader &reader, const QHash<quint16, Entry> &ifd, quint16 tag) {
    if (!ifd.contains(tag))
        return 0;
    const Entry entry = ifd.value(tag);
    switch (entry.type) {
    case 3: return reader.u16(entry.value);
    case 4: return reader.u32(entry.value);
    case 5: {
        const quint32 denominator = reader.u32(entry.value + 4);
        return denominator ? double(reader.u32(entry.value)) / denominator : 0;
    }
    case 10: {
        const auto denominator = qint32(reader.u32(entry.value + 4));
        return denominator ? double(qint32(reader.u32(entry.value))) / denominator : 0;
    }
    }
    return 0;
}

// The TIFF structure in a JPEG: the APP1 segment that starts "Exif\0\0",
// found by walking marker headers with seeks rather than reading a fixed
// prefix or any pixel data.
QByteArray fromJpeg(QFile &file) {
    qint64 at = 2;
    const qint64 end = file.size();
    while (at + 2 <= end && file.seek(at)) {
        char byte = 0;
        if (file.read(&byte, 1) != 1 || uchar(byte) != 0xFF)
            break;
        // JPEG allows one or more 0xFF fill bytes before a marker code.
        uchar marker = 0xFF;
        while (marker == 0xFF && file.read(&byte, 1) == 1)
            marker = uchar(byte);
        if (marker == 0xFF || marker == 0xD9 || marker == 0xDA)  // EOF, the end, or the image data
            break;
        // Standalone markers (TEM, RST0..7, SOI) carry no length field.
        if (marker == 0x00 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
            at = file.pos();
            continue;
        }
        const QByteArray lenBytes = file.read(2);
        if (lenBytes.size() < 2)
            break;
        const int length = uchar(lenBytes[0]) << 8 | uchar(lenBytes[1]);
        if (length < 2)
            break;
        const qint64 payloadStart = file.pos();
        if (marker == 0xE1 && length >= 8 && file.read(6) == QByteArray("Exif\0\0", 6))
            return file.read(length - 8);
        at = payloadStart + (length - 2);
    }
    return {};
}

// The one chunk of a PNG (eXIf, which holds the TIFF structure as it is) or
// a WebP (EXIF, in its RIFF container, sometimes with JPEG's prefix), found
// by walking the chunk headers with seeks rather than reading the pixels.
QByteArray chunk(QFile &file, bool webp) {
    qint64 at = webp ? 12 : 8;
    while (at + 8 <= file.size() && file.seek(at)) {
        const QByteArray header = file.read(8);
        if (header.size() < 8)
            break;
        const auto *p = reinterpret_cast<const uchar *>(header.constData());
        const quint32 length = webp ? quint32(p[4]) | quint32(p[5]) << 8 | quint32(p[6]) << 16 | quint32(p[7]) << 24
                                    : quint32(p[0]) << 24 | quint32(p[1]) << 16 | quint32(p[2]) << 8 | p[3];
        const QByteArray type = webp ? header.left(4) : header.mid(4, 4);
        if (type == (webp ? "EXIF" : "eXIf")) {
            QByteArray tiff = file.read(std::min<qint64>(length, 1024 * 1024));
            if (tiff.startsWith(QByteArray("Exif\0\0", 6)))
                tiff.remove(0, 6);
            return tiff;
        }
        if (!webp && type == "IEND")
            break;
        at += webp ? 8 + qint64(length) + (length & 1) : 12 + qint64(length);
    }
    return {};
}

}  // namespace

bool Tags::empty() const {
    return !taken.isValid() && make.isEmpty() && model.isEmpty() && lens.isEmpty() && exposure <= 0
           && aperture <= 0 && focalLength <= 0 && focal35 <= 0 && iso <= 0;
}

QString Tags::camera() const {
    if (model.isEmpty())
        return make;
    if (make.isEmpty() || model.startsWith(make.section(' ', 0, 0), Qt::CaseInsensitive))
        return model;
    // "NIKON CORPORATION" says only "NIKON" in front of its model.
    return make.section(' ', 0, 0) + ' ' + model;
}

Tags parse(const QByteArray &tiff) {
    Tags tags;
    const Reader reader(tiff);
    if (!reader.valid())
        return tags;
    const QHash<quint16, Entry> image = entries(reader, reader.u32(4));
    tags.make = text(reader, image, 0x010F);
    tags.model = text(reader, image, 0x0110);
    QHash<quint16, Entry> photo;
    if (const Entry exifIfd = image.value(0x8769); exifIfd.type == 4 || exifIfd.type == 13)
        photo = entries(reader, reader.u32(exifIfd.value));
    auto whole = [](double v) {
        return v > 0 && v <= std::numeric_limits<int>::max() ? int(v) : 0;
    };
    tags.exposure = number(reader, photo, 0x829A);
    tags.aperture = number(reader, photo, 0x829D);
    tags.iso = whole(number(reader, photo, 0x8827));
    tags.focalLength = number(reader, photo, 0x920A);
    tags.focal35 = whole(number(reader, photo, 0xA405));
    tags.lens = text(reader, photo, 0xA434);
    QString when = text(reader, photo, 0x9003);
    if (when.isEmpty())
        when = text(reader, image, 0x0132);
    tags.taken = QDateTime::fromString(when, "yyyy:MM:dd HH:mm:ss");
    return tags;
}

Tags read(const QString &path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    // Only what holds the tags is read: a JPEG's start, a PNG's or WebP's one
    // chunk, a TIFF's first megabyte. Read, not mapped: a file another program
    // cuts short as it saves would crash a mapping with SIGBUS.
    const QByteArray head = file.peek(16);
    if (head.startsWith("\xFF\xD8"))
        return parse(fromJpeg(file));
    if (head.startsWith("\x89PNG\r\n\x1a\n"))
        return parse(chunk(file, false));
    if (head.startsWith("RIFF") && head.mid(8, 4) == "WEBP")
        return parse(chunk(file, true));
    if (head.startsWith("II*") || head.startsWith(QByteArray("MM\0*", 4)))
        return parse(file.read(1024 * 1024));
    return {};
}

}  // namespace exif
