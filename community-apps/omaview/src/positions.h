#pragma once

#include <QJsonObject>
#include <QString>

// Where each file was left, and the choices worth keeping between files
// (volume, the subtitle and audio languages picked). Several windows may be
// open, so every write locks, rereads, changes only its own entry, and
// replaces the file atomically.
class Positions {
public:
    // Tests pass a temp file; the default is ~/.local/state/omaview/positions.json.
    explicit Positions(const QString &path = {});

    static constexpr qint64 minimumDuration = 5 * 60 * 1000;
    static constexpr int keep = 500;

    // The position to resume a file at, or -1.
    qint64 lookup(const QString &file) const;
    // Remembers a file's position by the rules: long enough to be worth it,
    // and not at its end; otherwise forgets it.
    void update(const QString &file, qint64 position, qint64 duration);
    void forget(const QString &file);

    QJsonObject preferences() const;
    void setPreference(const QString &key, const QJsonValue &value);
    // Several at once, in one locked write.
    void setPreferences(const QJsonObject &changed);

    // The key a file is remembered under: its path, size and modification
    // time, hashed, so the file holds no names and an edited file starts over.
    static QString key(const QString &file);


private:
    QJsonObject read() const;
    template <typename Change>
    void change(Change change);

    QString m_path;
};
