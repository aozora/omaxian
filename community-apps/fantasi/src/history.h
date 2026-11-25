#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QFileSystemWatcher>
#include <QFutureWatcher>
#include <QTimer>

// The images in the output folder, newest first, with the prompt, seed and
// size each one carries. Images an agent made with the command line are here
// too: it is the folder, not the app's own list.
class History : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    struct Entry {
        QString path;
        QString prompt;
        qint64 seed = -1;
        QString size;
        QDateTime modified;
        // The clip a poster stands for; empty for an image.
        QString video;
        // The song a poster stands for, and what the song goes by.
        QString audio;
        QString title;
        // The song's shape: how loud it is from start to end, each 0 to 1.
        QVariantList wave;
    };
    enum Role { UrlRole = Qt::UserRole + 1, PathRole, PromptRole, SeedRole, SizeRole, VideoRole, AudioRole, TitleRole, WaveRole };

    // Songs are in `musicFolder`, their posters among the images in `folder`.
    explicit History(const QString &folder, const QString &musicFolder = {}, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return int(m_entries.size()); }

    // The settings stable-diffusion.cpp writes into a PNG's `parameters`:
    // the prompt, then a line of `Key: value` pairs.
    static Entry readEntry(const QString &path, const QString &musicFolder = {});
    static QList<Entry> scan(const QString &folder, const QString &musicFolder = {});

    // What the entry shows: its image, or a poster's clip or song.
    Q_INVOKABLE QString urlAt(int row) const {
        for (const Role role : {VideoRole, AudioRole})
            if (const QString media = data(index(row), role).toString(); !media.isEmpty())
                return media;
        return data(index(row), UrlRole).toString();
    }
    // The title and shape of the song at `url`, empty until it's listed.
    Q_INVOKABLE QVariantMap song(const QString &url) const;
    // The row showing `url`, as urlAt gives it, or -1.
    Q_INVOKABLE int rowOf(const QString &url) const {
        for (int row = 0; row < rowCount(); ++row)
            if (urlAt(row) == url)
                return row;
        return -1;
    }
    Q_INVOKABLE QString promptAt(int row) const { return data(index(row), PromptRole).toString(); }
    // Moves the image to the trash, from where it can come back.
    Q_INVOKABLE bool remove(int row);

signals:
    void countChanged();

private:
    void rescan();
    void watch();

    QString m_folder;
    QString m_musicFolder;
    QList<Entry> m_entries;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QFutureWatcher<QList<Entry>> m_scan;
    bool m_again = false;
};
