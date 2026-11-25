#pragma once

// Follows Omacut's file picker (MIT, David Heinemeier Hansson).

#include <QObject>
#include <QUrl>

// Asks for a picture to start from, or where to save an image; the portal
// does it on the desktop, and a test puts a fake in its place.
class FilePicker : public QObject {
    Q_OBJECT

public:
    explicit FilePicker(QObject *parent = nullptr) : QObject(parent) {}
    virtual ~FilePicker() = default;

    virtual void openImage() = 0;
    virtual void saveImage(const QUrl &suggestedUrl) = 0;

signals:
    void openSelected(const QUrl &url);
    void saveSelected(const QUrl &url);
    void failed(const QString &message);
};
