// checkmate — 3D chess for one or two players.

#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QUrl>

#include "backend.h"
#include "cli.h"
#include "sculptgeometry.h"
#include "surfacetexture.h"
#include <QQuick3D>
#include <iostream>
#include <QLocalServer>
#include <QLocalSocket>
#include <QStandardPaths>
#include <QQuickWindow>
#include <QElapsedTimer>
#include <QThread>
#include "theme.h"
#include "translator.h"

int main(int argc, char *argv[]) {
    const std::string command = argc > 1 ? argv[1] : "open";
    if (command == "--help" || command == "--version") {
      std::cout << (command == "--version" ? "Checkmate " CHECKMATE_VERSION "\n" : "Checkmate — 3D chess\nUsage: checkmate [open | inspect | export | legal [FEN] | --help | --version]\nHeadless commands accept --json. export prints PGN to stdout.\n");
      return 0;
    }
    if (command == "inspect" || command == "export" || command == "legal") return runCli(argc,argv);
    if (command != "open" || argc > 2) { std::cerr << "Unknown command. Use checkmate --help.\n"; return 1; }
    QGuiApplication app(argc, argv);
    QSurfaceFormat::setDefaultFormat(QQuick3D::idealSurfaceFormat());
    qmlRegisterType<SculptGeometry>("Checkmate", 1, 0, "SculptGeometry");
    qmlRegisterType<SurfaceTexture>("Checkmate",1,0,"SurfaceTexture");
    app.setApplicationName("checkmate");
    app.setApplicationVersion(CHECKMATE_VERSION);

    // Matches the window to checkmate.desktop, so the compositor (Wayland app_id)
    // and the launcher pick up the installed icon. The compiled-in copy covers
    // a run from build/, and needs qt6-svg's icon engine.
    app.setDesktopFileName("checkmate");
    app.setWindowIcon(QIcon::fromTheme("checkmate", QIcon(":/checkmate.svg")));

    // A second launch only brings the first forward, so that is settled before anything else is set up.
    const QString socketName = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + "/checkmate.sock";
    QLocalSocket existing;
    existing.connectToServer(socketName);
    if (existing.waitForConnected(100)) return 0;

    QQuickStyle::setStyle("Material");

    // Installed before anything is translated, and every qsTr() binding is
    // re-evaluated when the Omarchy language changes.
    Translator translator;
    app.installTranslator(&translator);

    Theme theme;
    Backend backend;
    if (!backend.ownsSave()) {
      // Another window may hold the save and be a moment from listening; give it that moment. A folder that
      // cannot be written has nobody to wait for.
      QElapsedTimer startup;
      startup.start();
      while (backend.saveContended() && startup.elapsed() < 2000) {
        existing.abort(); existing.connectToServer(socketName);
        if (existing.waitForConnected(100)) return 0;
        QThread::msleep(50);
      }
      // Nobody answered, so the save is simply out of reach. The window opens and says so, rather than a
      // launcher click that does nothing.
      std::cerr << backend.error().toStdString() << "\n";
    }
    QLocalServer server;
    server.setSocketOptions(QLocalServer::UserAccessOption);
    QLocalServer::removeServer(socketName);
    // Without the socket a second launch opens a window of its own, which the save lock keeps from writing.
    if (!server.listen(socketName)) { std::cerr << server.errorString().toStdString() << "\n"; backend.reportSocket(server.errorString()); }

    // Declared before the engine, so it is still there while the scene that borrows from it is torn down.
    Sculptures sculptures;
    QQmlApplicationEngine engine;
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    engine.rootContext()->setContextProperty("translator", &translator);
    engine.rootContext()->setContextProperty("theme", &theme);
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.rootContext()->setContextProperty("sculptures", &sculptures);
    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return 1;

    QObject::connect(&server,&QLocalServer::newConnection,&app,[&] {
      while (auto connection = server.nextPendingConnection()) {
        connection->disconnectFromServer(); connection->deleteLater();
      }
      auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
      if (window) { window->showNormal(); window->raise(); window->requestActivate(); }
    });
    return app.exec();
}
