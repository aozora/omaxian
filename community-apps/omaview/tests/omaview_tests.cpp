#include <QDBusConnection>
#include <QDBusPendingCall>
#include <QDBusVariant>
#include <QDBusReply>
#include <QBuffer>
#include <QDir>
#include <QFile>
#include <QImage>
#include <QtEndian>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QMediaPlayer>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

#include "backend.h"
#include "cli.h"
#include "exif.h"
#include "fixtures.h"
#include "frames.h"
#include "mpris.h"
#include "picture.h"
#include "playlist.h"
#include "positions.h"
#include "probe.h"
#include "subtitles.h"
#include "theme.h"
#include "translator.h"

namespace {

bool write(const QString &path, const QByteArray &contents) {
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(contents) == contents.size();
}

// A photo of a size as stored, with a camera's EXIF: an orientation of 6
// means it is shown turned a quarter clockwise.
bool writePhoto(const QString &path, QSize stored, quint16 orientation) {
    using namespace fixtures;
    QImage image(stored, QImage::Format_RGB32);
    image.fill(Qt::darkCyan);
    return write(path, jpegWithExif(image, {ascii(0x010F, "Canon"), ascii(0x0110, "Canon EOS R5"), shortTag(0x0112, orientation)},
                                    {rational(0x829A, 1, 250), rational(0x829D, 28, 10), shortTag(0x8827, 400),
                                     ascii(0x9003, "2026:07:14 18:30:05"), rational(0x920A, 50, 1),
                                     shortTag(0xA405, 50), ascii(0xA434, "RF50mm F1.8 STM")}));
}

int lines(const QString &path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll().count('\n') : 0;
}

// A hyprctl that answers with response.json beside it and counts its calls.
QString fakeHyprctl(const QString &directory) {
    const QString command = directory + "/hyprctl";
    write(command, "#!/bin/bash\necho >> '" + directory.toUtf8() + "/calls'\ncat '" + directory.toUtf8()
                       + "/response.json'\n");
    QFile::setPermissions(command, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    return command;
}

QJsonObject readCatalog(const QString &path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(file.readAll()).object() : QJsonObject();
}

// The placeholders in a text, sorted: %1 to %99, and the count (%n, %Ln).
QStringList placeholders(const QString &text) {
    static const QRegularExpression placeholder("%L?(?:[1-9][0-9]?|n)");
    QStringList found;
    for (auto it = placeholder.globalMatch(text); it.hasNext();)
        found << it.next().captured();
    found.sort();
    return found;
}

// Every text the sources hand to qsTr() or tr(), and whether a call passes it
// a count. It walks the code a token at a time, so a string never hides a
// comment or the other way round, C++'s adjacent literals join, and QML's
// single quotes count. A text that isn't a literal can't be in a catalog.
QMap<QString, bool> translatables(const QString &folder, QStringList *problems) {
    QMap<QString, bool> found;
    for (const QFileInfo &info : QDir(folder).entryInfoList({"*.qml", "*.js", "*.cpp", "*.h"}, QDir::Files)) {
        QFile file(info.filePath());
        if (!file.open(QIODevice::ReadOnly))
            continue;
        const QString code = QString::fromUtf8(file.readAll());
        qsizetype i = 0;
        auto literal = [&](QString *text) {
            const QChar quote = code[i++];
            for (; i < code.size() && code[i] != quote; ++i) {
                if (code[i] == '\\' && i + 1 < code.size()) {
                    const QChar escaped = code[++i];
                    const int digits = escaped == 'u' ? 4 : escaped == 'x' ? 2 : 0;
                    bool hex = false;
                    const ushort unit = code.mid(i + 1, digits).toUShort(&hex, 16);
                    if (digits && hex) {
                        *text += QChar(unit);
                        i += digits;
                    } else {
                        *text += escaped == 'n' ? QChar('\n') : escaped == 't' ? QChar('\t') : escaped;
                    }
                } else {
                    *text += code[i];
                }
            }
            ++i;
        };
        auto skipSpace = [&] {
            while (i < code.size() && code[i].isSpace())
                ++i;
        };
        while (i < code.size()) {
            const QChar c = code[i];
            if (code.mid(i, 2) == "//") {
                i = code.indexOf('\n', i);
                if (i < 0)
                    break;
            } else if (code.mid(i, 2) == "/*") {
                i = code.indexOf("*/", i + 2);
                if (i < 0)
                    break;
                i += 2;
            } else if (c == '"' || c == '\'') {
                QString skipped;
                literal(&skipped);
            } else if (c.isLetter() || c == '_') {
                const qsizetype start = i;
                while (i < code.size() && (code[i].isLetterOrNumber() || code[i] == '_'))
                    ++i;
                const QString word = code.mid(start, i - start);
                skipSpace();
                if ((word != "qsTr" && word != "tr") || i >= code.size() || code[i] != '(')
                    continue;
                ++i;
                skipSpace();
                if (i >= code.size() || (code[i] != '"' && code[i] != '\'')) {
                    *problems << info.fileName() + ": not a literal: " + code.mid(start, 40);
                    continue;
                }
                QString text;
                do {
                    literal(&text);
                    skipSpace();
                } while (i < code.size() && code[i] == '"');
                // The arguments after the text, to the call's closing parenthesis.
                int depth = 0, commas = 0;
                while (i < code.size()) {
                    const QChar d = code[i];
                    if (d == '"' || d == '\'') {
                        QString skipped;
                        literal(&skipped);
                        continue;
                    }
                    if (d == '(' || d == '[' || d == '{')
                        ++depth;
                    else if ((d == ')' || d == ']' || d == '}') && depth-- == 0)
                        break;
                    else if (d == ',' && depth == 0)
                        ++commas;
                    ++i;
                }
                found[text] = found.value(text) || commas >= 2;
            } else {
                ++i;
            }
        }
    }
    return found;
}

} // namespace

namespace {

// Makes a clip with ffmpeg from lavfi sources; extra arguments come before
// the output name.
bool ffmpeg(const QString &directory, const QStringList &arguments) {
    QProcess process;
    process.setWorkingDirectory(directory);
    process.start("ffmpeg", QStringList{"-v", "error", "-y"} + arguments);
    return process.waitForFinished(120000) && process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0;
}

}  // namespace

class OmaviewTests : public QObject {
    Q_OBJECT

    QTemporaryDir m_home;
    QString m_clip;
    QString m_picture;

private slots:
    void initTestCase() {
        QQuickStyle::setStyle("Material");
        QVERIFY(m_home.isValid());
        // Caches and state go to a temp home, and nothing here may reach the
        // desktop's clipboard.
        qputenv("XDG_CACHE_HOME", m_home.filePath("cache").toUtf8());
        qputenv("XDG_STATE_HOME", m_home.filePath("state").toUtf8());
        qunsetenv("WAYLAND_DISPLAY");
        // Ten seconds with English audio and English and Danish subtitles.
        QVERIFY(write(m_home.filePath("en.srt"), "1\n00:00:00,500 --> 00:00:04,000\nHello there.\n"));
        QVERIFY(write(m_home.filePath("da.srt"), "1\n00:00:00,500 --> 00:00:04,000\nHej med dig.\n"));
        QVERIFY(ffmpeg(m_home.path(), {"-f", "lavfi", "-i", "testsrc2=size=320x180:rate=25:duration=10", "-f", "lavfi",
                                       "-i", "sine=duration=10", "-i", "en.srt", "-i", "da.srt", "-map", "0:v", "-map",
                                       "1:a", "-map", "2:s", "-map", "3:s", "-c:v", "libx264", "-g", "25", "-pix_fmt",
                                       "yuv420p", "-c:a", "aac", "-ac", "2", "-c:s", "srt", "-metadata:s:a:0",
                                       "language=eng", "-metadata:s:s:0", "language=eng", "-metadata:s:s:1",
                                       "language=dan", "clip.mkv"}));
        m_clip = m_home.filePath("clip.mkv");
        // A photo taken upright on a camera held on its side, beside a clip
        // from the same day, as a phone's camera folder has them.
        QVERIFY(QDir(m_home.path()).mkpath("photos"));
        m_picture = m_home.filePath("photos/photo.jpg");
        QVERIFY(writePhoto(m_picture, QSize(600, 400), 6));
        QVERIFY(QFile::copy(m_clip, m_home.filePath("photos/clip.mkv")));
    }

    // ffprobe

    void probeReadsStreamsAndChapters() {
        const QByteArray json = R"json({
            "streams": [
                {"index": 0, "codec_type": "video", "codec_name": "h264", "width": 1920, "height": 1080,
                 "avg_frame_rate": "24000/1001", "disposition": {"default": 1}},
                {"index": 1, "codec_type": "audio", "codec_name": "eac3", "channels": 6,
                 "channel_layout": "5.1(side)", "tags": {"language": "eng", "title": "Surround"}},
                {"index": 2, "codec_type": "subtitle", "codec_name": "hdmv_pgs_subtitle", "tags": {"LANGUAGE": "dan"}},
                {"index": 3, "codec_type": "subtitle", "codec_name": "subrip", "tags": {"language": "und"}},
                {"index": 4, "codec_type": "video", "codec_name": "mjpeg", "disposition": {"attached_pic": 1}}
            ],
            "chapters": [{"start_time": "0.000000", "end_time": "60.5", "tags": {"title": "Opening"}}],
            "format": {"format_long_name": "Matroska / WebM", "duration": "5400.25", "size": "123",
                       "tags": {"TITLE": "A Film"}}
        })json";
        const probe::Info info = probe::parse(json, "/films/a.mkv");
        QVERIFY(info.ok());
        QCOMPARE(info.title, QString("A Film"));
        QCOMPARE(info.duration, 5400.25);
        QCOMPARE(info.ofType("video").size(), 1);  // cover art isn't a video
        QCOMPARE(info.video()->frameRate, 24000.0 / 1001);
        QCOMPARE(info.ofType("audio").first().channelLayout, QString("5.1(side)"));
        // Bitmap subtitles are never offered to Qt's text-only path.
        QVERIFY(!info.ofType("subtitle").at(0).textSubtitle());
        QVERIFY(info.ofType("subtitle").at(1).textSubtitle());
        QCOMPARE(info.ofType("subtitle").at(0).language, QString("dan"));
        QCOMPARE(info.ofType("subtitle").at(1).language, QString());
        QCOMPARE(info.chapters.size(), 1);
        QCOMPARE(info.chapters.first().title, QString("Opening"));
        QVERIFY(!probe::parse("not json", "x").ok());
    }

    void probeRunsFfprobe() {
        const probe::Info info = probe::run(m_clip);
        QVERIFY2(info.ok(), qPrintable(info.error));
        QVERIFY(qAbs(info.duration - 10) < 0.2);
        QCOMPARE(info.ofType("subtitle").size(), 2);
        QVERIFY(!probe::run(m_home.filePath("missing.mkv")).ok());
    }

    void languagesAreNamed() {
        QCOMPARE(probe::shortLanguage("eng"), QString("en"));
        QCOMPARE(probe::shortLanguage("ger"), QString("de"));
        QCOMPARE(probe::shortLanguage("dan"), QString("da"));
        QCOMPARE(probe::shortLanguage("pt"), QString("pt"));
        QCOMPARE(probe::languageName("und"), QString());
        QCOMPARE(probe::languageName(""), QString());
        QVERIFY(!probe::languageName("fre").isEmpty());
    }

    // Subtitles

    void webVttParses() {
        const auto cues = subtitles::parseWebVtt(
            "WEBVTT\n\n00:01.000 --> 00:02.500\n<i>Hello</i> &amp; welcome\nsecond line\n\n"
            "1\n00:00:03,000 --> 00:00:04,000 align:start\n{\\an8}Top\n\n"
            "00:03.500 --> 00:05.000\nOverlap\n\n00:06.000 --> 00:05.000\nBackwards\n");
        QCOMPARE(cues.size(), 3);
        QCOMPARE(cues.at(0).start, qint64(1000));
        QCOMPARE(cues.at(0).end, qint64(2500));
        QCOMPARE(cues.at(0).text, QString("Hello & welcome\nsecond line"));
        QCOMPARE(cues.at(1).text, QString("Top"));
        QCOMPARE(subtitles::at(cues, 999), QString());
        QCOMPARE(subtitles::at(cues, 1500), QString("Hello & welcome\nsecond line"));
        QCOMPARE(subtitles::at(cues, 3700), QString("Top\nOverlap"));
        QCOMPARE(subtitles::at(cues, 4500), QString("Overlap"));
        QCOMPARE(subtitles::at(cues, 9000), QString());

        // A long line stays while many short ones come and go beneath it.
        QString vtt = "WEBVTT\n\n00:00.000 --> 01:00.000\nNarrator\n\n";
        for (int i = 0; i < 20; ++i)
            vtt += QString("00:%1.000 --> 00:%1.500\nShort %2\n\n").arg(i + 10, 2, 10, QChar('0')).arg(i);
        const auto many = subtitles::parseWebVtt(vtt);
        QCOMPARE(many.size(), 21);
        QCOMPARE(subtitles::at(many, 45000), QString("Narrator"));
        QCOMPARE(subtitles::at(many, 12200), QString("Narrator\nShort 2"));
    }

    void sidecarsAreFoundBesideTheVideo() {
        QTemporaryDir dir;
        for (const char *name : {"film.mkv", "film.srt", "film.en.srt", "film.dan.ass", "film.English.vtt",
                                 "film2.srt", "other.srt", "film.txt"})
            QVERIFY(write(dir.filePath(name), "x"));
        const auto found = subtitles::find(dir.filePath("film.mkv"));
        QStringList names;
        for (const auto &sidecar : found)
            names << QFileInfo(sidecar.path).fileName();
        QCOMPARE(names, (QStringList{"film.dan.ass", "film.en.srt", "film.English.vtt", "film.srt"}));
        QCOMPARE(found.at(0).language, QString("dan"));
        QCOMPARE(found.at(1).language, QString("en"));
        QCOMPARE(found.at(2).language, QString());
        QCOMPARE(found.at(2).label, QString("English"));
        QCOMPARE(found.at(3).label, QString("film.srt"));
    }

    void subtitlesLoadThroughFfmpeg() {
        QString error;
        auto cues = subtitles::load(m_home.filePath("da.srt"), 0, &error);
        QVERIFY2(!cues.isEmpty(), qPrintable(error));
        QCOMPARE(cues.first().text, QString("Hej med dig."));
        // And a track out of the video, by its place among the subtitles.
        cues = subtitles::load(m_clip, 1, &error);
        QVERIFY2(!cues.isEmpty(), qPrintable(error));
        QCOMPARE(cues.first().text, QString("Hej med dig."));
        QVERIFY(subtitles::load(m_home.filePath("missing.srt"), 0, &error).isEmpty());
        QVERIFY(!error.isEmpty());
    }

    // The playlist

    void folderIsThePlaylistInNaturalOrder() {
        QTemporaryDir dir;
        for (const char *name : {"Episode 10.mkv", "episode 2.mkv", "Episode 1.mp4", "notes.txt", "song.flac", "cover.jpg"})
            QVERIFY(write(dir.filePath(name), "x"));
        QStringList names;
        for (const QString &path : playlist::siblings(dir.filePath("episode 2.mkv")))
            names << QFileInfo(path).fileName();
        QCOMPARE(names, (QStringList{"cover.jpg", "Episode 1.mp4", "episode 2.mkv", "Episode 10.mkv", "song.flac"}));
        QCOMPARE(playlist::kind("a.FLAC"), playlist::Kind::Audio);
        QCOMPARE(playlist::kind("a.txt"), playlist::Kind::None);
    }

    void songsAndPicturesDontMix() {
        QTemporaryDir dir;
        for (const char *name : {"IMG_2.jpg", "IMG_10.HEIC", "IMG_3.mov", "memo.m4a", "scan.pdf", "IMG_1.png"})
            QVERIFY(write(dir.filePath(name), "x"));
        auto names = [&](const char *opened) {
            QStringList found;
            for (const QString &path : playlist::siblings(dir.filePath(opened)))
                found << QFileInfo(path).fileName();
            return found;
        };
        // HEIC counts only where an image plugin reads it, and a PDF never.
        const bool heic = playlist::picture("x.heic");
        QStringList photos{"IMG_1.png", "IMG_2.jpg", "IMG_3.mov"};
        if (heic)
            photos << "IMG_10.HEIC";
        QCOMPARE(names("IMG_2.jpg"), photos);
        QCOMPARE(names("memo.m4a"), (QStringList{"IMG_3.mov", "memo.m4a"}));
        QCOMPARE(playlist::kind("scan.pdf"), playlist::Kind::None);
        // A folder opened as itself is its pictures and videos; one of songs,
        // its songs and videos.
        QStringList folder;
        for (const QString &path : playlist::folder(dir.path()))
            folder << QFileInfo(path).fileName();
        QCOMPARE(folder, photos);
        QTemporaryDir album;
        for (const char *name : {"2 b.flac", "1 a.flac", "live.mkv", "cover.jpg"})
            QVERIFY(write(album.filePath(name), "x"));
        folder.clear();
        for (const QString &path : playlist::folder(album.path()))
            folder << QFileInfo(path).fileName();
        QCOMPARE(folder, (QStringList{"1 a.flac", "2 b.flac", "live.mkv"}));
    }

    // Pictures

    void exifIsRead() {
        const exif::Tags tags = exif::read(m_picture);
        QCOMPARE(tags.camera(), QString("Canon EOS R5"));
        QCOMPARE(tags.lens, QString("RF50mm F1.8 STM"));
        QCOMPARE(tags.exposure, 1.0 / 250);
        QCOMPARE(tags.aperture, 2.8);
        QCOMPARE(tags.iso, 400);
        QCOMPARE(tags.focal35, 50);
        QCOMPARE(tags.taken, QDateTime(QDate(2026, 7, 14), QTime(18, 30, 5)));
        // Nikon says its name in full as the make, and only "NIKON" before
        // the model.
        exif::Tags nikon;
        nikon.make = "NIKON CORPORATION";
        nikon.model = "Z 6";
        QCOMPARE(nikon.camera(), QString("NIKON Z 6"));
        // Nothing in a file without it, nor in a truncated one.
        QVERIFY(exif::read(m_clip).empty());
        QVERIFY(exif::parse(QByteArray("II*\0\x08\0\0\0\xFF\xFF", 10)).empty());
    }

    void picturesAreReadUpright() {
        const picture::Info info = picture::read(m_picture);
        QVERIFY2(info.ok(), qPrintable(info.error));
        QCOMPARE(info.format, QString("JPEG"));
        QCOMPARE(info.size, QSize(400, 600));
        QVERIFY(!info.animated && !info.transparent && !info.vector);
        QCOMPARE(info.exif.iso, 400);
        QCOMPARE(picture::load(m_picture).size(), QSize(400, 600));
        QCOMPARE(picture::load(m_picture, 90).size(), QSize(600, 400));

        QTemporaryDir dir;
        QImage clear(32, 16, QImage::Format_ARGB32);
        clear.fill(Qt::transparent);
        QVERIFY(clear.save(dir.filePath("clear.png")));
        QVERIFY(picture::read(dir.filePath("clear.png")).transparent);
        QVERIFY(write(dir.filePath("broken.png"), "not a picture"));
        QVERIFY(!picture::read(dir.filePath("broken.png")).ok());
    }

    void aPhonesPortraitClipIsTall() {
        // Stored on its side with a display matrix, as a phone writes it.
        QTemporaryDir state;
        const QString turned = state.filePath("portrait.mp4");
        QCOMPARE(QProcess::execute("ffmpeg", {"-v", "error", "-y", "-display_rotation", "90", "-i", m_clip,
                                              "-c", "copy", turned}), 0);
        QCOMPARE(probe::run(turned).video()->rotation % 180 != 0, true);
        Backend::Options options;
        options.positionsPath = state.filePath("positions.json");
        options.audio = false;
        options.previews = false;
        Backend backend(options);
        backend.open({turned});
        QTRY_VERIFY_WITH_TIMEOUT(backend.videoSize().isValid(), 10000);
        QVERIFY(backend.videoSize().height() > backend.videoSize().width());
    }

    void aFolderWaitsOnlyOnItsFirstFile() {
        // A folder opening on a picture: the video picked after it plays.
        QTemporaryDir state, folder;
        QVERIFY(QFile::copy(m_picture, folder.filePath("a.jpg")));
        QVERIFY(QFile::copy(m_clip, folder.filePath("b.mkv")));
        Backend::Options options;
        options.positionsPath = state.filePath("positions.json");
        options.audio = false;
        options.previews = false;
        Backend backend(options);
        QSignalSpy opened(&backend, &Backend::folderOpened);
        backend.open({folder.path()});
        QTRY_COMPARE(opened.count(), 1);
        QVERIFY(backend.isPicture());
        QVERIFY(backend.go(1));
        QTRY_VERIFY_WITH_TIMEOUT(backend.playing(), 10000);
        // An empty folder opens nothing, and says so.
        QTemporaryDir empty;
        QSignalSpy nothing(&backend, &Backend::nothingToOpen);
        backend.open({empty.path()});
        QTRY_COMPARE(nothing.count(), 1);
    }

    void aPictureNeverStartsThePlayer() {
        QTemporaryDir state;
        Backend::Options options;
        options.positionsPath = state.filePath("positions.json");
        options.audio = false;
        options.previews = false;
        Backend backend(options);
        backend.open({m_picture});
        QVERIFY(backend.isPicture());
        QVERIFY(!backend.playerReady());
        // The window gets the picture once its header has been read.
        QCOMPARE(backend.pictureSource(), QUrl());
        QTRY_COMPARE(backend.pictureSource(), QUrl::fromLocalFile(m_picture));
        QCOMPARE(backend.pictureSize(), QSize(400, 600));
        QTRY_COMPARE(backend.playlistCount(), 2);
        QStringList rows;
        for (const QVariant &row : backend.info())
            rows << row.toMap().value("label").toString() + ": " + row.toMap().value("value").toString();
        QVERIFY2(rows.contains("Camera: Canon EOS R5"), qPrintable(rows.join('\n')));
        QVERIFY2(rows.contains("Exposure: 1/250 s · f/2.8 · ISO 400 · 50 mm"), qPrintable(rows.join('\n')));
        QVERIFY(rows.contains("Dimensions: 400 × 600 · 0.2 MP"));

        // Turned as it shows, by quarter turns either way, and anew for the
        // next picture.
        backend.rotate(90);
        backend.rotate(-180);
        QCOMPARE(backend.rotation(), 270);
        backend.play();
        QVERIFY(!backend.playerReady());

        // The clip beside it plays, and stepping back to the photo stops it.
        QVERIFY(backend.previous());
        QVERIFY(!backend.isPicture());
        QTRY_VERIFY_WITH_TIMEOUT(backend.playing(), 10000);
        QVERIFY(backend.next());
        QVERIFY(backend.isPicture());
        QCOMPARE(backend.rotation(), 0);
        QTRY_VERIFY(!backend.playing());
        QCOMPARE(backend.duration(), qint64(0));
        backend.close();
    }

    void aChangedPictureIsReadAgain() {
        QTemporaryDir dir;
        const QString path = dir.filePath("edit.png");
        QImage image(40, 20, QImage::Format_RGB32);
        image.fill(Qt::red);
        QVERIFY(image.save(path));
        Backend::Options options;
        options.positionsPath = dir.filePath("positions.json");
        options.audio = false;
        options.previews = false;
        Backend backend(options);
        backend.open({path});
        QTRY_COMPARE(backend.pictureSize(), QSize(40, 20));
        // Saved as an editor saves: a new file renamed over the old.
        QImage wider(80, 20, QImage::Format_RGB32);
        wider.fill(Qt::blue);
        QVERIFY(wider.save(dir.filePath("edit.tmp.png")));
        QFile::remove(path);
        QVERIFY(QFile::rename(dir.filePath("edit.tmp.png"), path));
        QTRY_COMPARE(backend.pictureSize(), QSize(80, 20));
        QCOMPARE(backend.pictureSource().fragment(), QString("r1"));
        backend.close();
    }

    void theTrashTakesAFileAndGivesItBack() {
        // A home of its own on the same disk as the files, so the Trash used
        // is a temporary one and never the desktop's.
        QTemporaryDir home;
        const QByteArray realHome = qgetenv("HOME"), realData = qgetenv("XDG_DATA_HOME");
        qputenv("HOME", home.path().toUtf8());
        qputenv("XDG_DATA_HOME", home.filePath("data").toUtf8());
        QVERIFY(QDir(home.path()).mkpath("photos"));
        // Qt makes the Trash only where ~/.local/share is, as it always is.
        QVERIFY(QDir(home.path()).mkpath("data"));
        QImage image(8, 8, QImage::Format_RGB32);
        image.fill(Qt::green);
        for (const char *name : {"a.png", "b.png", "c.png"})
            QVERIFY(image.save(home.filePath(QString("photos/") + name)));
        {
            Backend::Options options;
            options.positionsPath = home.filePath("positions.json");
            options.audio = false;
            options.previews = false;
            Backend backend(options);
            backend.open({home.filePath("photos/b.png")});
            QTRY_COMPARE(backend.playlistCount(), 3);
            QVERIFY(backend.trash());
            QVERIFY(!QFile::exists(home.filePath("photos/b.png")));
            QVERIFY(QFile::exists(home.filePath("data/Trash/files/b.png")));
            QVERIFY(QFile::exists(home.filePath("data/Trash/info/b.png.trashinfo")));
            QCOMPARE(backend.fileName(), QString("c.png"));
            QCOMPARE(backend.playlistCount(), 2);
            // Something in its way keeps it in the Trash, and Ctrl+Z works
            // again once that has gone.
            QVERIFY(write(home.filePath("photos/b.png"), "in the way"));
            QVERIFY(!backend.undoTrash());
            QVERIFY(QFile::remove(home.filePath("photos/b.png")));
            // Ctrl+Z puts it back, where it was, and shows it again.
            QVERIFY(backend.undoTrash());
            QVERIFY(QFile::exists(home.filePath("photos/b.png")));
            QVERIFY(!QFile::exists(home.filePath("data/Trash/info/b.png.trashinfo")));
            QCOMPARE(backend.fileName(), QString("b.png"));
            QCOMPARE(backend.playlistIndex(), 1);
            QVERIFY(!backend.undoTrash());
            // The last file going leaves the window empty.
            backend.open({home.filePath("photos/a.png"), home.filePath("photos/c.png")});
            QVERIFY(backend.trash());
            QVERIFY(backend.trash());
            QVERIFY(!backend.hasMedia());
            QVERIFY(!backend.trash());
            backend.close();
        }
        qputenv("HOME", realHome);
        if (realData.isEmpty())
            qunsetenv("XDG_DATA_HOME");
        else
            qputenv("XDG_DATA_HOME", realData);
    }

    // Resume positions

    void positionsFollowTheRules() {
        QTemporaryDir dir;
        const QString film = dir.filePath("film.mkv");
        QVERIFY(write(film, "a film"));
        Positions positions(dir.filePath("positions.json"));
        const qint64 hour = 3600 * 1000;
        positions.update(film, 20 * 60 * 1000, hour);
        QCOMPARE(positions.lookup(film), qint64(20 * 60 * 1000));
        // Near the end counts as watched, and is forgotten.
        positions.update(film, hour - 60 * 1000, hour);
        QCOMPARE(positions.lookup(film), qint64(-1));
        // A short clip is never remembered.
        positions.update(film, 60 * 1000, 4 * 60 * 1000);
        QCOMPARE(positions.lookup(film), qint64(-1));
        // An edited file starts over.
        positions.update(film, 20 * 60 * 1000, hour);
        QVERIFY(write(film, "a longer film now"));
        QCOMPARE(positions.lookup(film), qint64(-1));
        // The file holds no names.
        QFile stored(dir.filePath("positions.json"));
        QVERIFY(stored.open(QIODevice::ReadOnly));
        QVERIFY(!stored.readAll().contains("film"));
    }

    void positionsFromTwoWindowsBothSurvive() {
        QTemporaryDir dir;
        const QString a = dir.filePath("a.mkv"), b = dir.filePath("b.mkv");
        QVERIFY(write(a, "a"));
        QVERIFY(write(b, "b"));
        Positions first(dir.filePath("positions.json")), second(dir.filePath("positions.json"));
        first.update(a, 600000, 3600000);
        second.update(b, 700000, 3600000);
        first.setPreference("volume", 0.4);
        QCOMPARE(second.lookup(a), qint64(600000));
        QCOMPARE(first.lookup(b), qint64(700000));
        QCOMPARE(second.preferences().value("volume").toDouble(), 0.4);
    }

    // The command line

    void timesParse() {
        QCOMPARE(parseTime("90"), 90.0);
        QCOMPARE(parseTime("1:30"), 90.0);
        QCOMPARE(parseTime("1:02:03.5"), 3723.5);
        QCOMPARE(parseTime("x"), -1.0);
        QCOMPARE(parseTime("1:2:3:4"), -1.0);
        QCOMPARE(parseTime("-5"), -1.0);
    }

    void framesAreExact() {
        QString error;
        const QImage frame = frames::extract(m_clip, 2.0, &error);
        QVERIFY2(!frame.isNull(), qPrintable(error));
        QCOMPARE(frame.size(), QSize(320, 180));
        QVERIFY(frames::extract(m_clip, 3600, &error).isNull());
        QVERIFY(!error.isEmpty());
        const QString out = m_home.filePath("frame.png");
        QVERIFY(frames::savePng(frame, out, &error));
        QCOMPARE(QImage(out).size(), QSize(320, 180));
    }

    void theGridHasAPosterAndAFilmstrip() {
        const QImage poster = frames::poster(m_clip);
        QCOMPARE(poster.width(), 640);
        // Ten frames from across the video, each its own, made once.
        const QImage first = frames::filmstripFrame(m_clip, 0);
        const QImage last = frames::filmstripFrame(m_clip, frames::filmstripFrames - 1);
        QCOMPARE(first.width(), 320);
        QCOMPARE(last.size(), first.size());
        QVERIFY(first != last);
        QVERIFY(frames::filmstripFrame(m_clip, frames::filmstripFrames).isNull());
        QVERIFY(QFileInfo::exists(frames::previewCacheDirectory() + "/" + Positions::key(m_clip) + ".strip.jpg"));
    }

    // Previews

    void previewLayoutIsCapped() {
        auto layout = frames::PreviewLayout::forVideo(10, QSize(1920, 1080));
        QCOMPARE(layout.count, 5);
        QCOMPARE(layout.interval, 2.0);
        QCOMPARE(layout.tileSize, QSize(192, 108));
        layout = frames::PreviewLayout::forVideo(7200, QSize(1080, 1920));
        QCOMPARE(layout.count, 100);
        QCOMPARE(layout.columns, 10);
        QCOMPARE(layout.tileSize.height(), 340);
        QCOMPARE(frames::PreviewLayout::forVideo(0, QSize(10, 10)).count, 0);
    }

    void previewsAreBuiltAndCached() {
        frames::Previews previews;
        QSignalSpy ready(&previews, &frames::Previews::ready);
        previews.start(m_clip, 10, QSize(320, 180));
        QVERIFY(ready.wait(60000));
        const QString atlas = ready.first().at(0).toString();
        QVERIFY(atlas.startsWith(m_home.filePath("cache")));
        QCOMPARE(QImage(atlas).size(), QSize(192 * 5, 108));
        // The second time comes from the cache, at once.
        previews.start(m_clip, 10, QSize(320, 180));
        QCOMPARE(ready.size(), 2);
        // A cache over its limit loses its oldest first.
        frames::prunePreviewCache(frames::previewCacheDirectory(), 0);
        QVERIFY(!QFileInfo::exists(atlas));
    }

    // The backend, with the real player and no audio device.

    void tracksFollowTheReadersLanguage() {
        QTemporaryDir state;
        Backend::Options options;
        options.positionsPath = state.filePath("positions.json");
        options.audio = false;
        options.previews = false;
        Backend backend(options);
        // English audio for a Danish reader: Danish subtitles come on.
        backend.setLanguage("da");
        backend.open({m_clip});
        QTRY_VERIFY_WITH_TIMEOUT(backend.subtitleChoices() == 2, 10000);
        QTRY_COMPARE(backend.subtitleLabel(), probe::languageName("da"));
        // Turned off, and remembered for the next file.
        backend.cycleSubtitles();
        QCOMPARE(backend.subtitleLabel(), QString());
        backend.flush();
        QCOMPARE(Positions(options.positionsPath).preferences().value("subtitleLanguage").toString(), QString("off"));
        backend.open({m_clip});
        QTRY_VERIFY_WITH_TIMEOUT(backend.subtitleChoices() == 2, 10000);
        QTest::qWait(200);
        QCOMPARE(backend.subtitleLabel(), QString());
        backend.close();

        // A language switch says again everything C++ translated.
        QSignalSpy tracks(&backend, &Backend::tracksChanged), info(&backend, &Backend::infoChanged),
            errors(&backend, &Backend::errorChanged);
        backend.setLanguage("de");
        QCOMPARE(tracks.size(), 1);
        QCOMPARE(info.size(), 1);
        QCOMPARE(errors.size(), 1);

        // An English reader of an English film gets none.
        QTemporaryDir fresh;
        options.positionsPath = fresh.filePath("positions.json");
        Backend english(options);
        english.setLanguage("en");
        english.open({m_clip});
        QTRY_VERIFY_WITH_TIMEOUT(english.subtitleChoices() == 2, 10000);
        QTRY_COMPARE(english.audioLabel(), probe::languageName("en") + " · stereo");
        QCOMPARE(english.subtitleLabel(), QString());
        english.close();
    }

    void resumesWhereItWasLeft() {
        QTemporaryDir state;
        // Six minutes, at a frame a second, so it is quick to make.
        QVERIFY(ffmpeg(state.path(), {"-f", "lavfi", "-i", "testsrc2=size=64x36:rate=1:duration=360", "-c:v",
                                      "libx264", "-preset", "ultrafast", "-g", "10", "-pix_fmt", "yuv420p", "long.mkv"}));
        const QString film = state.filePath("long.mkv");
        Backend::Options options;
        options.positionsPath = state.filePath("positions.json");
        options.audio = false;
        options.previews = false;
        {
            Backend backend(options);
            backend.open({film});
            QTRY_VERIFY_WITH_TIMEOUT(backend.seekable() && backend.duration() > 0, 10000);
            backend.pause();
            backend.seek(120000);
            // The window's closing and the application's quitting both close;
            // the second, after the player has stopped, changes nothing.
            backend.close();
            backend.close();
        }
        QCOMPARE(Positions(options.positionsPath).lookup(film), qint64(120000));
        Backend backend(options);
        backend.open({film});
        QTRY_COMPARE_WITH_TIMEOUT(backend.resumedAt(), qint64(120000), 10000);
        QTRY_VERIFY(qAbs(backend.position() - 117000) < 2000);
        backend.startOver();
        QCOMPARE(backend.position(), qint64(0));
        QCOMPARE(backend.resumedAt(), qint64(-1));
        backend.close();
    }

    void severalFilesAreThePlaylist() {
        QTemporaryDir state;
        Backend::Options options;
        options.positionsPath = state.filePath("positions.json");
        options.audio = false;
        options.previews = false;
        Backend backend(options);
        const QString missing = state.filePath("gone.mkv");
        backend.open({m_clip, missing});
        QCOMPARE(backend.playlist(), (QStringList{m_clip, missing}));
        QCOMPARE(backend.nextName(), QString("gone.mkv"));
        QTRY_VERIFY_WITH_TIMEOUT(!backend.info().isEmpty() && backend.chapters().isEmpty(), 10000);
        QVERIFY(backend.next());
        QCOMPARE(backend.error(), QString("gone.mkv doesn't exist."));
        // Nothing of the last file stays: its subtitles, its card, its picture.
        QCOMPARE(backend.subtitleText(), QString());
        QCOMPARE(backend.info().first().toMap().value("value").toString(), QString("gone.mkv"));
        QVERIFY(!backend.currentFrame().isValid());
        QVERIFY(!backend.next());
        QVERIFY(backend.previous());
        QCOMPARE(backend.fileName(), QString("clip.mkv"));
        backend.close();
    }

    void mprisAnswersOnItsOwnName() {
        // A private bus, so the test player never shows in the desktop's bar.
        QProcess daemon;
        daemon.start("dbus-daemon", {"--session", "--nofork", "--print-address"});
        QVERIFY2(daemon.waitForReadyRead(5000), "dbus-daemon is needed for this test");
        const QString address = QString::fromUtf8(daemon.readLine()).trimmed();
        {
            QDBusConnection bus = QDBusConnection::connectToBus(address, "omaview-test");
            QVERIFY(bus.isConnected());
            QTemporaryDir state;
            Backend::Options options;
            options.positionsPath = state.filePath("positions.json");
            options.audio = false;
            options.previews = false;
            Backend backend(options);
            Mpris mpris(&backend, nullptr, bus);
            // A window with nothing playing, or only pictures, isn't a player.
            QVERIFY(!mpris.registered());
            backend.open({m_picture});
            QVERIFY(!mpris.registered());
            backend.open({m_clip});
            QVERIFY(mpris.registered());
            QCOMPARE(mpris.service(),
                     QString("org.mpris.MediaPlayer2.omaview.instance%1").arg(QCoreApplication::applicationPid()));
            QTRY_VERIFY_WITH_TIMEOUT(backend.playing(), 10000);
            QCOMPARE(mpris.playbackStatus(), QString("Playing"));
            QTRY_COMPARE(mpris.metadata().value("xesam:title").toString(), QString("clip.mkv"));
            QVERIFY(mpris.metadata().value("mpris:length").toLongLong() > 9000000);

            // A second connection plays the part of playerctl, asynchronously,
            // since this thread is also the one that answers.
            QDBusConnection client = QDBusConnection::connectToBus(address, "omaview-client");
            auto send = [&](const QString &interface, const QString &method, const QVariantList &arguments = {}) {
                QDBusMessage message = QDBusMessage::createMethodCall(mpris.service(), "/org/mpris/MediaPlayer2",
                                                                      interface, method);
                message.setArguments(arguments);
                QDBusPendingCall pending = client.asyncCall(message);
                // One that never finishes shows in the checks on what it did.
                (void)QTest::qWaitFor([&] { return pending.isFinished(); }, 5000);
                return pending;
            };
            const QString player = "org.mpris.MediaPlayer2.Player";
            send(player, "Pause");
            QTRY_VERIFY(!backend.playing());
            QDBusPendingCall status = send("org.freedesktop.DBus.Properties", "Get", {player, QString("PlaybackStatus")});
            QVERIFY2(!status.isError(), qPrintable(status.error().message()));
            QCOMPARE(status.reply().arguments().value(0).value<QDBusVariant>().variant().toString(), QString("Paused"));
            send(player, "PlayPause");
            QTRY_VERIFY(backend.playing());
            send(player, "Seek", {qlonglong(-1000000)});
            QVERIFY(backend.position() < 1000);
            // Stop is stopped, not paused, as the specification has it.
            send(player, "Stop");
            QCOMPARE(mpris.playbackStatus(), QString("Stopped"));
            QCOMPARE(backend.position(), qint64(0));
            send(player, "Play");
            QTRY_VERIFY(backend.playing());
            QCOMPARE(mpris.playbackStatus(), QString("Playing"));
            QDBusConnection::disconnectFromBus("omaview-client");
            backend.close();
        }
        QDBusConnection::disconnectFromBus("omaview-test");
        daemon.kill();
        daemon.waitForFinished();
    }

    void themeFallsBack() {
        QTemporaryDir dir;
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QColor("#FFD60A"));
        QCOMPARE(theme.accentForeground(), QColor("black"));
        QVERIFY(!theme.light());
        QCOMPARE(theme.radius(), 0);
    }

    void themeReadsThePalette() {
        QTemporaryDir dir;
        QVERIFY(QDir(dir.path()).mkpath("theme"));
        QVERIFY(write(dir.path() + "/theme/colors.toml", "mode = \"light\"\n"
                                                         "theme_type = \"dark\"\n"
                                                         "accent = \"#112233\"\n"
                                                         "bg = #fafafa # paper\n"
                                                         "foreground = '#202020'\n"
                                                         "color1 = \"#aa0000\"\n"));

        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QColor("#112233"));
        QCOMPARE(theme.accentForeground(), QColor("white"));
        QCOMPARE(theme.background(), QColor("#fafafa"));
        QCOMPARE(theme.foreground(), QColor("#202020"));
        QCOMPARE(theme.colors().value("red").value<QColor>(), QColor("#aa0000"));
        QVERIFY(theme.light());
    }

    void themeAsksHyprlandAgainOnlyWhenItReloads() {
        // The fake Hyprland lives outside the theme directory, whose changes
        // the Theme also follows.
        QTemporaryDir dir, hypr;
        const QString command = fakeHyprctl(hypr.path());
        QVERIFY(write(hypr.filePath("response.json"), "{\"int\":4}"));
        QLocalServer events;
        QVERIFY(events.listen(hypr.filePath("events.sock")));

        // Once on start, and once more when the event socket connects.
        Theme theme(dir.path(), nullptr, command, events.fullServerName());
        QTRY_VERIFY(events.hasPendingConnections());
        QLocalSocket *hyprland = events.nextPendingConnection();
        QTRY_COMPARE(lines(hypr.filePath("calls")), 2);
        QTRY_COMPARE(theme.radius(), 4);

        QVERIFY(write(hypr.filePath("response.json"), "{\"int\":10}"));
        QTest::qWait(300);
        QCOMPARE(lines(hypr.filePath("calls")), 2);
        // Events arrive in pieces; only a whole configreloaded line counts.
        hyprland->write("activewindow>>kitty,~\nconfigrel");
        hyprland->flush();
        QTest::qWait(100);
        QCOMPARE(lines(hypr.filePath("calls")), 2);
        hyprland->write("oaded>>\n");
        QTRY_COMPARE(theme.radius(), 10);
        QCOMPARE(lines(hypr.filePath("calls")), 3);
    }

    void themeReachesHyprlandOnceItListens() {
        QTemporaryDir dir, hypr;
        const QString command = fakeHyprctl(hypr.path());
        QVERIFY(write(hypr.filePath("response.json"), "{\"int\":4}"));
        Theme theme(dir.path(), nullptr, command, hypr.filePath("events.sock"));
        QTRY_COMPARE(theme.radius(), 4);

        QVERIFY(write(hypr.filePath("response.json"), "{\"int\":8}"));
        QLocalServer events;
        QVERIFY(events.listen(hypr.filePath("events.sock")));
        QTRY_VERIFY_WITH_TIMEOUT(events.hasPendingConnections(), 5000);
        QTRY_COMPARE(theme.radius(), 8);
    }

    void translatorFallsBackToEnglish() {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("en"));
        QVERIFY(translator.translate("Main", "Save").isNull());
    }

    void translatorFollowsTheLanguageFile() {
        QTemporaryDir dir;
        QVERIFY(write(dir.path() + "/language", "pt-BR\n"));
        QVERIFY(write(dir.path() + "/pt.json", R"({"Save": "Guardar", "Open": "Abrir"})"));
        QVERIFY(write(dir.path() + "/pt-BR.json", R"({"Save": "Salvar"})"));

        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("pt-BR"));
        QCOMPARE(translator.translate("Main", "Save"), QString("Salvar"));
        QCOMPARE(translator.translate("Main", "Open"), QString("Abrir"));
        QVERIFY(translator.translate("Main", "Quit").isNull());
    }

    void translatorSeesAFirstPick() {
        // Before the first pick there is no ~/.config/omarchy to watch.
        QTemporaryDir dir;
        QVERIFY(write(dir.path() + "/da.json", R"({"Save": "Gem"})"));
        Translator translator(dir.path() + "/omarchy/language", dir.path());
        QVERIFY(QDir(dir.path()).mkpath("omarchy"));
        QVERIFY(write(dir.path() + "/omarchy/language", "da\n"));
        QTRY_COMPARE(translator.translate("Main", "Save"), QString("Gem"));
    }

    void translatorPicksPluralForms() {
        QTemporaryDir dir;
        QVERIFY(write(dir.path() + "/language", "ru\n"));
        QVERIFY(write(dir.path() + "/en.json", R"({"%n clips": {"one": "%n clip", "other": "%n clips"},
                                                   "%n files": {"one": "%n file", "other": "%n files"}})"));
        QVERIFY(write(dir.path() + "/ru.json", R"({"%n clips": {"one": "%n клип", "few": "%n клипа", "many": "%n клипов", "other": "%n клипа"}})"));

        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 21), QString("%n клип"));
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 22), QString("%n клипа"));
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 25), QString("%n клипов"));
        // An untranslated counted string falls back to English, with English rules.
        QCOMPARE(translator.translate("Main", "%n files", nullptr, 21), QString("%n files"));
    }

    void englishCatalogListsEveryString() {
        // en.json is what translators work from: every text the sources
        // translate is in it, as itself or, when counted, as its English
        // plural forms, and nothing else is.
        const QString sources = QFileInfo(QFINDTESTDATA("../src/Main.qml")).absolutePath();
        QStringList problems;
        const QMap<QString, bool> used = translatables(sources, &problems);
        const QJsonObject english = readCatalog(sources + "/i18n/en.json");
        for (auto it = used.begin(); it != used.end(); ++it) {
            const QJsonValue value = english.value(it.key());
            if (value.isUndefined())
                problems << "missing from en.json: " + it.key();
            else if (it.value() && (value.toObject().keys() != QStringList{"one", "other"}
                                    || value.toObject().value("other").toString() != it.key()))
                problems << "counted, so needs its one and other forms: " + it.key();
            else if (!it.value() && value.toString() != it.key())
                problems << "should be itself: " + it.key();
        }
        for (const QString &key : english.keys())
            if (!used.contains(key))
                problems << "in en.json but no source translates it: " + key;
        QVERIFY2(problems.isEmpty(), qPrintable(problems.join('\n')));
    }

    void catalogsMatchTheEnglishOne() {
        // A catalog may lack a string (it shows in English meanwhile), but what
        // it has translates something in en.json, with the same placeholders,
        // and a counted string has every form its language uses.
        const QString folder = QFileInfo(QFINDTESTDATA("../src/i18n/en.json")).absolutePath();
        const QJsonObject english = readCatalog(folder + "/en.json");
        QStringList problems;
        for (const QFileInfo &file : QDir(folder).entryInfoList({"*.json"}, QDir::Files)) {
            const QString code = file.completeBaseName();
            const QJsonObject catalog = readCatalog(file.filePath());
            if (catalog.isEmpty())
                problems << code + ": not a JSON object, or empty";
            // Some languages reach a form only at a million ("many" in French).
            QSet<QString> categories{"other", Translator::pluralCategory(code, 1000000)};
            for (long long n = 0; n <= 1000; ++n)
                categories << Translator::pluralCategory(code, n);
            for (auto it = catalog.begin(); it != catalog.end(); ++it) {
                const QString where = code + ": " + it.key() + ": ";
                const QJsonValue source = english.value(it.key());
                if (source.isUndefined()) {
                    problems << where + "not in en.json";
                } else if (source.isString()) {
                    if (!it.value().isString() || it.value().toString().isEmpty())
                        problems << where + "needs a translation";
                    else if (placeholders(it.value().toString()) != placeholders(it.key()))
                        problems << where + "has other placeholders than the English";
                } else {
                    const QJsonObject forms = it.value().toObject();
                    const QStringList wanted = placeholders(source.toObject().value("other").toString());
                    for (const QString &category : categories)
                        if (forms.value(category).toString().isEmpty())
                            problems << where + "needs its " + category + " form";
                    // A form other than "other" may say its number in words.
                    for (auto form = forms.begin(); form != forms.end(); ++form) {
                        const QStringList has = placeholders(form.value().toString());
                        QStringList needed = wanted;
                        if (form.key() != "other")
                            needed.removeIf([&](const QString &p) { return p.endsWith('n') && !has.contains(p); });
                        if (has != needed)
                            problems << where + form.key() + " has other placeholders than the English";
                    }
                }
            }
        }
        QVERIFY2(problems.isEmpty(), qPrintable(problems.join('\n')));
    }

};

QTEST_MAIN(OmaviewTests)
#include "omaview_tests.moc"
