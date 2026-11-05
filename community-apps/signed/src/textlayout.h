#pragma once

#include <QFont>
#include <QPointF>
#include <QSizeF>
#include <QString>

class QPainter;

// The one place text is measured and painted, used both on screen and in the
// exported PDF, so a placed line of text lands exactly where it was shown.
// Everything is in PDF points.
namespace TextLayout {

QFont font();
QSizeF size(const QString &text, qreal fontSize);
void paint(QPainter &painter, const QPointF &topLeft, const QString &text, qreal fontSize);

}
