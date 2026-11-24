#include "subtitles.h"

#include <QCollator>
#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QProcess>
#include <QRegularExpression>
#include <algorithm>
#include <unistd.h>

#include "probe.h"
#include "texts.h"

namespace subtitles {

namespace {

const QStringList &extensions() {
    static const QStringList list{"srt", "vtt", "ass", "ssa", "sub", "smi", "sami"};
    return list;
}

qint64 timestamp(const QString &text) {
    // hh:mm:ss.mmm or mm:ss.mmm
    const QStringList parts = text.trimmed().split(':');
    if (parts.size() < 2 || parts.size() > 3)
        return -1;
    qint64 hours = 0;
    int i = 0;
    if (parts.size() == 3)
        hours = parts.at(i++).toLongLong();
    const qint64 minutes = parts.at(i++).toLongLong();
    const double seconds = QString(parts.at(i)).replace(',', '.').toDouble();
    return hours * 3600000 + minutes * 60000 + qRound64(seconds * 1000);
}

}  // namespace

QList<Sidecar> find(const QString &videoPath) {
    const QFileInfo video(videoPath);
    const QString base = video.completeBaseName();
    QList<Sidecar> found;
    const QFileInfoList entries = video.dir().entryInfoList(QDir::Files | QDir::Readable);
    for (const QFileInfo &entry : entries) {
        if (!extensions().contains(entry.suffix().toLower()))
            continue;
        const QString name = entry.completeBaseName();
        if (name.compare(base, Qt::CaseInsensitive) != 0 && !name.startsWith(base + '.', Qt::CaseInsensitive))
            continue;
        Sidecar sidecar;
        sidecar.path = entry.absoluteFilePath();
        const QString middle = name.mid(base.size() + 1);  // "en", "eng", "English", "en.forced"
        const QString first = middle.section('.', 0, 0);
        if (!first.isEmpty()) {
            if (!probe::languageName(first).isEmpty() && first.size() <= 3)
                sidecar.language = first.toLower();
            sidecar.label = !sidecar.language.isEmpty() ? probe::languageName(sidecar.language) : middle;
        }
        if (sidecar.label.isEmpty())
            sidecar.label = entry.fileName();
        found << sidecar;
    }
    QCollator collator;
    collator.setNumericMode(true);
    std::sort(found.begin(), found.end(),
              [&](const Sidecar &a, const Sidecar &b) { return collator.compare(a.path, b.path) < 0; });
    return found;
}

QList<Cue> parseWebVtt(const QString &text) {
    QList<Cue> cues;
    static const QRegularExpression timing(R"(^\s*([\d:.,]+)\s*-->\s*([\d:.,]+))");
    static const QRegularExpression tags(R"(<[^>]*>|\{\\[^}]*\})");
    const QStringList lines = QString(text).replace("\r\n", "\n").replace('\r', '\n').split('\n');
    for (qsizetype i = 0; i < lines.size(); ++i) {
        const auto match = timing.match(lines.at(i));
        if (!match.hasMatch())
            continue;
        Cue cue;
        cue.start = timestamp(match.captured(1));
        cue.end = timestamp(match.captured(2));
        QStringList body;
        for (++i; i < lines.size() && !lines.at(i).trimmed().isEmpty(); ++i)
            body << QString(lines.at(i)).remove(tags).replace("&lt;", "<").replace("&gt;", ">")
                        .replace("&nbsp;", QString(QChar(0xa0))).replace("&amp;", "&").trimmed();
        body.removeAll(QString());
        cue.text = body.join('\n');
        if (cue.start >= 0 && cue.end > cue.start && !cue.text.isEmpty())
            cues << cue;
    }
    std::stable_sort(cues.begin(), cues.end(), [](const Cue &a, const Cue &b) { return a.start < b.start; });
    qint64 reach = 0;
    for (Cue &cue : cues)
        cue.reach = reach = std::max(reach, cue.end);
    return cues;
}

QList<Cue> load(const QString &path, int stream, QString *error, const std::atomic_bool *cancelled) {
    if (cancelled && *cancelled)
        return {};
    const QString ffmpeg = probe::toolPath("ffmpeg");
    if (ffmpeg.isEmpty()) {
        if (error)
            *error = Texts::tr("ffmpeg was not found. Install ffmpeg.");
        return {};
    }
    QProcess process;
    process.setChildProcessModifier([] { (void)::nice(10); });
    // Reading a track out of a film means reading the film, so it gets time.
    process.start(ffmpeg, {"-nostdin", "-v", "error", "-i", path, "-map", QString("0:s:%1").arg(stream),
                           "-f", "webvtt", "-"});
    // In slices, so a track that is no longer wanted stops its ffmpeg.
    QElapsedTimer clock;
    clock.start();
    bool stopped = false;
    while (!process.waitForFinished(100) && process.state() != QProcess::NotRunning) {
        if ((cancelled && *cancelled) || clock.elapsed() > 120000) {
            process.kill();
            process.waitForFinished(1000);
            stopped = true;
            break;
        }
    }
    if (stopped || process.error() == QProcess::FailedToStart || process.exitStatus() != QProcess::NormalExit
        || process.exitCode() != 0) {
        if (error)
            *error = Texts::tr("Could not read the subtitles in %1.").arg(QFileInfo(path).fileName());
        return {};
    }
    return parseWebVtt(QString::fromUtf8(process.readAllStandardOutput()));
}

QString at(const QList<Cue> &cues, qint64 ms) {
    // The first cue starting after ms; everything showing starts before it.
    // Walking back, a cue whose reach has passed means no earlier one can
    // still be showing, however long ago a long line began.
    auto after = std::upper_bound(cues.begin(), cues.end(), ms, [](qint64 t, const Cue &c) { return t < c.start; });
    QStringList showing;
    for (auto it = after; it != cues.begin();) {
        --it;
        if (it->reach <= ms)
            break;
        if (it->end > ms)
            showing.prepend(it->text);
    }
    return showing.join('\n');
}

}  // namespace subtitles
