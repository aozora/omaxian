#pragma once

#include <QAbstractListModel>
#include <QImage>
#include <QStringList>

// The saved signatures: one PNG per signature in a directory, named after it.
// No index to keep in sync — the directory is the library.
class SignatureLibrary : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Role { NameRole = Qt::UserRole + 1, SourceRole };

    explicit SignatureLibrary(const QString &directory = {}, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_names.size(); }
    QString directory() const { return m_directory; }

    Q_INVOKABLE QString validateName(const QString &name) const;
    Q_INVOKABLE bool contains(const QString &name) const;
    Q_INVOKABLE void reload();
    QString add(const QString &name, const QImage &image);
    bool remove(const QString &name);
    QImage image(const QString &name) const;

    // Turns a scan or photo of a signature on paper into ink on transparency,
    // cropped to the ink. threshold is how dark, relative to the paper, a
    // pixel must be to count as ink. Images that already have transparency are
    // only cropped. Returns a null image when no ink is left.
    static QImage removeBackground(const QImage &source, qreal threshold);
    static QImage load(const QString &path, QString *error = nullptr);

signals:
    void countChanged();

private:
    QString pathFor(const QString &name) const;

    QString m_directory;
    QStringList m_names;
    int m_generation = 0;
};
