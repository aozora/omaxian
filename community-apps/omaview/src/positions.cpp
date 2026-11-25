#include "positions.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QLockFile>
#include <QSaveFile>
#include <QStandardPaths>
#include <algorithm>
#include <vector>

Positions::Positions(const QString &path)
    : m_path(!path.isEmpty() ? path
                             : QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation)
                                   + "/omaview/positions.json") {}

QString Positions::key(const QString &file) {
    const QFileInfo info(file);
    if (!info.exists())
        return {};
    const QByteArray identity = info.absoluteFilePath().toUtf8() + '\n' + QByteArray::number(info.size()) + '\n'
                                + QByteArray::number(info.lastModified().toMSecsSinceEpoch());
    return QString::fromLatin1(QCryptographicHash::hash(identity, QCryptographicHash::Sha256).toHex().left(32));
}

QJsonObject Positions::read() const {
    QFile file(m_path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(file.readAll()).object();
}

template <typename Change>
void Positions::change(Change change) {
    QDir().mkpath(QFileInfo(m_path).absolutePath());
    QLockFile lock(m_path + ".lock");
    lock.setStaleLockTime(5000);
    // A position is a convenience: if another window holds the lock for this
    // long, skipping one write loses nothing anyone would notice.
    if (!lock.tryLock(2000))
        return;
    QJsonObject root = read();
    change(root);

    // Only the most recent entries are kept, so the file stays small.
    QJsonObject files = root.value("files").toObject();
    if (files.size() > keep) {
        std::vector<std::pair<qint64, QString>> ages;
        for (auto it = files.begin(); it != files.end(); ++it)
            ages.emplace_back(it.value().toObject().value("at").toInteger(), it.key());
        std::sort(ages.begin(), ages.end());
        for (std::size_t i = 0; i + keep < ages.size(); ++i)
            files.remove(ages[i].second);
        root.insert("files", files);
    }

    QSaveFile out(m_path);
    out.setDirectWriteFallback(false);
    if (!out.open(QIODevice::WriteOnly))
        return;
    out.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    out.commit();
}

qint64 Positions::lookup(const QString &file) const {
    const QString k = key(file);
    if (k.isEmpty())
        return -1;
    const QJsonObject entry = read().value("files").toObject().value(k).toObject();
    return entry.contains("position") ? entry.value("position").toInteger(-1) : -1;
}

void Positions::update(const QString &file, qint64 position, qint64 duration) {
    if (duration < minimumDuration || position <= 0 || position >= duration * 95 / 100) {
        forget(file);
        return;
    }
    const QString k = key(file);
    if (k.isEmpty())
        return;
    change([&](QJsonObject &root) {
        QJsonObject files = root.value("files").toObject();
        files.insert(k, QJsonObject{{"position", position}, {"at", QDateTime::currentSecsSinceEpoch()}});
        root.insert("files", files);
    });
}

void Positions::forget(const QString &file) {
    const QString k = key(file);
    if (k.isEmpty() || !read().value("files").toObject().contains(k))
        return;
    change([&](QJsonObject &root) {
        QJsonObject files = root.value("files").toObject();
        files.remove(k);
        root.insert("files", files);
    });
}

QJsonObject Positions::preferences() const {
    return read().value("preferences").toObject();
}

void Positions::setPreference(const QString &name, const QJsonValue &value) {
    setPreferences({{name, value}});
}

void Positions::setPreferences(const QJsonObject &changed) {
    if (changed.isEmpty())
        return;
    change([&](QJsonObject &root) {
        QJsonObject preferences = root.value("preferences").toObject();
        for (auto it = changed.begin(); it != changed.end(); ++it)
            preferences.insert(it.key(), it.value());
        root.insert("preferences", preferences);
    });
}
