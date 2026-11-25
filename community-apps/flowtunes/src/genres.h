#pragma once

#include <QList>
#include <QString>
#include <QStringList>

class QRandomGenerator;

// What Flowtunes plays: each genre is a description of its sound and a
// handful of turns it can take, so one tune differs from the next while the
// genre stays itself. `name` is what its folder of tunes is called; the names
// shown are in Main.qml, where they're translated.
struct Genre {
    QString id;
    QString name;
    QString sound;
    // The same genre as a song someone sings.
    QString song;
    QStringList turns;
    // What its instrumental tunes are named from: one of each.
    QStringList moods;
    QStringList things;
};

namespace Genres {

const QList<Genre> &all();
QStringList ids();
bool has(const QString &id);
QString name(const QString &id);
// What the music model is asked for: the genre's sound with two of its
// turns, without a voice, or with lyrics as a song of the genre with one.
QString caption(const QString &id, QRandomGenerator &random, bool lyrics = false);
// A name for a tune nobody sings in: a mood of the genre and a thing of it,
// "Dusty Notebook". They're English, as tunes' names often are anywhere.
QString title(const QString &id, QRandomGenerator &random);

} // namespace Genres
