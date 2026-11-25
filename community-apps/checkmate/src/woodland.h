#pragma once
#include <QVector2D>
#include <QVector3D>
#include <QVector4D>
#include <QtGlobal>
#include <vector>

// One vertex layout serves every set: Moss & Myth paints its vertices, the others shade their recesses there.
struct SculptVertex { QVector3D position, normal; QVector2D uv; QVector4D color{1,1,1,1}; };

// A finished mesh, its triangles sharing vertices through an index buffer.
struct SculptFigure { std::vector<SculptVertex> vertices; std::vector<quint32> indices; };

namespace Woodland {
using Figure=SculptFigure;
// The carved and painted figure for a piece kind (1 pawn to 6 king); tone 0 is the pale side.
const Figure &figure(int kind,int tone);
}
