#include "cli.h"

#include "backend.h"

#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QTimer>
#include <QUrl>
#include <cstdio>

namespace {

void print(FILE *stream, const QString &text) {
    std::fputs(qPrintable(text + '\n'), stream);
    std::fflush(stream);
}

const char *usage = "Usage:\n"
                    "  fantasi                      Open the window\n"
                    "  fantasi open [prompt] [--model <id>]\n"
                    "                               Open the window with a prompt, and a model\n"
                    "  fantasi generate <prompt>    Make an image, print where it's saved\n"
                    "      --from <image> --width <px> --height <px> --steps <n> --seed <n> --video --seconds <n> --json\n"
                    "      --music [--lyrics <text> | --instrumental] [--seconds <n>]\n"
                    "  fantasi skill [install]      Print the agent skill, or install it\n";

// As Hype does: one shared copy agents find in ~/.agents/skills, linked into
// Claude Code's skills when it is installed.
int skill(const QString &action) {
    QFile bundled(":/skill.md");
    if (!bundled.open(QIODevice::ReadOnly))
        return 1;
    const QByteArray text = bundled.readAll();
    if (action.isEmpty()) {
        std::fputs(text.constData(), stdout);
        return 0;
    }
    if (action != "install") {
        print(stderr, "Error: use fantasi skill to print the skill, or fantasi skill install.");
        return 1;
    }
    const QDir home = QDir::home();
    const QString directory = home.filePath(".agents/skills/fantasi");
    QSaveFile file(directory + "/SKILL.md");
    if (!QDir().mkpath(directory) || !file.open(QIODevice::WriteOnly) || file.write(text) < 0 || !file.commit()) {
        print(stderr, "Error: couldn't write " + file.fileName());
        return 1;
    }
    print(stdout, "Installed " + file.fileName());
    if (!home.exists(".claude"))
        return 0;
    const QString link = home.filePath(".claude/skills/fantasi");
    const QFileInfo existing(link);
    if (existing.isSymLink())
        QFile::remove(link);
    else if (existing.exists()) {
        print(stderr, "Error: " + link + " exists and is not a link; leaving it alone.");
        return 1;
    }
    if (!home.mkpath(".claude/skills") || !QFile::link("../../.agents/skills/fantasi", link)) {
        print(stderr, "Error: couldn't link " + link);
        return 1;
    }
    print(stdout, "Linked " + link);
    return 0;
}

} // namespace

bool isCliCommand(int argc, char *argv[]) {
    if (argc < 2)
        return false;
    const QByteArray command(argv[1]);
    // `open --help` asks for the usage, not for a window with that as its prompt.
    if (command == "open" && argc > 2)
        return QByteArray(argv[2]) == "--help" || QByteArray(argv[2]) == "-h";
    return command == "generate" || command == "skill" || command == "--help" || command == "-h";
}

int runCli(const QStringList &arguments) {
    const QString command = arguments.value(1);
    if (command == "skill")
        return skill(arguments.value(2));
    if (command != "generate") {
        print(stdout, usage);
        return 0;
    }

    QCommandLineParser parser;
    parser.addPositionalArgument("prompt", "What to make");
    parser.addOption({"width", "Width in pixels", "px", "1024"});
    parser.addOption({"height", "Height in pixels", "px", "1024"});
    parser.addOption({"steps", "Sampling steps; the model's own when left out", "n", "0"});
    parser.addOption({"seed", "Seed; a random one when left out", "n", "-1"});
    parser.addOption({"from", "Change this picture: the prompt says what to change. Give it again to combine pictures, with a model that edits", "image"});
    parser.addOption({"video", "Make a clip with its sound on the running video model; --from is its first frame"});
    parser.addOption({"music", "Make a song on the running music model: the prompt describes it"});
    parser.addOption({"lyrics", "The song's lyrics, with [verse] and [chorus] over their parts and \\n between lines; the model writes them when left out", "text"});
    parser.addOption({"instrumental", "A song without words"});
    parser.addOption({"seconds", "How long a clip is: 2, 5, 10, 15… as long as the video model makes here; or a song, a minute when left out", "n"});
    parser.addOption({"json", "Print the result as JSON"});
    // The parser takes its first argument as the program's name: here,
    // `generate`, which leaves the prompt as the positional arguments.
    if (!parser.parse(arguments.mid(1))) {
        print(stderr, "Error: " + parser.errorText());
        return 1;
    }
    const QString prompt = parser.positionalArguments().join(' ').trimmed();
    const bool json = parser.isSet("json");
    if (prompt.isEmpty()) {
        print(stderr, "Error: say what to make: fantasi generate \"a calm lake at dusk\"");
        return 1;
    }

    Backend backend;
    Models *models = backend.models();
    Generator *generator = backend.generator();
    if (models->state() != "ready") {
        const QString how = models->state() == "installed" || models->state() == "blocked"
                              ? " Start it with: omarchy-models start " + models->modelId()
                          : models->state() == "installable" ? " Set one up with: omarchy-models use " + models->modelId()
                                                             : QString();
        print(stderr, "Error: no image model is running." + how);
        return 1;
    }

    // The running model of the kind asked for: a music model for --music, a
    // video model for --video, an image model otherwise, whichever is the
    // one chosen in the window.
    const bool video = parser.isSet("video"), music = parser.isSet("music");
    // A clip's length is checked against what its model makes here once
    // the model is known, before minutes go into it.
    const int seconds = parser.isSet("seconds") ? parser.value("seconds").toInt()
                        : music ? Generator::defaultSongSeconds : Generator::defaultSeconds;

    int code = 1;
    QString path;
    QObject::connect(generator, &Generator::saved, [&path](const QString &saved) { path = saved; });
    auto done = [&] {
        code = 0;
        print(stdout, json ? QString::fromUtf8(QJsonDocument(QJsonObject{{"path", path}}).toJson(QJsonDocument::Compact)) : path);
        QCoreApplication::quit();
    };
    // A clip is done once its poster is beside it.
    QObject::connect(generator, &Generator::posterSaved, [&](const QString &clip) {
        path = clip;
        done();
    });
    QObject::connect(generator, &Generator::posterFailed, [&](const QString &error) {
        print(stderr, "Error: " + error);
        QCoreApplication::quit();
    });
    QObject::connect(generator, &Generator::finished, [&](const QString &error) {
        if (!error.isEmpty() || path.isEmpty()) {
            print(stderr, "Error: " + (error.isEmpty() ? QString("the image was cancelled") : error));
            QCoreApplication::quit();
        } else if (!path.endsWith(".webm") && !path.endsWith(".mp3")) {
            done();
        }
    });
    // Starts on the model's own defaults once they're known, or without them
    // after a moment.
    bool started = false;
    auto start = [&] {
        if (started)
            return;
        started = true;
        QStringList from;
        for (const QString &path : parser.values("from"))
            from << QUrl::fromLocalFile(QFileInfo(path).absoluteFilePath()).toString();
        // The running model of the kind asked for, whichever the window chose.
        const auto right = [&] { return models->video() == video && models->music() == music; };
        if (!right()) {
            for (const QVariant &choice : models->choices()) {
                const QVariantMap row = choice.toMap();
                if (row.value("video").toBool() == video && row.value("music").toBool() == music && row.value("running").toBool()) {
                    models->choose(row.value("id").toString());
                    break;
                }
            }
        }
        // None of that kind running: say so rather than send it to the wrong one.
        if (!right()) {
            print(stderr, QString("Error: no %1 model is running").arg(music ? "music" : video ? "video" : "image"));
            QCoreApplication::exit(1);
            return;
        }
        if (video && !models->clipLengths().contains(seconds)) {
            QStringList lengths;
            for (const QVariant &length : models->clipLengths())
                lengths << length.toString();
            print(stderr, QString("Error: --seconds takes %1 with %2 here").arg(lengths.join(", "), models->modelName()));
            QCoreApplication::exit(1);
            return;
        }
        if (music)
            generator->makeSong(prompt, parser.isSet("instrumental") ? QString("[Instrumental]") : parser.value("lyrics").replace("\\n", "\n"),
                                seconds);
        else if (video)
            generator->makeVideo(prompt, parser.value("width").toInt(), parser.value("height").toInt(), from.value(0), seconds);
        else
            generator->generate(prompt, parser.value("width").toInt(), parser.value("height").toInt(),
                                parser.value("steps").toInt(), parser.value("seed").toLongLong(), from, models->edits());
        if (!generator->busy()) {
            print(stderr, "Error: " + generator->error());
            QCoreApplication::exit(1);
        }
    };
    QObject::connect(generator, &Generator::defaultsChanged, start);
    QTimer::singleShot(3000, start);
    QCoreApplication::exec();
    return code;
}
