// cards — Klondike solitaire in four card series.

#include <QElapsedTimer>
#include <QGuiApplication>
#include <QIcon>
#include <QLocalServer>
#include <QLocalSocket>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QThread>
#include <QUrl>
#include <iostream>

#include "backend.h"
#include "cli.h"
#include "theme.h"
#include "translator.h"

int main(int argc, char *argv[]) {
    const std::string command = argc > 1 ? argv[1] : "open";
    if (command == "--help") {
      std::cout << "Cards — Klondike solitaire\nUsage: cards [open | inspect | deal [SEED] | --help]\nHeadless commands accept --json. inspect prints the saved game; deal prints a fresh one.\n";
      return 0;
    }
    if (command == "inspect" || command == "deal") return runCli(argc, argv);
    if (command != "open" || argc > 2) { std::cerr << "Unknown command. Use cards --help.\n"; return 1; }
    QGuiApplication app(argc, argv);
    app.setApplicationName("cards");

    // Matches the window to cards.desktop, so the compositor (Wayland app_id)
    // and the launcher pick up the installed icon. The compiled-in copy covers
    // a run from build/, and needs qt6-svg's icon engine.
    app.setDesktopFileName("cards");
    app.setWindowIcon(QIcon::fromTheme("cards", QIcon(":/cards.svg")));

    QQuickStyle::setStyle("Material");

    // Installed before anything is translated, and every qsTr() binding is
    // re-evaluated when the Omarchy language changes.
    Translator translator;
    app.installTranslator(&translator);

    Theme theme;
    // A second launch brings the game already running forward, rather than
    // opening a second writer of the same save.
    const QString socketName = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + "/cards.sock";
    QLocalSocket existing;
    existing.connectToServer(socketName);
    if (existing.waitForConnected(100)) return 0;

    Backend backend;
    if (!backend.ownsSave()) {
      QElapsedTimer startup;
      startup.start();
      while (startup.elapsed() < 2000) {
        existing.abort(); existing.connectToServer(socketName);
        if (existing.waitForConnected(100)) return 0;
        QThread::msleep(50);
      }
      std::cerr << backend.error().toStdString() << "\n";
      return 1;
    }
    QLocalServer server;
    server.setSocketOptions(QLocalServer::UserAccessOption);
    QLocalServer::removeServer(socketName);
    if (!server.listen(socketName)) { std::cerr << server.errorString().toStdString() << "\n"; return 1; }

    QQmlApplicationEngine engine;
    QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
    engine.rootContext()->setContextProperty("translator", &translator);
    engine.rootContext()->setContextProperty("theme", &theme);
    engine.rootContext()->setContextProperty("backend", &backend);
    engine.load(QUrl("qrc:/Main.qml"));
    if (engine.rootObjects().isEmpty())
        return 1;

    QObject::connect(&server, &QLocalServer::newConnection, &app, [&] {
      while (auto connection = server.nextPendingConnection()) {
        connection->disconnectFromServer(); connection->deleteLater();
      }
      auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
      if (window) { window->showNormal(); window->raise(); window->requestActivate(); }
    });
    return app.exec();
}
