#pragma once

#include <QList>
#include <QString>
#include <QStringList>
#include <atomic>

// Subtitle files beside a video, turned into timed text through ffmpeg, since
// Qt Multimedia plays only the subtitle tracks inside a file.
namespace subtitles {

struct Cue {
    qint64 start = 0;  // milliseconds
    qint64 end = 0;
    QString text;      // plain text, lines separated by \n
    qint64 reach = 0;  // the latest end of this cue and every one before it
};

struct Sidecar {
    QString path;
    QString language;  // from a name like movie.en.srt or movie.eng.srt, if any
    QString label;     // a short name for the display: the language or the file name
};

// Files named after the video, with a subtitle extension: movie.srt,
// movie.en.srt, movie.English.ass. Sorted by name.
QList<Sidecar> find(const QString &videoPath);

// Converts a subtitle stream ffmpeg reads to WebVTT and parses it: the first
// one in a subtitle file, or the nth subtitle stream inside a video. Runs
// a process synchronously at low priority, so call it off the GUI thread.
// Empty on failure, with the reason in *error.
// It stops early once *cancelled is set.
QList<Cue> load(const QString &path, int stream = 0, QString *error = nullptr,
                const std::atomic_bool *cancelled = nullptr);

// Parses WebVTT text; separate so tests can feed it. Tags (<i>, <c.yellow>)
// and ASS overrides are dropped, since the window draws all subtitles in one
// style.
QList<Cue> parseWebVtt(const QString &text);

// The text showing at a time, or empty. Cues are sorted by start, and may
// overlap; overlapping ones are joined.
QString at(const QList<Cue> &cues, qint64 ms);

}  // namespace subtitles
