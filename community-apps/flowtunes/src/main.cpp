// flowtunes — endless music in the genre you pick, made on this machine by a local model.

#include <QGuiApplication>
#include <QIcon>
#include <QKeySequence>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>

#include "backend.h"
#include "genres.h"
#include "theme.h"
#include "translator.h"

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    app.setOrganizationName("flowtunes");
    app.setApplicationName("flowtunes");

    // Matches the window to flowtunes.desktop, so the compositor (Wayland app_id)
    // and the launcher pick up the installed icon. The compiled-in copy covers
    // a run from build/, and needs qt6-svg's icon engine.
    app.setDesktopFileName("flowtunes");
    app.setWindowIcon(QIcon::fromTheme("flowtunes", QIcon(":/flowtunes.svg")));

    QQuickStyle::setStyle("Material");

    // Installed before anything is translated, and every qsTr() binding is
    // re-evaluated when the Omarchy language changes.
    Translator translator;
    app.installTranslator(&translator);

    Theme theme;
    Backend backend;
    // `flowtunes jazz` plays jazz from the start, by a genre's id or its name.
    if (const QString wanted = app.arguments().value(1); !wanted.isEmpty())
        for (const Genre &genre : Genres::all())
            if (genre.id.compare(wanted, Qt::CaseInsensitive) == 0 || genre.name.compare(wanted, Qt::CaseInsensitive) == 0)
                backend.setInitialGenre(genre.id);

    // Quitting stops the music models nothing else uses. A window drawn
    // offscreen leaves the user's models alone.
    if (app.platformName() != "offscreen")
        QObject::connect(&app, &QCoreApplication::aboutToQuit, &backend, [&backend] { backend.models()->release(); });

    QQmlApplicationEngine engine;
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    engine.rootContext()->setContextProperty("translator", &translator);
    engine.rootContext()->setContextProperty("theme", &theme);
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return 1;
    // The media keys reach it once the window is there to hear them.
    backend.mpris()->publish();

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
        QTimer::singleShot(800 + keys.size() * 300 + delay, &app, [&engine, &app, &backend, shot] {
            if (auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst()))
                window->grabWindow().save(shot);
            // A tune still being made is called off, and the model given a
            // moment to hear so, before the app goes.
            backend.flow()->stop();
            QTimer::singleShot(500, &app, &QCoreApplication::quit);
        });
    }

    return app.exec();
}
