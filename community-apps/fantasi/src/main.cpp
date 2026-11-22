// fantasi — make images with a local model, as Omarchy runs them.

#include <QGuiApplication>
#include <QIcon>
#include <QJsonObject>
#include <QKeySequence>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QSettings>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>

#include "backend.h"
#include "instance.h"
#include "cli.h"
#include "theme.h"
#include "translator.h"

int main(int argc, char *argv[]) {
    // A command needs no window, so no display either, even where the desktop
    // exports QT_QPA_PLATFORM=wayland.
    const bool command = isCliCommand(argc, argv);
    if (command)
        qputenv("QT_QPA_PLATFORM", "offscreen");

    // Controls only follow the pointer where the platform asks for hover
    // effects, which Wayland doesn't, and without it no tooltip ever shows.
    qputenv("QT_QUICK_CONTROLS_HOVER_ENABLED", "1");

    QGuiApplication app(argc, argv);
    app.setApplicationName("fantasi");
    // Settings (the model used last) live in ~/.config/fantasi/.
    app.setOrganizationName("fantasi");
    if (command)
        return runCli(app.arguments());

    // Matches the window to fantasi.desktop, so the compositor (Wayland app_id)
    // and the launcher pick up the installed icon. The compiled-in copy covers
    // a run from build/, and needs qt6-svg's icon engine.
    app.setDesktopFileName("fantasi");
    app.setWindowIcon(QIcon::fromTheme("fantasi", QIcon(":/fantasi.svg")));

    QQuickStyle::setStyle("Material");

    // Installed before anything is translated, and every qsTr() binding is
    // re-evaluated when the Omarchy language changes.
    Translator translator;
    app.installTranslator(&translator);

    // `fantasi open "a calm lake"` starts with that prompt, and
    // `--model <id>` with that model, as the agents panel opens it: the
    // model to prefer is set before the models are first read.
    QStringList words = app.arguments().value(1) == "open" ? app.arguments().mid(2) : QStringList();
    QString modelId;
    if (const qsizetype model = words.indexOf("--model"); model >= 0 && model + 1 < words.size()) {
        modelId = words.at(model + 1);
        words.remove(model, 2);
    }
    const QString initialPrompt = words.join(' ');

    // With a window already open, it takes the model and the prompt and comes
    // to the front, rather than a second one opening. A window drawn offscreen
    // (to be looked at, or tested) stays apart from the user's.
    const bool offscreen = app.platformName() == "offscreen";
    Instance instance;
    if (!offscreen && instance.handOver({{"model", modelId}, {"prompt", initialPrompt}})) {
        // Omaxian: i3, not Hyprland (no omarchy-launch-or-focus).
        QProcess::startDetached("i3-msg", {"[class=\"(?i)^fantasi$\"] focus"});
        return 0;
    }

    Theme theme;
    Backend backend;
    backend.setInitialPrompt(initialPrompt);
    QObject::connect(&instance, &Instance::requested, &backend, [&backend](const QJsonObject &request) {
        backend.open(request.value("model").toString(), request.value("prompt").toString());
    });

    QQmlApplicationEngine engine;
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    engine.rootContext()->setContextProperty("translator", &translator);
    engine.rootContext()->setContextProperty("theme", &theme);
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return 1;
    // The model asked for, once the models are known: an image model to use,
    // or the video model to make clips with.
    if (!modelId.isEmpty())
        backend.open(modelId, {});

    // `omarchy agent look app` runs the app offscreen with these set, to see
    // the window without a display: size it to OMARCHY_LOOK_SIZE when given,
    // press the keys in OMARCHY_LOOK_KEYS through the window's Shortcuts,
    // save it once it has settled, and quit.
    if (const QString shot = qEnvironmentVariable("OMARCHY_LOOK_SCREENSHOT"); !shot.isEmpty()) {
        const QStringList size = qEnvironmentVariable("OMARCHY_LOOK_SIZE").split('x');
        if (auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst()); window && size.size() == 2)
            window->resize(size[0].toInt(), size[1].toInt());
        const QStringList keys = qEnvironmentVariable("OMARCHY_LOOK_KEYS").split(' ', Qt::SkipEmptyParts);
        for (int i = 0; i < keys.size(); ++i) {
            QTimer::singleShot(800 + i * 300, &app, [&engine, key = QKeySequence(keys[i])] {
                for (QObject *shortcut : engine.rootObjects().constFirst()->findChildren<QObject *>()) {
                    if (qstrcmp(shortcut->metaObject()->className(), "QQuickShortcut") == 0
                        && shortcut->property("enabled").toBool()
                        && QKeySequence(shortcut->property("sequence").toString()) == key) {
                        QMetaObject::invokeMethod(shortcut, "activated");
                        break;
                    }
                }
            });
        }
        const int delay = qEnvironmentVariableIsSet("OMARCHY_LOOK_DELAY_MS") ? qEnvironmentVariableIntValue("OMARCHY_LOOK_DELAY_MS") : 1500;
        QTimer::singleShot(800 + keys.size() * 300 + delay, &app, [&engine, shot] {
            if (auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst()))
                window->grabWindow().save(shot);
            QCoreApplication::quit();
        });
    }

    return app.exec();
}
