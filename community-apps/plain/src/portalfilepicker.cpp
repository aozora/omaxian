// From Omacut's portal file picker (MIT, David Heinemeier Hansson), without the
// video filters and export choices.
#include "portalfilepicker.h"

#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QFileInfo>
#include <QRandomGenerator>

namespace {
const QString PortalService = QStringLiteral("org.freedesktop.portal.Desktop");

// Messages built and sent as they are. A QDBusInterface would first ask the
// portal to describe itself, a blocking call that freezes Plain for as long
// as a hung portal doesn't answer.
QDBusMessage portalCall(const QString &path, const QString &interface, const QString &method) {
    return QDBusMessage::createMethodCall(PortalService, path, interface, method);
}

QString portalToken() {
    return QStringLiteral("plain_%1").arg(QRandomGenerator::global()->generate());
}

// The portal takes folders as NUL-terminated byte strings.
QByteArray portalPathBytes(const QString &path) {
    QByteArray bytes = path.toUtf8();
    bytes.append('\0');
    return bytes;
}
}

void PortalFilePicker::openFile(const QString &folder) {
    QVariantMap options;
    options.insert(QStringLiteral("accept_label"), tr("Open"));
    options.insert(QStringLiteral("modal"), true);
    options.insert(QStringLiteral("multiple"), false);
    options.insert(QStringLiteral("current_folder"),
                   portalPathBytes(QDir(folder).exists() ? folder : QDir::homePath()));
    requestFile(QStringLiteral("OpenFile"), tr("Open File"), options, Action::Open);
}

void PortalFilePicker::saveFile(const QString &suggestedPath) {
    const QFileInfo target(suggestedPath.isEmpty() ? QDir::homePath() + "/untitled.txt" : suggestedPath);
    QVariantMap options;
    options.insert(QStringLiteral("accept_label"), tr("Save"));
    options.insert(QStringLiteral("modal"), true);
    options.insert(QStringLiteral("current_folder"), portalPathBytes(target.absolutePath()));
    options.insert(QStringLiteral("current_name"), target.fileName());
    requestFile(QStringLiteral("SaveFile"), tr("Save As"), options, Action::Save);
}

bool PortalFilePicker::connectToRequestPath(const QString &path) {
    m_pendingPath = path;
    return m_bus.connect(
        QStringLiteral("org.freedesktop.portal.Desktop"), m_pendingPath,
        QStringLiteral("org.freedesktop.portal.Request"), QStringLiteral("Response"),
        this, SLOT(handleResponse(uint,QVariantMap)));
}

void PortalFilePicker::closePendingRequest() {
    if (m_pendingPath.isEmpty())
        return;
    m_bus.send(
        portalCall(m_pendingPath, QStringLiteral("org.freedesktop.portal.Request"), QStringLiteral("Close")));
}

void PortalFilePicker::requestFile(const QString &method, const QString &title,
                                   QVariantMap options, Action action) {
    // A request whose Response never arrives (the portal crashed or was
    // killed with the dialog up) must not wedge every later dialog behind
    // it: close the stuck one best-effort and replace it.
    if (m_pendingAction != Action::None) {
        closePendingRequest();
        clearPending();
    }

    QDBusConnection bus = m_bus;
    if (!bus.isConnected()) {
        emit failed(tr("The desktop's file chooser (xdg-desktop-portal) is not available."));
        return;
    }

    // Subscribe to the Response signal at the request path the portal will
    // derive from our handle_token *before* making the call, so a response
    // can't slip past while our match rule is still being installed.
    const QString token = portalToken();
    options.insert(QStringLiteral("handle_token"), token);
    QString sender = bus.baseService().mid(1);
    sender.replace(QLatin1Char('.'), QLatin1Char('_'));
    const QString predictedPath =
        QStringLiteral("/org/freedesktop/portal/desktop/request/%1/%2").arg(sender, token);

    m_pendingAction = action;
    if (!connectToRequestPath(predictedPath)) {
        clearPending();
        emit failed(tr("Could not listen for the file chooser's answer."));
        return;
    }

    const int generation = ++m_pendingGeneration;
    QDBusMessage call = portalCall(QStringLiteral("/org/freedesktop/portal/desktop"),
                                   QStringLiteral("org.freedesktop.portal.FileChooser"), method);
    call << QString() << title << options;
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(call), this);
    m_pendingWatcher = watcher;

    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher, generation]() {
        QDBusPendingReply<QDBusObjectPath> reply = *watcher;
        watcher->deleteLater();
        if (m_pendingWatcher == watcher)
            m_pendingWatcher = nullptr;

        // Superseded by a newer request, or a response may already have
        // been handled while the reply was in flight.
        if (generation != m_pendingGeneration || m_pendingAction == Action::None)
            return;

        if (reply.isError()) {
            clearPending();
            // No portal on the bus at all, rather than one that failed.
            const QDBusError::ErrorType type = reply.error().type();
            if (type == QDBusError::ServiceUnknown || type == QDBusError::UnknownObject
                || type == QDBusError::UnknownInterface)
                emit failed(tr("The desktop's file chooser (xdg-desktop-portal) is not available."));
            else
                emit failed(tr("The file chooser failed: %1").arg(reply.error().message()));
            return;
        }

        // Old portal versions can hand back a different request path than the
        // handle_token predicts; move our subscription over if so.
        const QString actualPath = reply.value().path();
        if (actualPath != m_pendingPath) {
            m_bus.disconnect(
                QStringLiteral("org.freedesktop.portal.Desktop"), m_pendingPath,
                QStringLiteral("org.freedesktop.portal.Request"), QStringLiteral("Response"),
                this, SLOT(handleResponse(uint,QVariantMap)));
            if (!connectToRequestPath(actualPath)) {
                clearPending();
                emit failed(tr("Could not listen for the file chooser's answer."));
            }
        }
    });
}

void PortalFilePicker::handleResponse(uint response, const QVariantMap &results) {
    const Action action = m_pendingAction;
    clearPending();
    const QStringList uris = results.value(QStringLiteral("uris")).toStringList();
    if (response != 0 || uris.isEmpty()) {
        emit cancelled();
        return;
    }

    const QUrl url(uris.first());
    if (action == Action::Open)
        emit openSelected(url);
    else if (action == Action::Save)
        emit saveSelected(url);
}

void PortalFilePicker::clearPending() {
    // A caller that never gets its reply must not outlive the request it
    // belonged to (repeated stuck requests would otherwise pile them up).
    if (m_pendingWatcher) {
        m_pendingWatcher->deleteLater();
        m_pendingWatcher = nullptr;
    }
    if (!m_pendingPath.isEmpty()) {
        m_bus.disconnect(
            QStringLiteral("org.freedesktop.portal.Desktop"), m_pendingPath,
            QStringLiteral("org.freedesktop.portal.Request"), QStringLiteral("Response"),
            this, SLOT(handleResponse(uint,QVariantMap)));
    }
    m_pendingPath.clear();
    m_pendingAction = Action::None;
}
