#include "textlayout.h"

#include <QFontMetricsF>
#include <QPainter>

namespace {

// Text is laid out at a fixed pixel size and scaled to the requested point
// size. Pixel sizes don't depend on the device's DPI, so the screen and the
// 72 DPI PDF writer measure the same font identically.
constexpr int ReferenceSize = 100;

}

namespace TextLayout {

QFont font() {
    QFont font(QStringLiteral("Noto Sans"));
    font.setStyleHint(QFont::SansSerif);
    font.setPixelSize(ReferenceSize);
    font.setHintingPreference(QFont::PreferNoHinting);
    font.setKerning(true);
    return font;
}

QSizeF size(const QString &text, qreal fontSize) {
    const QFontMetricsF metrics(font());
    const QStringList lines = text.split(QLatin1Char('\n'));
    qreal width = 0;
    for (const QString &line : lines)
        width = std::max(width, metrics.horizontalAdvance(line));
    const qreal scale = fontSize / ReferenceSize;
    return {width * scale, metrics.lineSpacing() * lines.size() * scale};
}

void paint(QPainter &painter, const QPointF &topLeft, const QString &text, qreal fontSize) {
    const QFont layoutFont = font();
    const QFontMetricsF metrics(layoutFont);
    const qreal scale = fontSize / ReferenceSize;

    painter.save();
    painter.translate(topLeft);
    painter.scale(scale, scale);
    painter.setFont(layoutFont);
    painter.setPen(Qt::black);
    const QStringList lines = text.split(QLatin1Char('\n'));
    for (int i = 0; i < lines.size(); ++i)
        painter.drawText(QPointF(0, metrics.ascent() + i * metrics.lineSpacing()), lines.at(i));
    painter.restore();
}

}
