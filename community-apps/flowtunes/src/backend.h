#pragma once

#include <QObject>

#include "flow.h"
#include "models.h"
#include "mpris.h"

// The app's state for the window: the music model, the flow of tunes it
// makes, and the desktop's way to play them.
class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(Models *models READ models CONSTANT)
    Q_PROPERTY(Flow *flow READ flow CONSTANT)
    Q_PROPERTY(Mpris *mpris READ mpris CONSTANT)
    // The genre `flowtunes <genre>` asked to play from the start.
    Q_PROPERTY(QString initialGenre MEMBER m_initialGenre CONSTANT)

public:
    // Where things live; an empty one is the user's own.
    struct Places {
        QString engineState;
        QString engineKey;
        QString engineCommand;
        QString musicFolder;
    };

    explicit Backend(const Places &places = {}, QObject *parent = nullptr);

    Models *models() { return &m_models; }
    Flow *flow() { return &m_flow; }
    Mpris *mpris() { return &m_mpris; }
    void setInitialGenre(const QString &genre) { m_initialGenre = genre; }

private:
    Models m_models;
    Flow m_flow;
    Mpris m_mpris;
    QString m_initialGenre;
};
