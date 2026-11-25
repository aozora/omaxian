#include "probe.h"

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLocale>
#include <QProcess>
#include <QStandardPaths>

#include "texts.h"

namespace probe {

namespace {

double rate(const QString &fraction) {
    const auto parts = fraction.split('/');
    if (parts.size() != 2)
        return fraction.toDouble();
    const double denominator = parts.at(1).toDouble();
    return denominator > 0 ? parts.at(0).toDouble() / denominator : 0;
}

QString tag(const QJsonObject &object, const char *name) {
    const QJsonObject tags = object.value("tags").toObject();
    // Containers spell tag names in either case (TITLE in Matroska).
    for (auto it = tags.begin(); it != tags.end(); ++it)
        if (it.key().compare(QLatin1String(name), Qt::CaseInsensitive) == 0)
            return it.value().toString().trimmed();
    return {};
}

}  // namespace

bool Stream::textSubtitle() const {
    static const QStringList text{"subrip", "srt", "ass", "ssa", "webvtt", "mov_text", "text", "microdvd",
                                  "subviewer", "subviewer1", "realtext", "sami", "stl", "jacosub", "mpl2",
                                  "pjs", "vplayer", "eia_608"};
    return type == "subtitle" && text.contains(codec);
}

QList<Stream> Info::ofType(const QString &type) const {
    QList<Stream> found;
    for (const Stream &stream : streams)
        if (stream.type == type && !(type == "video" && stream.attachedPicture))
            found << stream;
    return found;
}

const Stream *Info::video() const {
    for (const Stream &stream : streams)
        if (stream.type == "video" && !stream.attachedPicture)
            return &stream;
    return nullptr;
}

QString toolPath(const QString &name) {
    return QStandardPaths::findExecutable(name);
}

Info parse(const QByteArray &json, const QString &path) {
    Info info;
    info.path = path;
    QJsonParseError parseError;
    const QJsonObject root = QJsonDocument::fromJson(json, &parseError).object();
    if (parseError.error != QJsonParseError::NoError || root.isEmpty()) {
        info.error = Texts::tr("ffprobe gave an answer that could not be read.");
        return info;
    }
    const QJsonObject format = root.value("format").toObject();
    info.format = format.value("format_long_name").toString();
    info.title = tag(format, "title");
    info.artist = tag(format, "artist");
    info.duration = format.value("duration").toString().toDouble();
    info.size = format.value("size").toString().toLongLong();
    info.bitRate = format.value("bit_rate").toString().toLongLong();

    for (const QJsonValue &value : root.value("streams").toArray()) {
        const QJsonObject object = value.toObject();
        Stream stream;
        stream.index = object.value("index").toInt(-1);
        stream.type = object.value("codec_type").toString();
        stream.codec = object.value("codec_name").toString();
        stream.language = tag(object, "language");
        if (stream.language == "und")
            stream.language.clear();
        stream.title = tag(object, "title");
        stream.width = object.value("width").toInt();
        stream.height = object.value("height").toInt();
        for (const QJsonValue &data : object.value("side_data_list").toArray())
            if (data["rotation"].isDouble())
                stream.rotation = data["rotation"].toInt();
        stream.frameRate = rate(object.value("avg_frame_rate").toString());
        if (stream.frameRate <= 0)
            stream.frameRate = rate(object.value("r_frame_rate").toString());
        stream.channels = object.value("channels").toInt();
        stream.channelLayout = object.value("channel_layout").toString();
        const QJsonObject disposition = object.value("disposition").toObject();
        stream.isDefault = disposition.value("default").toInt() != 0;
        stream.attachedPicture = disposition.value("attached_pic").toInt() != 0;
        if (!stream.type.isEmpty())
            info.streams << stream;
    }

    for (const QJsonValue &value : root.value("chapters").toArray()) {
        const QJsonObject object = value.toObject();
        Chapter chapter;
        chapter.start = object.value("start_time").toString().toDouble();
        chapter.end = object.value("end_time").toString().toDouble();
        chapter.title = tag(object, "title");
        info.chapters << chapter;
    }
    return info;
}

Info run(const QString &path, int timeoutMs, const std::atomic_bool *cancelled) {
    Info info;
    info.path = path;
    if (cancelled && *cancelled) {
        info.error = Texts::tr("ffprobe took too long reading this file.");
        return info;
    }
    const QString ffprobe = toolPath("ffprobe");
    if (ffprobe.isEmpty()) {
        info.error = Texts::tr("ffprobe was not found. Install ffmpeg.");
        info.missingTool = true;
        return info;
    }
    QProcess process;
    process.start(ffprobe, {"-v", "error", "-print_format", "json", "-show_format", "-show_streams",
                            "-show_chapters", "--", path});
    if (!process.waitForStarted(5000)) {
        info.error = Texts::tr("ffprobe could not be started.");
        return info;
    }
    QElapsedTimer clock;
    clock.start();
    // In slices, so a file that is no longer wanted stops its ffprobe.
    while (!process.waitForFinished(100) && process.state() != QProcess::NotRunning) {
        if ((cancelled && *cancelled) || clock.elapsed() > timeoutMs) {
            process.kill();
            process.waitForFinished(1000);
            info.error = Texts::tr("ffprobe took too long reading this file.");
            return info;
        }
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        const QString message = QString::fromUtf8(process.readAllStandardError()).trimmed().section('\n', -1);
        info.error = message.isEmpty() ? Texts::tr("ffprobe could not read this file.")
                                       : message;
        return info;
    }
    return parse(process.readAllStandardOutput(), path);
}

QString shortLanguage(const QString &code) {
    if (code.size() != 3)
        return code.toLower();
    // QLocale knows ISO 639-2/T codes; a few common files carry the /B
    // spellings, which differ.
    static const QHash<QString, QString> bibliographic{
        {"ger", "deu"}, {"fre", "fra"}, {"dut", "nld"}, {"chi", "zho"}, {"cze", "ces"}, {"gre", "ell"},
        {"per", "fas"}, {"rum", "ron"}, {"slo", "slk"}, {"ice", "isl"}, {"baq", "eus"}, {"arm", "hye"},
        {"geo", "kat"}, {"mac", "mkd"}, {"may", "msa"}, {"bur", "mya"}, {"tib", "bod"}, {"wel", "cym"},
        {"alb", "sqi"},
    };
    const QString terminology = bibliographic.value(code.toLower(), code.toLower());
    const QLocale::Language language = QLocale::codeToLanguage(terminology, QLocale::ISO639Part2);
    if (language == QLocale::AnyLanguage)
        return code.toLower();
    const QString two = QLocale::languageToCode(language, QLocale::ISO639Part1);
    return two.isEmpty() ? code.toLower() : two;
}

QString languageName(const QString &code) {
    if (code.isEmpty() || code == "und" || code == "zxx" || code == "mis" || code == "mul")
        return {};
    const QString two = shortLanguage(code);
    const QLocale::Language language = QLocale::codeToLanguage(two);
    if (language == QLocale::AnyLanguage || language == QLocale::C)
        return {};
    // In its own words ("Dansk", "Deutsch"), which is how a speaker of it
    // finds it in a list; Qt can't name one language in another's words.
    // English alone names its default region ("American English"), which a
    // track tagged only "eng" doesn't claim.
    QString name = language == QLocale::English ? QStringLiteral("English") : QLocale(language).nativeLanguageName();
    if (name.isEmpty())
        name = QLocale::languageToString(language);
    if (!name.isEmpty())
        name[0] = name[0].toUpper();
    return name;
}

QJsonObject Info::toJson() const {
    QJsonObject object{{"path", path}, {"format", format}, {"duration", duration},
                       {"size", size}, {"bitRate", bitRate}};
    if (!title.isEmpty())
        object.insert("title", title);
    if (!artist.isEmpty())
        object.insert("artist", artist);
    QJsonArray streamList;
    for (const Stream &stream : streams) {
        QJsonObject entry{{"index", stream.index}, {"type", stream.type}, {"codec", stream.codec}};
        if (!stream.language.isEmpty())
            entry.insert("language", stream.language);
        if (!stream.title.isEmpty())
            entry.insert("title", stream.title);
        if (stream.type == "video") {
            entry.insert("width", stream.width);
            entry.insert("height", stream.height);
            entry.insert("frameRate", stream.frameRate);
            if (stream.attachedPicture)
                entry.insert("coverArt", true);
        }
        if (stream.type == "audio") {
            entry.insert("channels", stream.channels);
            if (!stream.channelLayout.isEmpty())
                entry.insert("channelLayout", stream.channelLayout);
        }
        if (stream.type == "subtitle")
            entry.insert("text", stream.textSubtitle());
        if (stream.isDefault)
            entry.insert("default", true);
        streamList << entry;
    }
    object.insert("streams", streamList);
    QJsonArray chapterList;
    for (const Chapter &chapter : chapters)
        chapterList << QJsonObject{{"start", chapter.start}, {"end", chapter.end}, {"title", chapter.title}};
    object.insert("chapters", chapterList);
    return object;
}

}  // namespace probe
