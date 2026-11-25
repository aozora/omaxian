#pragma once

#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QSize>

#include "filepicker.h"
#include "generator.h"
#include "history.h"
#include "models.h"

// The app's state for the window: the model it uses, the image being made,
// the images made before, and what the desktop does with one.
class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(Models *models READ models CONSTANT)
    Q_PROPERTY(Generator *generator READ generator CONSTANT)
    Q_PROPERTY(History *history READ history CONSTANT)
    // The Screen size: the focused monitor's shape at about a megapixel.
    Q_PROPERTY(QSize screenSize READ screenSize NOTIFY screenSizeChanged)
    // The prompt `fantasi open` was given.
    Q_PROPERTY(QString initialPrompt MEMBER m_initialPrompt CONSTANT)
    // Why the last thing done with an image (Save as) didn't happen.
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)

public:
    // Where things live; an empty one is the user's own.
    struct Places {
        QString engineState;
        QString engineKey;
        QString engineCommand;
        QString folder;
        QString hyprctl;
        QString music;
    };

    // The picker asks where Save as writes; without one, the desktop portal's.
    explicit Backend(const Places &places = {}, FilePicker *picker = nullptr, QObject *parent = nullptr);

    Models *models() { return &m_models; }
    Generator *generator() { return &m_generator; }
    History *history() { return &m_history; }
    QSize screenSize() const { return m_screenSize; }

    void setInitialPrompt(const QString &prompt) { m_initialPrompt = prompt; }

    QString error() const { return m_error; }

    Q_INVOKABLE void copy(const QString &url);
    // What a later `fantasi open` asked for: that model, and a new image
    // from that prompt when it gave one.
    void open(const QString &model, const QString &prompt);
    // Asks where, then writes a copy of the image there.
    Q_INVOKABLE void saveAs(const QString &url);
    // Asks for a picture of the user's own to start the next image from.
    Q_INVOKABLE void openPicture();
    // Whether a dropped file is a picture Fantasi can start from.
    Q_INVOKABLE bool isPicture(const QString &url) const;

signals:
    void screenSizeChanged();
    void errorChanged();
    void pictureChosen(const QString &url);
    void promptRequested(const QString &prompt);
    // Another `fantasi open --model`, as the agents panel opens a model:
    // the window turns to making something new with it.
    void modelRequested();

private:
    Models m_models;
    Generator m_generator;
    History m_history;
    QSize m_screenSize{1344, 768};
    QString m_initialPrompt;
    // What a later `fantasi open` asked for while an image was being made.
    QJsonObject m_waitingOpen;
    QString m_error;
    QString m_saving;
    FilePicker *m_picker;
    QProcess m_monitors;
};
