#pragma once

// Follows Omacut's portal file picker (MIT, David Heinemeier Hansson).

#include <QVariantMap>

#include "filepicker.h"

class QDBusPendingCallWatcher;

// The open and save dialogs through xdg-desktop-portal's FileChooser.
class PortalFilePicker : public FilePicker {
    Q_OBJECT

public:
    explicit PortalFilePicker(QObject *parent = nullptr);

    void openImage() override;
    void saveImage(const QUrl &suggestedUrl) override;

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
    Action m_pending = Action::None;
    // Bumped per request, so a late reply for a replaced request is ignored.
    int m_pendingGeneration = 0;
    QDBusPendingCallWatcher *m_pendingWatcher = nullptr;
};
