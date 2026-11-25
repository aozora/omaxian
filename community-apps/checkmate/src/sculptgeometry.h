#pragma once
#include <QHash>
#include <QQuick3DGeometry>

class SculptGeometry : public QQuick3DGeometry {
  Q_OBJECT
  Q_PROPERTY(int kind READ kind WRITE setKind NOTIFY changed)
  Q_PROPERTY(int design READ design WRITE setDesign NOTIFY changed)
  Q_PROPERTY(int part READ part WRITE setPart NOTIFY changed)
  // Moss & Myth figures are painted in the mesh, so each side has its own: 0 pale, 1 dark.
  Q_PROPERTY(int tone READ tone WRITE setTone NOTIFY changed)
public:
  explicit SculptGeometry(QQuick3DObject *parent = nullptr);
  int kind() const { return m_kind; }
  int design() const { return m_design; }
  int part() const { return m_part; }
  int tone() const { return m_tone; }
  void setKind(int value);
  void setDesign(int value);
  void setPart(int value);
  void setTone(int value);
  // All four at once, built once.
  void shape(int design,int kind,int part,int tone);
  // A geometry declared in QML is built once, when all four of its properties are in.
  void classBegin() override { m_declared = true; }
  void componentComplete() override;
signals:
  void changed();
private:
  friend class Sculptures;
  void rebuild();
  int m_kind = 1, m_design = 0, m_part = 0, m_tone = 0;
  bool m_declared = false, m_built = false;
};

// Hands out one geometry per figure, so sixteen pawns share a single mesh on the GPU instead of uploading sixteen.
class Sculptures : public QObject {
  Q_OBJECT
public:
  using QObject::QObject;
  Q_INVOKABLE QQuick3DGeometry *geometry(int design,int kind,int part,int tone);
private:
  QHash<int,SculptGeometry *> m_made;
};
