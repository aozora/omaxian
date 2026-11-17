#pragma once

#include <QJsonObject>
#include <QList>
#include <QString>
#include <atomic>

// What ffprobe says about a file, as plain values: what Qt Multimedia doesn't
// expose (chapters, subtitle codecs) and what the info card and the command
// line show.
namespace probe {

struct Stream {
    int index = -1;       // ffprobe's index across all streams
    QString type;         // "video", "audio", "subtitle"
    QString codec;        // codec_name, e.g. "h264", "subrip", "hdmv_pgs_subtitle"
    QString language;     // ISO 639-2 from the tags, e.g. "eng"
    QString title;
    int width = 0;
    int height = 0;
    int rotation = 0;     // degrees, from the display matrix a phone writes
    double frameRate = 0;
    int channels = 0;
    QString channelLayout;
    bool isDefault = false;
    bool attachedPicture = false;  // cover art, which ffprobe lists as video

    // Whether Qt's subtitle path, which handles text only, can show it.
    bool textSubtitle() const;
};

struct Chapter {
    double start = 0;  // seconds
    double end = 0;
    QString title;
};

struct Info {
    QString error;  // empty when the probe worked
    bool missingTool = false;  // ffprobe isn't installed
    QString path;
    QString format;      // format_long_name
    QString title;       // the container's title tag
    QString artist;
    double duration = 0;  // seconds; 0 when unknown (a live stream)
    qint64 size = 0;
    qint64 bitRate = 0;
    QList<Stream> streams;
    QList<Chapter> chapters;

    bool ok() const { return error.isEmpty(); }
    QList<Stream> ofType(const QString &type) const;
    // The first real video stream, skipping cover art.
    const Stream *video() const;
    QJsonObject toJson() const;
};

// Runs ffprobe synchronously, so call it off the GUI thread. A timeout keeps a
// file on a stalled network mount from holding a worker forever.
// It stops early, with an error, once *cancelled is set.
Info run(const QString &path, int timeoutMs = 15000, const std::atomic_bool *cancelled = nullptr);
// Parses ffprobe's -print_format json output; separate so tests can feed it.
Info parse(const QByteArray &json, const QString &path);

// "English", "Dansk", "Deutsch", from an ISO 639-2 or 639-1 code, each in
// its own words; empty for "und" or unknown codes.
QString languageName(const QString &code);
// The ISO 639-1 code for a 639-2 one ("eng" -> "en"), or the code itself.
QString shortLanguage(const QString &code);

QString toolPath(const QString &name);

}  // namespace probe
