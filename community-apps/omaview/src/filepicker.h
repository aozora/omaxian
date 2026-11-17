#pragma once

#include <QList>
#include <QObject>
#include <QUrl>

// The open and save dialogs, behind an interface so tests can answer them.
class FilePicker : public QObject {
    Q_OBJECT

public:
    explicit FilePicker(QObject *parent = nullptr) : QObject(parent) {}
    virtual ~FilePicker() = default;

    virtual void openMedia() = 0;
    virtual void saveImage(const QUrl &suggestedUrl) = 0;

signals:
    void openSelected(const QList<QUrl> &urls);
    void saveSelected(const QUrl &url);
    // The dialog was dismissed without a choice.
    void cancelled();
    void failed(const QString &message);
};
