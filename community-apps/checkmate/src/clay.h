#pragma once
#include <algorithm>
#include <cmath>
#include <initializer_list>
#include <utility>
#include <vector>

// Modelling clay for the sculpted sets: the volumes figures are built from, measured as
// distances that are negative inside, and the cut that turns such a field into a closed mesh.
namespace Clay {
constexpr float pi = 3.14159265358979323846f;

struct P { float x=0,y=0,z=0; };
inline P operator+(P a,P b) { return {a.x+b.x,a.y+b.y,a.z+b.z}; }
inline P operator-(P a,P b) { return {a.x-b.x,a.y-b.y,a.z-b.z}; }
inline P operator*(P a,float s) { return {a.x*s,a.y*s,a.z*s}; }
inline float dot(P a,P b) { return a.x*b.x+a.y*b.y+a.z*b.z; }
inline P cross(P a,P b) { return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x}; }
inline float length(P a) { return std::sqrt(dot(a,a)); }
inline P normalize(P a) { const float l=length(a); return l>1e-9f ? a*(1/l) : P{0,1,0}; }
inline P mix(P a,P b,float t) { return a+(b-a)*t; }
inline float hypot2(float a,float b) { return std::sqrt(a*a+b*b); }
inline float saturate(float v) { return std::min(1.f,std::max(0.f,v)); }
inline float smooth(float a,float b,float v) { const float t=saturate((v-a)/(b-a)); return t*t*(3-2*t); }
inline float smin(float a,float b,float k) {
  if(k<=0) return std::min(a,b);
  const float h=std::max(k-std::abs(a-b),0.f)/k;
  return std::min(a,b)-h*h*k*.25f;
}
inline float smax(float a,float b,float k) { return -smin(-a,-b,k); }

// Distances to the volumes the figures are built from; negative inside.
inline float ball(P p,P c,float r) { return length(p-c)-r; }
inline float egg(P p,P c,P r) {
  const P q=p-c, a{q.x/r.x,q.y/r.y,q.z/r.z}, b{a.x/r.x,a.y/r.y,a.z/r.z};
  const float k0=length(a), k1=length(b);
  return k1>1e-6f ? k0*(k0-1)/k1 : -std::min(r.x,std::min(r.y,r.z));
}
// A limb between two balls of different sizes.
inline float horn(P p,P a,P b,float ra,float rb) {
  const P ba=b-a, pa=p-a;
  const float l2=dot(ba,ba), rr=ra-rb, a2=l2-rr*rr, il2=1/l2;
  const float y=dot(pa,ba), z=y-l2;
  const P w=pa*l2-ba*y;
  const float x2=dot(w,w), y2=y*y*l2, z2=z*z*l2;
  const float k=(rr>0 ? 1.f : rr<0 ? -1.f : 0.f)*rr*rr*x2;
  if((z>0 ? 1.f : z<0 ? -1.f : 0.f)*a2*z2>k) return std::sqrt(x2+z2)*il2-rb;
  if((y>0 ? 1.f : y<0 ? -1.f : 0.f)*a2*y2<k) return std::sqrt(x2+y2)*il2-ra;
  return (std::sqrt(std::max(0.f,x2*a2*il2))+y*rr)*il2-ra;
}
inline float brick(P q,P half,float round) {
  const P d{std::abs(q.x)-half.x+round,std::abs(q.y)-half.y+round,std::abs(q.z)-half.z+round};
  const P outside{std::max(d.x,0.f),std::max(d.y,0.f),std::max(d.z,0.f)};
  return length(outside)+std::min(std::max(d.x,std::max(d.y,d.z)),0.f)-round;
}
inline float hoop(P q,float radius,float tube) { return hypot2(hypot2(q.x,q.z)-radius,q.y)-tube; }
inline float arch(float x,float y,float half,float sill,float spring) {
  return y>spring ? hypot2(x,y-spring)-half : std::max(std::abs(x)-half,sill-y);
}
// A turned disc about the axis, its rims rounded.
inline float disc(P p,float height,float radius,float half,float round) {
  const float a=hypot2(p.x,p.z)-radius+round, b=std::abs(p.y-height)-half+round;
  return std::min(std::max(a,b),0.f)+hypot2(std::max(a,0.f),std::max(b,0.f))-round;
}
// A cord through a run of distinct points, tapering from one girth to another.
inline float strand(P p,const std::vector<P> &path,float from,float to) {
  const float last=float(path.size())-1;
  float d=1e9f;
  for(size_t i=0;i+1<path.size();++i) d=std::min(d,horn(p,path[i],path[i+1],from+(to-from)*float(i)/last,from+(to-from)*float(i+1)/last));
  return d;
}
// A cross with flared arms, flat to the front.
inline float pattee(P p,P centre,float reach,float waist,float flare,float depth) {
  const float x=std::abs(p.x-centre.x), y=std::abs(p.y-centre.y), along=std::max(x,y), aside=std::min(x,y);
  const float a=std::max(aside-waist-(flare-waist)*along/reach,along-reach)+.006f, b=std::abs(p.z-centre.z)-depth+.006f;
  return std::min(std::max(a,b),0.f)+hypot2(std::max(a,0.f),std::max(b,0.f))-.006f;
}
// Squeeze space sideways so a round volume measured there comes out oval; scale its distance by the same factor.
inline P narrow(P p,float factor) { return {p.x/factor,p.y,p.z}; }
// Turn the nearest of `count` evenly spaced copies, the first at `first` radians, to the front (-z).
inline P wedge(P p,int count,float first) {
  const float step=2*pi/count, rho=hypot2(p.x,p.z);
  float angle=std::atan2(p.z,p.x)-first;
  angle-=step*std::round(angle/step);
  angle-=pi/2;
  return {rho*std::cos(angle),p.y,rho*std::sin(angle)};
}

struct Frame {
  P o,u,v,w;
  Frame(P origin,P up,P front) : o(origin) { v=normalize(up); w=normalize(front-v*dot(front,v)); u=cross(v,w); }
  P local(P p) const { const P q=p-o; return {dot(q,u),dot(q,v),dot(q,w)}; }
  P world(P q) const { return o+u*q.x+v*q.y+w*q.z; }
};

// A turned body: a (radius,height) outline from the axis and back, smoothed and revolved.
// Drawn taut, a short chamfer beside a long face cannot swing out into a lip.
struct Lathe {
  std::vector<float> r,y;
  float reach=0,low=0,high=0;
  Lathe(std::initializer_list<std::pair<float,float>> outline,bool taut=false) {
    const std::vector<std::pair<float,float>> knots(outline);
    const int count=int(knots.size());
    auto knot=[&](int i) { return knots[size_t(std::clamp(i,0,count-1))]; };
    auto spline=[](float a,float b,float c,float d,float t) { return .5f*(2*b+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t); };
    // The way through a knot, no longer than the shorter run beside it.
    auto lean=[&](int i) {
      const auto a=knot(i-1), b=knot(i), c=knot(i+1);
      std::pair<float,float> way{(c.first-a.first)*.5f,(c.second-a.second)*.5f};
      const float most=std::min(hypot2(b.first-a.first,b.second-a.second),hypot2(c.first-b.first,c.second-b.second));
      const float size=hypot2(way.first,way.second);
      if(size>most) way={way.first*most/size,way.second*most/size};
      return way;
    };
    for(int i=0;i+1<count;++i) for(int j=0;j<4;++j) {
      const auto a=knot(i-1), b=knot(i), c=knot(i+1), d=knot(i+2);
      const float t=j/4.f;
      if(!taut) {
        r.push_back(std::max(0.f,spline(a.first,b.first,c.first,d.first,t)));
        y.push_back(spline(a.second,b.second,c.second,d.second,t));
        continue;
      }
      const auto out=lean(i), in=lean(i+1);
      const float t2=t*t, t3=t2*t, h00=2*t3-3*t2+1, h10=t3-2*t2+t, h01=3*t2-2*t3, h11=t3-t2;
      r.push_back(std::max(0.f,h00*b.first+h10*out.first+h01*c.first+h11*in.first));
      y.push_back(h00*b.second+h10*out.second+h01*c.second+h11*in.second);
    }
    r.push_back(knots.back().first); y.push_back(knots.back().second);
    low=high=y.front();
    for(size_t i=0;i<r.size();++i) { reach=std::max(reach,r[i]); low=std::min(low,y[i]); high=std::max(high,y[i]); }
  }
  float distance(float rho,float height) const {
    const float outside=hypot2(std::max(rho-reach,0.f),std::max(std::max(low-height,height-high),0.f));
    if(outside>.25f) return outside;
    float best=1e9f;
    bool inside=false;
    const size_t count=r.size();
    for(size_t i=0,j=count-1;i<count;j=i++) {
      const float ex=r[j]-r[i], ey=y[j]-y[i], wx=rho-r[i], wy=height-y[i];
      // The closing edge runs along the axis and is not part of the surface.
      if(i>0) {
        const float ee=ex*ex+ey*ey, t=ee>1e-12f ? std::clamp((wx*ex+wy*ey)/ee,0.f,1.f) : 0.f;
        const float bx=wx-ex*t, by=wy-ey*t;
        best=std::min(best,bx*bx+by*by);
      }
      const bool above=height>=y[i], below=height<y[j], left=ex*wy>ey*wx;
      if((above && below && left) || (!above && !below && !left)) inside=!inside;
    }
    return (inside ? -1.f : 1.f)*std::sqrt(best);
  }
};

// Join surface cells across crossed grid edges; settle seats and stores each vertex.
// Triangle receives corner indices in settlement order.
template<typename Distance,typename Settle,typename Triangle>
void shell(const Distance &distance,P low,P high,float cell,const Settle &settle,const Triangle &triangle) {
  const int nx=int(std::ceil((high.x-low.x)/cell))+1, ny=int(std::ceil((high.y-low.y)/cell))+1, nz=int(std::ceil((high.z-low.z)/cell))+1;
  const int block=4, bx=(nx+block-2)/block, by=(ny+block-2)/block, bz=(nz+block-2)/block;
  auto at=[&](int i,int j,int k) { return size_t(i)+size_t(nx)*(size_t(j)+size_t(ny)*size_t(k)); };
  auto place=[&](float i,float j,float k) { return P{low.x+i*cell,low.y+j*cell,low.z+k*cell}; };
  auto last=[&](int b,int n) { return std::min((b+1)*block,n-1); };
  std::vector<float> value(size_t(nx)*size_t(ny)*size_t(nz));
  std::vector<char> busy(size_t(bx)*size_t(by)*size_t(bz)), known(value.size());
  // Blocks far from any surface take one sample; only the shell around the clay is measured finely.
  const float reach=block*cell*1.1f+.04f;
  for(int c=0;c<bz;++c) for(int b=0;b<by;++b) for(int a=0;a<bx;++a) {
    const float d=distance(place((a+.5f)*block,(b+.5f)*block,(c+.5f)*block));
    if(std::abs(d)<reach) { busy[size_t(a)+size_t(bx)*(size_t(b)+size_t(by)*size_t(c))]=1; continue; }
    for(int k=c*block;k<=last(c,nz);++k) for(int j=b*block;j<=last(b,ny);++j) for(int i=a*block;i<=last(a,nx);++i) value[at(i,j,k)]=d;
  }
  for(int c=0;c<bz;++c) for(int b=0;b<by;++b) for(int a=0;a<bx;++a) {
    if(!busy[size_t(a)+size_t(bx)*(size_t(b)+size_t(by)*size_t(c))]) continue;
    for(int k=c*block;k<=last(c,nz);++k) for(int j=b*block;j<=last(b,ny);++j) for(int i=a*block;i<=last(a,nx);++i) {
      const size_t sample=at(i,j,k);
      if(known[sample]) continue;
      known[sample]=1;
      value[sample]=distance(place(float(i),float(j),float(k)));
    }
  }
  // The faces of the grid count as air, so the mesh always closes.
  for(int k=0;k<nz;++k) for(int j=0;j<ny;++j) for(int i=0;i<nx;++i)
    if(i==0 || j==0 || k==0 || i==nx-1 || j==ny-1 || k==nz-1) value[at(i,j,k)]=std::max(value[at(i,j,k)],cell);

  static const int corner[8][3]={{0,0,0},{1,0,0},{0,1,0},{1,1,0},{0,0,1},{1,0,1},{0,1,1},{1,1,1}};
  static const int edge[12][2]={{0,1},{2,3},{4,5},{6,7},{0,2},{1,3},{4,6},{5,7},{0,4},{1,5},{2,6},{3,7}};
  std::vector<int> owner(value.size(),-1);
  std::vector<P> spots;
  for(int k=0;k+1<nz;++k) for(int j=0;j+1<ny;++j) for(int i=0;i+1<nx;++i) {
    float v[8];
    int inside=0;
    for(int c=0;c<8;++c) { v[c]=value[at(i+corner[c][0],j+corner[c][1],k+corner[c][2])]; inside+=v[c]<0; }
    if(inside==0 || inside==8) continue;
    P sum;
    int crossings=0;
    for(const auto &e:edge) {
      const float a=v[e[0]], b=v[e[1]];
      if((a<0)==(b<0)) continue;
      const float t=a/(a-b);
      const int *from=corner[e[0]], *to=corner[e[1]];
      sum=sum+P{from[0]+(to[0]-from[0])*t,from[1]+(to[1]-from[1])*t,from[2]+(to[2]-from[2])*t};
      ++crossings;
    }
    owner[at(i,j,k)]=int(spots.size());
    spots.push_back(place(i+sum.x/crossings,j+sum.y/crossings,k+sum.z/crossings));
  }

  for(P &spot:spots) spot=settle(spot);
  auto quad=[&](int a,int b,int c,int d,bool flip) {
    if(a<0 || b<0 || c<0 || d<0) return;
    if(flip) std::swap(b,d);
    const P ac=spots[size_t(a)]-spots[size_t(c)], bd=spots[size_t(b)]-spots[size_t(d)];
    if(dot(ac,ac)<=dot(bd,bd)) { triangle(a,b,c); triangle(a,c,d); }
    else { triangle(a,b,d); triangle(b,c,d); }
  };
  for(int k=0;k+1<nz;++k) for(int j=0;j+1<ny;++j) for(int i=0;i+1<nx;++i) {
    const bool solid=value[at(i,j,k)]<0;
    if(j>0 && k>0 && solid!=(value[at(i+1,j,k)]<0)) quad(owner[at(i,j-1,k-1)],owner[at(i,j,k-1)],owner[at(i,j,k)],owner[at(i,j-1,k)],!solid);
    if(i>0 && k>0 && solid!=(value[at(i,j+1,k)]<0)) quad(owner[at(i-1,j,k-1)],owner[at(i-1,j,k)],owner[at(i,j,k)],owner[at(i,j,k-1)],!solid);
    if(i>0 && j>0 && solid!=(value[at(i,j,k+1)]<0)) quad(owner[at(i-1,j-1,k)],owner[at(i,j-1,k)],owner[at(i,j,k)],owner[at(i-1,j,k)],!solid);
  }
}
}
