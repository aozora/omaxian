#include "textitem.h"

#include <QPainter>

#include "textlayout.h"

TextItem::TextItem(QQuickItem *parent) : QQuickPaintedItem(parent) {
    setAntialiasing(true);
    connect(this, &TextItem::changed, this, [this] { update(); });
}

void TextItem::paint(QPainter *painter) {
    painter->setRenderHint(QPainter::TextAntialiasing);
    painter->scale(m_zoom, m_zoom);
    TextLayout::paint(*painter, QPointF(0, 0), m_text, m_fontSize);
}
