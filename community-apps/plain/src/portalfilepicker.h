#pragma once

#include <QObject>
#include <QUrl>
#include <QVariantMap>

class QDBusPendingCallWatcher;

// The open and save dialogs through xdg-desktop-portal's FileChooser, so they
// are the desktop's own. From Omacut (MIT, David Heinemeier Hansson).
class PortalFilePicker : public QObject {
    Q_OBJECT

public:
    explicit PortalFilePicker(QObject *parent = nullptr) : QObject(parent) {}

    // Invokable, since QML's Ctrl+O and Ctrl+S call them.
    Q_INVOKABLE void openFile(const QString &folder);
    Q_INVOKABLE void saveFile(const QString &suggestedPath);

signals:
    void openSelected(const QUrl &url);
    void saveSelected(const QUrl &url);
    // The dialog was dismissed without choosing a file.
    void cancelled();
    void failed(const QString &message);

private slots:
    void handleResponse(uint response, const QVariantMap &results);

private:
    enum class Action { None, Open, Save };

    void requestFile(const QString &method, const QString &title, QVariantMap options, Action action);
    bool connectToRequestPath(const QString &path);
    void clearPending();
    // Best-effort Close of the pending portal request, if there is one.
    void closePendingRequest();

    QString m_pendingPath;
    Action m_pendingAction = Action::None;
    // Bumped per request, so a late reply for a replaced request is ignored.
    int m_pendingGeneration = 0;
    QDBusPendingCallWatcher *m_pendingWatcher = nullptr;
};
