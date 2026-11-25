// Omaview — Omarchy's picture viewer and media player, Media Viewer in the launcher: open a picture, a video
// or a song and look at it, from the keyboard, with nothing on screen but the picture.

#include <QDir>
#include <QEventLoopLocker>
#include <QFileInfo>
#include <QPointer>
#include <QtConcurrent>
#include <cmath>
#include <memory>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QUrl>

#include "backend.h"
#include "cli.h"
#include "inhibit.h"
#include "mpris.h"
#include "playlist.h"
#include "probe.h"
#include "thumbnails.h"
#include "theme.h"
#include "translator.h"

int main(int argc, char *argv[]) {
    // QGuiApplication aborts without a display before it has seen its
    // arguments, so commands and --help decide that first.
    const QByteArray first = argc > 1 ? QByteArray(argv[1]) : QByteArray();
    const bool command = isCliCommand(QString::fromLocal8Bit(first));
    const bool help = first == "--help" || first == "-h";
    if (command || help)
        qputenv("QT_QPA_PLATFORM", "offscreen");

    QGuiApplication app(argc, argv);
    app.setApplicationName("omaview");

    if (command)
        return runCli(app.arguments());
    if (help)
        return runCli({app.arguments().first(), "help"});

    // Matches the window to omaview.desktop, so the compositor (Wayland
    // app_id) and the launcher pick up the installed icon. The compiled-in
    // copy covers a run from build/, and needs qt6-svg's icon engine.
    app.setDesktopFileName("omaview");
    app.setWindowIcon(QIcon::fromTheme("omaview", QIcon(":/omaview.svg")));

    QQuickStyle::setStyle("Material");

    // Installed before anything is translated, and every qsTr() binding is
    // re-evaluated when the Omarchy language changes.
    Translator translator;
    app.installTranslator(&translator);

    Theme theme;
    Backend backend;
    backend.setLanguage(translator.language());
    QObject::connect(&translator, &Translator::changed, &backend,
                     [&] { backend.setLanguage(translator.language()); });
    Mpris mpris(&backend);
    IdleInhibitor idle;

    QQmlApplicationEngine engine;
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    engine.rootContext()->setContextProperty("translator", &translator);
    engine.rootContext()->setContextProperty("theme", &theme);
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.rootContext()->setContextProperty("idle", &idle);
    // `omaview open a.mkv` and `omaview a.mkv`, which launchers use, alike.
    QStringList files = app.arguments().mid(1);
    if (!files.isEmpty() && files.first() == "open")
        files.removeFirst();
    // A picture never starts the player, so it opens before the window
    // shows, which then waits for it.
    const bool picture = !files.isEmpty() && playlist::picture(files.first());
    // A local video or song is measured first too, so the window opens at
    // its shape rather than at a default and then changing.
    const QUrl firstUrl = files.isEmpty() ? QUrl() : QUrl::fromUserInput(files.first(), QDir::currentPath(), QUrl::AssumeLocalFile);
    const bool folder = firstUrl.isLocalFile() && QFileInfo(firstUrl.toLocalFile()).isDir();
    const bool measure = !picture && !folder && firstUrl.isLocalFile();
    // A folder opens on its grid, at the size of its tiles, once it's listed.
    engine.setInitialProperties({{"opening", !files.isEmpty()}, {"holding", picture || measure || folder}});
    engine.addImageProvider("thumbnail", new ThumbnailProvider);
    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return 1;

    auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    idle.setWindow(window);
    // The player's frames share the window's GPU context, set on the render
    // thread as the scene graph starts and stops.
    QObject::connect(window, &QQuickWindow::sceneGraphInitialized, window,
                     [&backend, window] { backend.setRhi(window->rhi()); }, Qt::DirectConnection);
    QObject::connect(window, &QQuickWindow::sceneGraphInvalidated, window,
                     [&backend] { backend.setRhi(nullptr); }, Qt::DirectConnection);
    QObject::connect(&backend, &Backend::raiseRequested, window, [window] {
        window->show();
        window->raise();
        window->requestActivate();
    });
    QObject::connect(&app, &QCoreApplication::aboutToQuit, &backend, &Backend::close);

    // A video or a song opens once the window has drawn, since starting the
    // player probes the GPU's decoders on this thread. A picture, and a
    // folder, which is listed before its grid shows, open while it's hidden.
    if (picture || folder) {
        // Work in the background lets the app quit when it finishes with no
        // window showing, so the hidden window holds it until it shows (or goes).
        auto hold = std::make_shared<QEventLoopLocker>();
        QObject::connect(window, &QWindow::visibleChanged, window, [hold](bool visible) mutable {
            if (visible)
                hold.reset();
        });
        backend.open(files);
    }
    else if (!files.isEmpty())
        QObject::connect(window, &QQuickWindow::frameSwapped, &backend, [&backend, files] { backend.open(files); },
                         Qt::ConnectionType(Qt::QueuedConnection | Qt::SingleShotConnection));
    if (measure) {
        QPointer<QQuickWindow> target(window);
        (void)QtConcurrent::run([target, path = firstUrl.toLocalFile()] {
            const probe::Info info = probe::run(path, 3000);
            const probe::Stream *video = info.video();
            QSize size = video ? QSize(video->width, video->height) : QSize();
            if (video && std::abs(video->rotation) % 180 == 90)
                size.transpose();
            const bool song = info.ok() && !video;
            QMetaObject::invokeMethod(qApp, [target, size, song] {
                if (target)
                    QMetaObject::invokeMethod(target, "openAt", Q_ARG(QVariant, size.width()),
                                              Q_ARG(QVariant, size.height()), Q_ARG(QVariant, song));
            }, Qt::QueuedConnection);
        });
    }

    return app.exec();
}
