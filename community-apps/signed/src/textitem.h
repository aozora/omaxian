#pragma once

#include <QQuickPaintedItem>

// Paints a text item through TextLayout, the same code that writes it into
// the PDF, so what's on screen is what gets saved.
class TextItem : public QQuickPaintedItem {
    Q_OBJECT
    Q_PROPERTY(QString text MEMBER m_text NOTIFY changed)
    Q_PROPERTY(qreal fontSize MEMBER m_fontSize NOTIFY changed)
    Q_PROPERTY(qreal zoom MEMBER m_zoom NOTIFY changed)

public:
    explicit TextItem(QQuickItem *parent = nullptr);
    void paint(QPainter *painter) override;

signals:
    void changed();

private:
    QString m_text;
    qreal m_fontSize = 12;
    qreal m_zoom = 1;
};
