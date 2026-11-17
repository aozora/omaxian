#include "sculptgeometry.h"
#include "figures.h"
#include "woodland.h"
#include <QVector2D>
#include <QVector3D>
#include <QVector4D>
#include <QQmlEngine>
#include <QtConcurrent>
#include <algorithm>
#include <map>

// Nothing is sculpted for the defaults a geometry starts with: one made in code builds on its first setter,
// and one declared in QML waits for the last of them, so neither casts a figure nobody asked for.
SculptGeometry::SculptGeometry(QQuick3DObject *parent) : QQuick3DGeometry(parent) {}
void SculptGeometry::setKind(int value) { const bool moved=m_kind != value; m_kind=value; if (moved || !m_built) { rebuild(); if (moved) emit changed(); } }
void SculptGeometry::setDesign(int value) { const bool moved=m_design != value; m_design=value; if (moved || !m_built) { rebuild(); if (moved) emit changed(); } }
void SculptGeometry::setPart(int value) { const bool moved=m_part != value; m_part=value; if (moved || !m_built) { rebuild(); if (moved) emit changed(); } }
void SculptGeometry::setTone(int value) { const bool moved=m_tone != value; m_tone=value; if (moved || !m_built) { rebuild(); if (moved) emit changed(); } }
void SculptGeometry::shape(int design,int kind,int part,int tone) {
  m_design=design; m_kind=kind; m_part=part; m_tone=tone;
  rebuild();
  emit changed();
}
QQuick3DGeometry *Sculptures::geometry(int design,int kind,int part,int tone) {
  // Only Moss & Myth paints its two sides differently.
  if(design!=2) tone=0;
  const int key=((design*6+kind-1)*6+part)*2+(tone ? 1 : 0);
  auto &made=m_made[key];
  if(!made) {
    made=new SculptGeometry;
    made->setParent(this);
    // QML only borrows it: a geometry returned from a method would otherwise be the garbage collector's to free.
    QQmlEngine::setObjectOwnership(made,QQmlEngine::CppOwnership);
    made->shape(design,kind,part,tone);
  }
  return made;
}
void SculptGeometry::componentComplete() {
  QQuick3DGeometry::componentComplete();
  m_declared=false;
  rebuild();
}
void SculptGeometry::rebuild() {
  if(m_declared) return;
  m_built=true;
  // Sculpting takes a moment, so every part is made once and shared by all the pieces that wear it.
  struct Sculpture { QByteArray vertices, indices; QVector3D minimum, maximum; };
  static std::map<int,Sculpture> sculptures;
  const bool woodland=m_design==2;
  const int key=((m_design*6+m_kind-1)*6+m_part)*2+(woodland && m_tone ? 1 : 0);
  auto upload=[&](const Sculpture &shape) {
    clear();
    setVertexData(shape.vertices);
    setStride(sizeof(SculptVertex));
    setPrimitiveType(QQuick3DGeometry::PrimitiveType::Triangles);
    addAttribute(QQuick3DGeometry::Attribute::PositionSemantic,0,QQuick3DGeometry::Attribute::F32Type);
    addAttribute(QQuick3DGeometry::Attribute::NormalSemantic,sizeof(QVector3D),QQuick3DGeometry::Attribute::F32Type);
    addAttribute(QQuick3DGeometry::Attribute::TexCoord0Semantic,2*sizeof(QVector3D),QQuick3DGeometry::Attribute::F32Type);
    // Moss & Myth is painted in its vertices; the cast sets keep the shade of their recesses there.
    addAttribute(QQuick3DGeometry::Attribute::ColorSemantic,2*sizeof(QVector3D)+sizeof(QVector2D),QQuick3DGeometry::Attribute::F32Type);
    if(!shape.indices.isEmpty()) {
      setIndexData(shape.indices);
      addAttribute(QQuick3DGeometry::Attribute::IndexSemantic,0,QQuick3DGeometry::Attribute::U32Type);
    }
    setBounds(shape.minimum,shape.maximum);
    update();
  };
  if(m_design<0 || m_design>3 || m_kind<1 || m_kind>6 || m_part<0 || m_part>5) { clear(); update(); return; }
  const auto found=sculptures.find(key);
  if(found!=sculptures.end()) { upload(found->second); return; }
  // Moss & Myth figures are whole painted carvings; the other sets are cast part by part.
  // A cast set is wanted whole the moment one part of it is, so its parts are cast side by side on every core
  // rather than one after another while the window waits. Moss & Myth carves its six figures the same way.
  static std::map<int,SculptFigure> cast;
  static bool poured[4]={};
  if(!woodland && m_part<4 && !poured[m_design]) {
    poured[m_design]=true;
    struct Job { int kind,part; SculptFigure figure; };
    QList<Job> jobs;
    for(int kind=1;kind<=6;++kind) for(int part=0;part<4;++part) jobs.append({kind,part,{}});
    const int design=m_design;
    QtConcurrent::blockingMap(jobs,[design](Job &job) { job.figure=Figures::part(design,job.kind,job.part); });
    for(Job &job:jobs) cast.emplace((design*6+job.kind-1)*6+job.part,std::move(job.figure));
  }
  SculptFigure figure;
  const auto ready=cast.find((m_design*6+m_kind-1)*6+m_part);
  if(!woodland && ready!=cast.end()) { figure=std::move(ready->second); cast.erase(ready); }
  else if(!woodland) figure=Figures::part(m_design,m_kind,m_part);
  else if(m_part==0) figure=Woodland::figure(m_kind,m_tone);
  // A part a piece does not have is a single point, which draws nothing.
  if(figure.vertices.empty()) {
    figure.vertices.assign(3,SculptVertex{QVector3D(0,0,0),QVector3D(0,1,0),QVector2D(0,0),QVector4D(1,1,1,1)});
    figure.indices.clear();
  }
  QVector3D minimum=figure.vertices.front().position,maximum=minimum;
  for (const auto &vertex : figure.vertices) for(int axis=0;axis<3;++axis) {
    minimum[axis]=std::min(minimum[axis],vertex.position[axis]);
    maximum[axis]=std::max(maximum[axis],vertex.position[axis]);
  }
  Sculpture shape;
  shape.vertices=QByteArray(reinterpret_cast<const char *>(figure.vertices.data()),qsizetype(figure.vertices.size()*sizeof(SculptVertex)));
  shape.indices=QByteArray(reinterpret_cast<const char *>(figure.indices.data()),qsizetype(figure.indices.size()*sizeof(quint32)));
  shape.minimum=minimum; shape.maximum=maximum;
  upload(sculptures.emplace(key,std::move(shape)).first->second);
}
