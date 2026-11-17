#include "surfacetexture.h"
#include <QHash>
#include <algorithm>
#include <QSize>
#include <cmath>
#include <cstring>

SurfaceTexture::SurfaceTexture(QQuick3DObject *parent) : QQuick3DTextureData(parent) { rebuild(); }
void SurfaceTexture::setStyle(int style) {
  if (m_style != style) { m_style = style; rebuild(); emit styleChanged(); }
}
void SurfaceTexture::rebuild() {
  const int width = 256, height = m_style == 4 ? 128 : 256;
  setSize({width,height});
  setHasTransparency(false);
  setFormat(m_style == 4 ? QQuick3DTextureData::RGBA32F : QQuick3DTextureData::RGBA8);
  // Each surface is computed once and shared by every texture that shows it.
  static QHash<int,QByteArray> surfaces;
  const auto made = surfaces.constFind(m_style);
  if (made != surfaces.constEnd()) { setTextureData(*made); return; }
  QByteArray data;
  if (m_style == 4) {
    data.resize(width*height*4*sizeof(float));
    for (int y=0;y<height;++y) for (int x=0;x<width;++x) {
      // Procedural probe rows run from nadir to zenith.
      float u=float(x)/width, v=1.f-float(y)/height;
      // The key light is feathered like a scrimmed softbox, as bright in all but soft at its edges:
      // a hard-edged one mirrors in lacquer and brass as a cut-out shape.
      float across=(u-.22f)/.0744f, down=std::abs(v-.32f)/.1687f;
      // The studio stands on a table: seen from above, every silhouette mirrors what lies below the
      // horizon, so the lights end there and the lower half is the dim warm board, not more sky.
      float above=std::clamp((.5f-v)/.08f,0.f,1.f);
      above=above*above*(3-2*above);
      float softbox=3.8f*above*std::exp(-across*across-down*down*down);
      float fill=2*above*std::exp(-std::pow((u-.73f)/.13f,4)-std::pow((v-.34f)/.16f,4));
      float sky=(.18f+.22f*(1-v))*above;
      float pixel[]={sky+.16f*(1-above)+softbox+fill*.7f,sky+.131f*(1-above)+softbox*.94f+fill*.85f,sky+.109f*(1-above)+softbox*.84f+fill,1};
      std::memcpy(data.data()+(y*width+x)*sizeof(pixel),pixel,sizeof(pixel));
    }
  } else {
    data.resize(width*height*4);
    for (int y=0;y<height;++y) for (int x=0;x<width;++x) {
      float noise=std::sin(x*.73f+y*1.37f)*std::sin(x*2.27f-y*.37f);
      float wave=std::sin(x*.17f+3*std::sin(y*.018f)+.7f*std::sin(y*.051f));
      float value=.94f;
      if (m_style==1) value=.87f+.065f*wave+.035f*std::sin(x*.85f+wave*3)+noise*.015f;
      else if (m_style==2) value=.95f+.018f*std::sin(x*.04f+2*std::sin(y*.033f))+noise*.006f;
      else if (m_style==5) value=.94f-.06f*std::pow(.5f+.5f*std::sin(x*.035f+y*.025f+2*wave),12)+noise*.004f;
      else if (m_style==0) value=.93f+noise*.02f;
      auto shade=char(std::clamp(int(value*255),0,255));
      const int offset=(y*width+x)*4;
      data[offset]=shade; data[offset+1]=shade; data[offset+2]=shade; data[offset+3]=char(255);
    }
  }
  surfaces.insert(m_style,data);
  setTextureData(data);
}
