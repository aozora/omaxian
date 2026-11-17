#pragma once
#include <QQuick3DTextureData>

class SurfaceTexture : public QQuick3DTextureData {
  Q_OBJECT
  Q_PROPERTY(int style READ style WRITE setStyle NOTIFY styleChanged)
public:
  explicit SurfaceTexture(QQuick3DObject *parent = nullptr);
  int style() const { return m_style; }
  void setStyle(int style);
signals:
  void styleChanged();
private:
  void rebuild();
  int m_style = 0;
};
