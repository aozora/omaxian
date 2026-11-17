#include "figures.h"
#include <QVector2D>
#include <QVector3D>
#include <QVector4D>
#include <algorithm>
#include <cmath>

namespace {
using namespace Clay;
using Figures::Field;
using Figures::Mould;

// Where a mould's solid lies, found on a coarse lattice so no figure needs a hand-measured box.
bool extent(const Field &field,float margin,P &low,P &high) {
  const float step=.055f;
  const int across=11, below=2, tall=40;
  bool found=false;
  for(int k=-across;k<=across;++k) for(int j=-below;j<tall;++j) for(int i=-across;i<=across;++i) {
    const P p{i*step,j*step,k*step};
    const float d=field(p);
    if(d>=step) {
      // A field never overstates the way to its surface by much, so the lattice strides across open air.
      i+=std::max(0,int((std::min(d,2.f)*.7f-step)/step));
      continue;
    }
    if(!found) { low=high=p; found=true; }
    low={std::min(low.x,p.x),std::min(low.y,p.y),std::min(low.z,p.z)};
    high={std::max(high.x,p.x),std::max(high.y,p.y),std::max(high.z,p.z)};
  }
  low=low-P{margin,margin,margin};
  high=high+P{margin,margin,margin};
  return found;
}

// The slope of a field, uphill and as steep as the field really is there, felt over a reach of `e`.
P slope(const Field &field,P p,float e) {
  const P a{1,-1,-1}, b{-1,-1,1}, c{-1,1,-1}, d{1,1,1};
  return (a*field(p+a*e)+b*field(p+b*e)+c*field(p+c*e)+d*field(p+d*e))*(.25f/e);
}

// Shadow gathers where the surface is closed in, by its own solid or by what stands against it,
// and is cast into the vertex with the shape.
float daylight(const Mould &mould,P spot,P facing,float steep) {
  if(mould.shade<=0) return 1;
  auto air=[&](float reach) {
    const P p=spot+facing*reach;
    const float d=mould.field(p);
    return mould.company ? std::min(d,mould.company(p)) : d;
  };
  const float here=mould.field(spot);
  const float open=saturate((.55f*(air(.03f)-here)/.03f+.45f*(air(.09f)-here)/.09f)/steep);
  return 1-mould.shade*(1-open);
}

void add(SculptFigure &out,P spot,P facing,float lit) {
  SculptVertex vertex;
  vertex.position=QVector3D(spot.x,spot.y,spot.z);
  vertex.normal=QVector3D(facing.x,facing.y,facing.z);
  // Grain runs through the solid like a plank's, so it meets itself all the way round.
  vertex.uv=QVector2D(.5f+.62f*spot.x+.47f*spot.z,spot.y);
  vertex.color=QVector4D(lit,lit,lit,1);
  out.vertices.push_back(vertex);
}

void face(SculptFigure &out,quint32 a,quint32 b,quint32 c) {
  quint32 corner[3]={a,b,c};
  const auto &v=out.vertices;
  // Qt flips back-face normals, so winding must agree with the sculpted normals.
  const QVector3D across=QVector3D::crossProduct(v[b].position-v[a].position,v[c].position-v[a].position);
  if(QVector3D::dotProduct(across,v[a].normal+v[b].normal+v[c].normal)<0) std::swap(corner[1],corner[2]);
  out.indices.insert(out.indices.end(),corner,corner+3);
}

// A cell that holds an edge of the solid seats its vertex on that edge, as dual contouring does,
// so arrises run straight and evenly lit instead of stepping from cell to cell.
bool ridge(const Field &field,P low,float cell,P home,P &spot,P &facing,float steep) {
  static const int corner[8][3]={{0,0,0},{1,0,0},{0,1,0},{1,1,0},{0,0,1},{1,0,1},{0,1,1},{1,1,1}};
  static const int edge[12][2]={{0,1},{2,3},{4,5},{6,7},{0,2},{1,3},{4,6},{5,7},{0,4},{1,5},{2,6},{3,7}};
  const P base{low.x+std::floor((home.x-low.x)/cell)*cell,low.y+std::floor((home.y-low.y)/cell)*cell,low.z+std::floor((home.z-low.z)/cell)*cell};
  // A smooth face lies flat across its cell; only a cell that departs from that is worked on.
  float v[8], bend=0;
  for(int c=0;c<8;++c) {
    const P p=base+P{float(corner[c][0]),float(corner[c][1]),float(corner[c][2])}*cell;
    v[c]=field(p);
    bend=std::max(bend,std::abs(v[c]/steep-dot(facing,p-spot)));
  }
  if(bend<cell*.2f) return false;
  // Each crossing of the cell's edges gives a point on the surface and the plane of the face it lies in.
  P at[12], plane[12], mass;
  int count=0;
  for(const auto &e:edge) {
    const float a=v[e[0]], b=v[e[1]];
    if((a<0)==(b<0)) continue;
    const float t=a/(a-b);
    const int *from=corner[e[0]], *to=corner[e[1]];
    const P p=base+P{from[0]+(to[0]-from[0])*t,from[1]+(to[1]-from[1])*t,from[2]+(to[2]-from[2])*t}*cell;
    const P lean=slope(field,p,cell*.1f);
    const float size=length(lean);
    // A field torn across a step is no guide; the vertex stays where it settled.
    if(size>1.6f) return false;
    // Faces turned away belong to the far side of a thin sheet, not to this vertex.
    if(size<1e-4f || dot(lean,facing)<-.2f*size) continue;
    plane[count]=lean*(1/size);
    at[count]=p-plane[count]*std::clamp(field(p)/std::max(.25f,size),-cell*.5f,cell*.5f);
    mass=mass+at[count];
    ++count;
  }
  if(count<3) return false;
  mass=mass*(1.f/count);
  // The point nearest every plane, held lightly to the middle of the crossings where the planes leave it free.
  float xx=.1f, yy=.1f, zz=.1f, xy=0, xz=0, yz=0, apart=1;
  int one=0, other=0;
  P pull;
  for(int i=0;i<count;++i) {
    const P n=plane[i];
    xx+=n.x*n.x; yy+=n.y*n.y; zz+=n.z*n.z; xy+=n.x*n.y; xz+=n.x*n.z; yz+=n.y*n.z;
    pull=pull+n*dot(n,at[i]-mass);
    for(int j=i+1;j<count;++j) if(dot(n,plane[j])<apart) { apart=dot(n,plane[j]); one=i; other=j; }
  }
  const float c00=yy*zz-yz*yz, c01=xz*yz-xy*zz, c02=xy*yz-xz*yy, c11=xx*zz-xz*xz, c12=xy*xz-xx*yz, c22=xx*yy-xy*xy;
  const float det=xx*c00+xy*c01+xz*c02;
  P seat=mass+P{c00*pull.x+c01*pull.y+c02*pull.z,c01*pull.x+c11*pull.y+c12*pull.z,c02*pull.x+c12*pull.y+c22*pull.z}*(1/det);
  // Confine the fitted point to its cell before projecting it back onto the surface.
  seat={std::clamp(seat.x,base.x,base.x+cell),std::clamp(seat.y,base.y,base.y+cell),std::clamp(seat.z,base.z,base.z+cell)};
  const P rise=slope(field,seat,cell*.4f);
  spot=seat-normalize(rise)*std::clamp(field(seat)/std::max(.25f,length(rise)),-cell*.5f,cell*.5f);
  // On the arris itself the slope is torn between two faces; the normal there bisects them.
  const P here=normalize(slope(field,spot,cell*.1f));
  const bool torn=apart<.94f && apart>-.8f && dot(here,plane[one])<.985f && dot(here,plane[other])<.985f;
  facing=torn ? normalize(plane[one]+plane[other]) : here;
  return true;
}

// Carved solids are cut from a grid of cells.
void cast(const Mould &mould,SculptFigure &out,bool fitEdges) {
  const Field &field=mould.field;
  const float cell=mould.cell;
  P low,high;
  if(!extent(field,.055f+2*cell,low,high)) return;
  const quint32 first=quint32(out.vertices.size());
  shell(field,low,high,cell,[&](P spot) {
    const P home=spot;
    // Two steps down the slope seat each vertex on the surface, so polished faces stay true.
    const P fall=slope(field,spot,cell*.4f);
    const float pitch=std::max(.25f,length(fall));
    for(int step=0;step<2;++step) spot=spot-normalize(fall)*std::clamp(field(spot)/pitch,-cell*.6f,cell*.6f);
    P rise=slope(field,spot,cell*.4f), facing=normalize(rise);
    if(fitEdges && ridge(field,low,cell,home,spot,facing,std::max(.25f,length(rise)))) rise=slope(field,spot,cell*.4f);
    add(out,spot,facing,daylight(mould,spot,facing,std::max(.25f,length(rise))));
    return spot;
  },[&](int a,int b,int c) { face(out,first+quint32(a),first+quint32(b),first+quint32(c)); });
}

// Turned solids are the same all the way round: the outline is traced once in a half-plane, finer
// than a grid could cut it, and spun into whole rings, so rims and highlights run true about the axis.
void turn(const Mould &mould,SculptFigure &out) {
  const Field &field=mould.field;
  const float cell=mould.cell*.4f;
  P low,high;
  if(!extent(field,.055f+2*cell,low,high)) return;
  const float reach=std::max(std::max(high.x,-low.x),std::max(high.z,-low.z));
  auto solid=[&](float rho,float y) { return field(P{std::abs(rho),y,0}); };
  // Nodes straddle the axis, so a cell on it is cut alike from both sides and its vertex is a pole.
  const int nx=int(std::ceil(reach/cell))+2, ny=int(std::ceil((high.y-low.y)/cell))+1;
  auto at=[&](int i,int j) { return size_t(i)+size_t(nx)*size_t(j); };
  std::vector<float> value(size_t(nx)*size_t(ny));
  for(int j=0;j<ny;++j) for(int i=0;i<nx;++i) {
    const float d=solid((i-.5f)*cell,low.y+j*cell);
    // The far faces of the grid count as air, so the outline always closes.
    value[at(i,j)]=i==nx-1 || j==0 || j==ny-1 ? std::max(d,cell) : d;
  }
  auto lean=[&](float rho,float y) {
    const float e=cell*.5f;
    return P{(solid(rho+e,y)-solid(rho-e,y))/(2*e),(solid(rho,y+e)-solid(rho,y-e))/(2*e),0};
  };

  // One bead of the outline settles in every cell the surface crosses.
  struct Bead { float rho,y; P facing; float lit,steep; std::vector<float> light; };
  std::vector<Bead> beads;
  std::vector<int> owner(value.size(),-1);
  float widest=0;
  for(int j=0;j+1<ny;++j) for(int i=0;i+1<nx;++i) {
    const float v[4]={value[at(i,j)],value[at(i+1,j)],value[at(i,j+1)],value[at(i+1,j+1)]};
    const int inside=(v[0]<0)+(v[1]<0)+(v[2]<0)+(v[3]<0);
    if(inside==0 || inside==4) continue;
    float across=0, up=0;
    int crossings=0;
    auto cut=[&](int from,int to) {
      if((v[from]<0)==(v[to]<0)) return;
      const float t=v[from]/(v[from]-v[to]);
      across+=(from&1)+((to&1)-(from&1))*t;
      up+=(from>>1)+((to>>1)-(from>>1))*t;
      ++crossings;
    };
    cut(0,1); cut(2,3); cut(0,2); cut(1,3);
    const bool pole=i==0;
    float rho=pole ? 0 : (i-.5f+across/crossings)*cell, y=low.y+(j+up/crossings)*cell;
    const P fall=lean(rho,y), down=normalize(fall);
    const float pitch=std::max(.25f,length(fall));
    for(int step=0;step<2;++step) {
      const float d=std::clamp(solid(rho,y)/pitch,-cell*.6f,cell*.6f);
      rho=pole ? 0 : std::max(0.f,rho-down.x*d);
      y-=down.y*d;
    }
    const P rise=lean(rho,y), facing=normalize(rise);
    owner[at(i,j)]=int(beads.size());
    const float steep=std::max(.25f,length(rise));
    beads.push_back({rho,y,facing,daylight(mould,P{rho,y,0},facing,steep),steep,{}});
    widest=std::max(widest,rho);
  }
  if(beads.empty()) return;

  // Beads are strung together across every grid edge the surface crosses, between the two cells that share it.
  std::vector<int> link(beads.size()*4,-1);
  auto join=[&](int a,int b) {
    if(a<0 || b<0) return;
    for(int s=0;s<4;++s) if(link[size_t(a)*4+s]<0) { link[size_t(a)*4+s]=b; break; }
    for(int s=0;s<4;++s) if(link[size_t(b)*4+s]<0) { link[size_t(b)*4+s]=a; break; }
  };
  for(int j=0;j+1<ny;++j) for(int i=1;i+1<nx;++i) {
    if((value[at(i,j)]<0)!=(value[at(i,j+1)]<0)) join(owner[at(i-1,j)],owner[at(i,j)]);
    if(j>0 && (value[at(i,j)]<0)!=(value[at(i+1,j)]<0)) join(owner[at(i,j-1)],owner[at(i,j)]);
  }
  auto follow=[&](int from) {
    for(int s=0;s<4;++s) {
      const int to=link[size_t(from)*4+s];
      if(to<0) continue;
      link[size_t(from)*4+s]=-1;
      for(int t=0;t<4;++t) if(link[size_t(to)*4+t]==from) { link[size_t(to)*4+t]=-1; break; }
      return to;
    }
    return -1;
  };

  // Every bead off the axis becomes a ring of vertices, shared by the bands on either side of it.
  const int around=std::clamp(8*int(std::ceil(2*pi*widest/.02f/8)),48,128);
  // Contact shading is sampled around each ring because neighbouring parts may be asymmetric.
  if(mould.company) for(Bead &b:beads) {
    b.light.reserve(size_t(around));
    for(int k=0;k<around;++k) {
      const float angle=2*pi*k/around, c=std::cos(angle), s=std::sin(angle);
      b.light.push_back(daylight(mould,P{b.rho*c,b.y,b.rho*s},P{b.facing.x*c,b.facing.y,b.facing.x*s},b.steep));
    }
  }
  std::vector<int> ring(beads.size(),-1);
  auto rim=[&](int bead) {
    const Bead &b=beads[size_t(bead)];
    if(ring[size_t(bead)]<0) {
      ring[size_t(bead)]=int(out.vertices.size());
      for(int k=0;k<(b.rho>0 ? around : 1);++k) {
        const float angle=2*pi*k/around, c=std::cos(angle), s=std::sin(angle);
        const P spot{b.rho*c,b.y,b.rho*s}, facing{b.facing.x*c,b.facing.y,b.facing.x*s};
        add(out,spot,facing,b.light.empty() ? b.lit : b.light[size_t(k)]);
      }
    }
    return quint32(ring[size_t(bead)]);
  };
  auto band=[&](int a,int b) {
    const bool pointA=beads[size_t(a)].rho<=0, pointB=beads[size_t(b)].rho<=0;
    if(pointA && pointB) return;
    const quint32 A=rim(a), B=rim(b);
    for(int k=0;k<around;++k) {
      const quint32 here=quint32(k), next=quint32((k+1)%around);
      if(pointA) face(out,A,B+here,B+next);
      else if(pointB) face(out,B,A+here,A+next);
      else { face(out,A+here,A+next,B+next); face(out,A+here,B+next,B+here); }
    }
  };
  // A run of beads may share one band while it stays straight, evenly lit and facing one way.
  auto spans=[&](const std::vector<int> &path,size_t a,size_t c) {
    const Bead &from=beads[size_t(path[a])], &to=beads[size_t(path[c])];
    const float dx=to.rho-from.rho, dy=to.y-from.y, run=hypot2(dx,dy);
    if(run>.045f) return false;
    for(size_t k=a+1;k<=c;++k) {
      const Bead &bead=beads[size_t(path[k])];
      if(dot(bead.facing,from.facing)<.988f || std::abs(bead.lit-from.lit)>.04f) return false;
      for(size_t angle=0;angle<bead.light.size();++angle)
        if(std::abs(bead.light[angle]-from.light[angle])>.04f) return false;
      if(k<c && std::abs(dx*(bead.y-from.y)-dy*(bead.rho-from.rho))>.0003f*run) return false;
    }
    return true;
  };
  // Outlines run from pole to pole, or close on themselves as a hoop's does; poles are walked first.
  for(int pass=0;pass<2;++pass) for(int start=0;start<int(beads.size());++start) {
    if(pass==0 && beads[size_t(start)].rho>0) continue;
    for(;;) {
      std::vector<int> path{start};
      for(int next=follow(start);next>=0;next=follow(next)) path.push_back(next);
      if(path.size()<2) break;
      for(size_t a=0;a+1<path.size();) {
        size_t b=a+1;
        while(b+1<path.size() && spans(path,a,b+1)) ++b;
        band(path[a],path[b]);
        a=b;
      }
    }
  }
}
}

SculptFigure Figures::part(int design,int kind,int part) {
  const std::vector<Mould> moulds=design==0 ? Orbital::moulds(kind,part) : design==1 ? Atelier::moulds(kind,part) : Candy::moulds(kind,part);
  SculptFigure figure;
  for(const Mould &mould:moulds) {
    if(mould.turned) turn(mould,figure);
    // Stepped panel fields in the other sets are discontinuous and cannot guide edge fitting.
    else cast(mould,figure,design==1);
  }
  return figure;
}
