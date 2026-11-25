#include "woodland.h"
#include <thread>
#include "clay.h"
#include <algorithm>
#include <cmath>
#include <functional>
#include <initializer_list>
#include <map>
#include <memory>
#include <utility>

// Moss & Myth is modelled like clay: each figure is a field of blended volumes, cut into
// one closed mesh and painted per vertex, the way a carved miniature is finished by hand.
namespace {
using namespace Clay;

// A carved leaf: a pointed oval slab with a midrib groove, bent to lie on a body.
struct Leaf {
  Frame f;
  float len,wid,thick,curl,cup,vr,vd;
  Leaf(P base,P tip,P out,float halfWidth,float thickness,float bend=0,float wrap=0)
    : f((base+tip)*.5f,tip-base,out), len(length(tip-base)*.5f), wid(halfWidth), thick(thickness), curl(bend), cup(wrap),
      vr((len*len/wid+wid)*.5f), vd((len*len/wid-wid)*.5f) {}
  float distance(P p,float *outline=nullptr) const {
    const P q=f.local(p);
    const float far=dot(q,q), bound=len+.07f;
    if(far>(bound+.2f)*(bound+.2f)) return std::sqrt(far)-bound;
    const float px=std::abs(q.x), py=std::abs(q.y);
    const float along=std::min(1.f,py/len), across=std::min(1.f,px/wid);
    const float z=q.z+curl*along*along+cup*across*across;
    const float edge=(py-len)*vd>px*len ? hypot2(px,py-len) : hypot2(px+vd,py)-vr;
    const float rib=thick*(1-.5f*std::exp(-q.x*q.x/(.09f*wid*wid)));
    const float a=edge+.006f, b=std::abs(z)-rib+.006f;
    if(outline) *outline=edge;
    return std::min(std::max(a,b),0.f)+hypot2(std::max(a,0.f),std::max(b,0.f))-.006f;
  }
};

// Paint for the pale side and the dark side; glow keeps a colour bright inside a recess.
struct Tone { P light,dark; float glow=0; };
P pigment(unsigned hex) {
  auto channel=[&](int shift) { return std::pow(float((hex>>shift)&255)/255.f,2.2f); };
  return {channel(16),channel(8),channel(0)};
}
Tone tone(unsigned light,unsigned dark,float glow=0) { return {pigment(light),pigment(dark),glow}; }
// The board's key light and tone mapping brighten and saturate paint a good deal, so these are
// mixed darker and greyer than the ivory, chestnut and olive they come out as on the board.
const Tone wood=tone(0xb2a07a,0x6e4b33), footing=tone(0x7f705a,0x513827), hollow=tone(0x6c5f4c,0x462f22);
const Tone skin=tone(0xb8a682,0x8f775a), blush=tone(0x9a6f60,0x83614f), ink=tone(0x2a1a10,0x23150d), lash=tone(0x574332,0x402b1f);
const Tone acorn=tone(0x837054,0x816847), husk=tone(0x6c573c,0x674f32);
const Tone leaf=tone(0x595f39,0x645c39), leafEdge=tone(0x737351,0x786e4c), sprig=tone(0x75755a,0x8e836c);
const Tone fur=tone(0xb6a580,0x7c4f2f), furPale=tone(0xc4b898,0xb8a886), sock=tone(0xa39069,0x573623);
const Tone plume=tone(0xb2a07a,0x6c4e36), down=tone(0xc2b592,0x8c775a), gold=tone(0x85704c,0x836940);
const Tone tress=tone(0x6c4e36,0x5a3927), whisker=tone(0xc6bb9e,0xbcae8e), felt=tone(0x555c36,0x575a36);
const Tone petal=tone(0xc8bea4,0xc2b596), pollen=tone(0x8a7339,0x8a7339);
const Tone antler=tone(0x7f6c51,0x7d6748), staff=tone(0x67543c,0x4c3627);
const Tone doorway=tone(0x432e21,0xa87a30,.85f), fungus=tone(0x7f5f46,0x835c3c), stalk=tone(0xbdb193,0xb5a685);

// The clay being built up at one point in space: its distance and, when asked, its paint.
struct Field {
  float d=1e9f, glow=0;
  bool paint=false;
  P light,dark;
  void coat(const Tone &with,float amount) {
    light=mix(light,with.light,amount); dark=mix(dark,with.dark,amount); glow+=(with.glow-glow)*amount;
  }
  void add(float shape,const Tone &with,float blend=0) {
    if(paint) coat(with,smooth(-.008f,.008f,d-shape));
    d=smin(d,shape,blend);
  }
  void cut(float shape,const Tone &with,float blend=0) {
    if(paint) coat(with,smooth(-.008f,.008f,-shape-d));
    d=smax(d,-shape,blend);
  }
  void tint(float shape,const Tone &with,float soft=.012f,float amount=1) {
    if(paint) coat(with,amount*smooth(soft,-soft,shape));
  }
};
using Sculptor=std::function<void(P,Field &)>;

float measure(const Sculptor &clay,P p) { Field f; clay(p,f); return f.d; }
P gradient(const Sculptor &clay,P p,float e) {
  const P a{1,-1,-1}, b{-1,-1,1}, c{-1,1,-1}, d{1,1,1};
  return normalize(a*measure(clay,p+a*e)+b*measure(clay,p+b*e)+c*measure(clay,p+c*e)+d*measure(clay,p+d*e));
}
// Walk in from outside until the clay is met, so details sit on the carved surface.
P land(const Sculptor &clay,P from,P toward) {
  toward=normalize(toward);
  float travelled=0;
  for(int i=0;i<240 && travelled<2;++i) {
    const float d=measure(clay,from+toward*travelled);
    if(d<.0015f) break;
    travelled+=std::max(.002f,d*.6f);
  }
  return from+toward*travelled;
}

void foliage(Field &f,const Leaf &blade,P p,const Tone &body,const Tone &edge,float blend=.006f) {
  float outline=-1;
  const float d=blade.distance(p,&outline);
  f.add(d,body,blend);
  if(f.paint && d<.02f) f.tint(std::max(d-.012f,-outline-.02f),edge,.008f,.75f);
}
// A leaf hung around the figure's axis, `turn` degrees from +x toward +z, between two (radius,height) ends.
Leaf drape(float turn,float baseRadius,float baseHeight,float tipRadius,float tipHeight,float halfWidth,float thickness,float bend,float wrap) {
  const float a=turn*pi/180;
  const P out{std::cos(a),0,std::sin(a)};
  return Leaf(out*baseRadius+P{0,baseHeight,0},out*tipRadius+P{0,tipHeight,0},out*(baseHeight-tipHeight)+P{0,tipRadius-baseRadius,0},halfWidth,thickness,bend,wrap);
}
// A leaf laid on the clay where a ray lands, pointing along `along`.
Leaf stick(const Sculptor &clay,P from,P toward,P along,float halfLength,float halfWidth,float thickness) {
  const P hit=land(clay,from,toward), normal=gradient(clay,hit,.01f);
  const P axis=normalize(along-normal*dot(along,normal)), centre=hit+normal*.005f;
  return Leaf(centre-axis*halfLength,centre+axis*halfLength,normal,halfWidth,thickness);
}

struct Carving {
  std::vector<P> points,normals,light,dark;
  std::vector<quint32> indices;
  quint32 vertex(P point,P normal,P pale,P deep) {
    points.push_back(point); normals.push_back(normal); light.push_back(pale); dark.push_back(deep);
    return quint32(points.size()-1);
  }
  quint32 vertex(P point,P normal,const Tone &with) { return vertex(point,normal,with.light,with.dark); }
  // Qt flips back-face normals, so winding must agree with the sculpted normals.
  void triangle(quint32 a,quint32 b,quint32 c) {
    const P face=cross(points[b]-points[a],points[c]-points[a]);
    if(dot(face,normals[a]+normals[b]+normals[c])<0) std::swap(b,c);
    indices.push_back(a); indices.push_back(b); indices.push_back(c);
  }
  // Crisp painted details are small closed solids pressed into the carving.
  void orb(P centre,P u,P v,P w,P radii,const Tone &with) {
    const int rings=6, sides=10;
    auto place=[&](float x,float y,float z) {
      return vertex(centre+u*(x*radii.x)+v*(y*radii.y)+w*(z*radii.z),normalize(u*(x/radii.x)+v*(y/radii.y)+w*(z/radii.z)),with);
    };
    const quint32 top=place(0,1,0);
    for(int j=1;j<rings;++j) for(int i=0;i<sides;++i) {
      const float polar=pi*j/rings, around=2*pi*i/sides;
      place(std::sin(polar)*std::cos(around),std::cos(polar),std::sin(polar)*std::sin(around));
    }
    const quint32 bottom=place(0,-1,0), first=top+1, last=first+quint32((rings-2)*sides);
    for(int i=0;i<sides;++i) {
      const quint32 here=quint32(i), next=quint32((i+1)%sides);
      triangle(top,first+here,first+next);
      triangle(bottom,last+here,last+next);
      for(int j=0;j+2<rings;++j) {
        const quint32 row=first+quint32(j*sides), below=row+quint32(sides);
        triangle(row+here,row+next,below+next);
        triangle(row+here,below+next,below+here);
      }
    }
  }
  void cord(const std::vector<P> &path,const std::vector<P> &outward,float radius,const Tone &with) {
    const int sides=6, count=int(path.size());
    if(count<2) return;
    const quint32 first=quint32(points.size());
    for(int i=0;i<count;++i) {
      const P along=normalize(path[size_t(std::min(i+1,count-1))]-path[size_t(std::max(i-1,0))]);
      const P a=normalize(outward[size_t(i)]-along*dot(outward[size_t(i)],along)), b=cross(along,a);
      const float girth=radius*(.5f+.5f*std::sin(pi*(i+.5f)/count));
      for(int j=0;j<sides;++j) {
        const float angle=2*pi*j/sides;
        const P normal=a*std::cos(angle)+b*std::sin(angle);
        vertex(path[size_t(i)]+normal*girth,normal,with);
      }
    }
    for(int i=0;i+1<count;++i) for(int j=0;j<sides;++j) {
      const quint32 a=first+quint32(i*sides+j), b=first+quint32(i*sides+(j+1)%sides), c=a+quint32(sides), d=b+quint32(sides);
      triangle(a,b,d); triangle(a,d,c);
    }
    const P front=normalize(path[0]-path[1]), back=normalize(path[size_t(count-1)]-path[size_t(count-2)]);
    const quint32 start=vertex(path[0]+front*(radius*.3f),front,with), end=vertex(path[size_t(count-1)]+back*(radius*.3f),back,with);
    for(int j=0;j<sides;++j) {
      triangle(start,first+quint32(j),first+quint32((j+1)%sides));
      triangle(end,first+quint32((count-1)*sides+j),first+quint32((count-1)*sides+(j+1)%sides));
    }
  }
  // A lash or a smile: an arc drawn onto whatever the ray `toward` meets.
  void stroke(const Sculptor &clay,P centre,P toward,float radius,float from,float to,float thickness,const Tone &with) {
    toward=normalize(toward);
    const P side=normalize(cross({0,1,0},toward)), up=cross(toward,side);
    std::vector<P> path,outward;
    for(int i=0;i<=10;++i) {
      const float angle=(from+(to-from)*i/10)*pi/180;
      path.push_back(land(clay,centre-toward*.3f+side*(radius*std::cos(angle))+up*(radius*std::sin(angle)),toward)-toward*(thickness*.3f));
      outward.push_back(toward*-1.f);
    }
    cord(path,outward,thickness,with);
  }
  void blossom(P centre,P normal,float size,float turn=0) {
    const P n=normalize(normal);
    const P side=normalize(cross(n,std::abs(n.y)<.9f ? P{0,1,0} : P{1,0,0})), up=cross(n,side);
    for(int i=0;i<5;++i) {
      const float angle=turn+2*pi*i/5;
      const P out=side*std::cos(angle)+up*std::sin(angle);
      orb(centre+out*(size*.58f)+n*(size*.1f),out,n,cross(n,out),{size*.46f,size*.2f,size*.36f},petal);
    }
    orb(centre+n*(size*.2f),side,n,up,{size*.27f,size*.24f,size*.27f},pollen);
  }
};

// Cut the clay into a closed mesh, each vertex painted and shaded where it stands.
void carve(const Sculptor &clay,P low,P high,float cell,Carving &out) {
  const quint32 first=quint32(out.points.size());
  shell([&](P p) { return measure(clay,p); },low,high,cell,[&](P spot) {
    // Each vertex settles onto the true surface, so faces are smooth and details stay crisp.
    spot=spot-gradient(clay,spot,cell*.4f)*std::clamp(measure(clay,spot),-cell*.6f,cell*.6f);
    const P normal=gradient(clay,spot,cell*.4f);
    Field f;
    f.paint=true;
    clay(spot,f);
    // Crevices are shaded where they are carved, warm like stained wood, with a little grain.
    const float open=saturate(.55f*(measure(clay,spot+normal*.03f)-f.d)/.03f+.45f*(measure(clay,spot+normal*.09f)-f.d)/.09f);
    const float grain=1+.04f*std::sin(38*(spot.x*.8f+spot.z*.6f)+2.5f*std::sin(spot.y*7));
    const float shade=(.42f+.58f*open)*grain, lit=shade+(1-shade)*f.glow;
    const P wash{std::pow(lit,.9f),lit,std::pow(lit,1.15f)};
    out.vertex(spot,normal,{f.light.x*wash.x,f.light.y*wash.y,f.light.z*wash.z},{f.dark.x*wash.x,f.dark.y*wash.y,f.dark.z*wash.z});
    return spot;
  },[&](int a,int b,int c) { out.triangle(first+quint32(a),first+quint32(b),first+quint32(c)); });
}

struct Statue {
  Sculptor clay;
  P low,high;
  float cell=.02f;
  std::function<void(const Sculptor &,Carving &)> details;
};

const Lathe plinth({{0,0},{.31f,0},{.352f,.016f},{.36f,.05f},{.346f,.08f},{.318f,.092f},{.322f,.112f},{.305f,.14f},{.26f,.155f},{0,.155f}});
void stand(Field &f,P p,float scale=1) {
  if(p.y>.4f) return;
  f.add(plinth.distance(hypot2(p.x,p.z)/scale,p.y/scale)*scale,p.y<.088f*scale ? footing : wood);
}

// A sleepy acorn child: round face under a cross-hatched cap pushed back, in a collar of leaves.
Statue pawn() {
  const Lathe body({{0,.11f},{.2f,.12f},{.224f,.17f},{.207f,.27f},{.167f,.38f},{.126f,.46f},{.105f,.5f},{0,.52f}});
  const Lathe dome({{0,-.03f},{.19f,-.02f},{.236f,0},{.254f,.03f},{.248f,.07f},{.226f,.13f},{.184f,.19f},{.12f,.238f},{.05f,.262f},{0,.268f}});
  const Frame crown({0,.672f,-.012f},{0,.978f,.208f},{0,0,1});
  const Leaf mantle({0,.515f,-.085f},{0,.205f,-.285f},{0,.2f,-.31f},.105f,.026f,.02f,.03f);
  const Leaf ruff({0,.53f,-.09f},{0,.335f,-.238f},{0,.148f,-.195f},.08f,.023f,.012f,.02f);
  Statue statue;
  statue.low={-.37f,-.03f,-.37f}; statue.high={.37f,1.08f,.37f}; statue.cell=.0175f;
  statue.clay=[=](P p,Field &f) {
    stand(f,p,.84f);
    if(p.y<.75f) {
      f.add(body.distance(hypot2(p.x,p.z),p.y),wood,.02f);
      foliage(f,mantle,wedge(p,6,-pi/2),leaf,leafEdge);
      foliage(f,ruff,wedge(p,6,-pi/3),leaf,leafEdge);
    }
    if(p.y>.3f) {
      const P m{std::abs(p.x),p.y,p.z};
      f.add(egg(p,{0,.66f,-.012f},{.222f,.2f,.212f}),skin,.03f);
      f.add(ball(m,{.105f,.618f,-.118f},.082f),skin,.05f);
      f.add(ball(p,{0,.636f,-.226f},.024f),skin,.02f);
      if(f.paint) f.tint(ball(m,{.122f,.612f,-.172f},.045f),blush,.03f,.8f);
      const P q=crown.local(p);
      const float around=hypot2(q.x,q.z);
      float cup=dome.distance(around,q.y);
      if(cup<.05f) {
        const float theta=std::atan2(q.z,q.x), phi=std::atan2(around,q.y+.03f);
        const float groove=std::min(std::abs(std::sin(7*theta+9*phi)),std::abs(std::sin(7*theta-9*phi)));
        cup+=.011f*(1-smooth(0,.5f,groove))*smooth(.045f,.09f,q.y);
      }
      f.add(cup,acorn);
      f.add(horn(q,{0,.25f,0},{.022f,.335f,.012f},.034f,.027f),husk,.012f);
    }
  };
  statue.details=[](const Sculptor &clay,Carving &out) {
    for(float side:{-1.f,1.f}) out.stroke(clay,{side*.09f,.68f,-.2f},{0,0,1},.045f,205,335,.013f,lash);
    out.stroke(clay,{0,.592f,-.2f},{0,0,1},.03f,215,325,.009f,lash);
  };
  return statue;
}

// A seated fox: upright chest, long muzzle, tall ears, and a brush curled round to its paws.
Statue fox() {
  auto leaves=std::make_shared<std::vector<Leaf>>();
  const P a{0,.27f,.3f}, b{.2f,.25f,.27f}, c{.31f,.27f,.1f}, d{.33f,.35f,-.085f}, e{.285f,.5f,-.21f}, tip{.23f,.66f,-.255f};
  Statue statue;
  statue.low={-.41f,-.03f,-.45f}; statue.high={.51f,1.43f,.44f}; statue.cell=.02f;
  statue.clay=[=](P p,Field &f) {
    stand(f,p);
    const P m{std::abs(p.x),p.y,p.z};
    if(p.y<1.3f) {
      f.add(egg(p,{0,.37f,.09f},{.255f,.225f,.255f}),fur,.03f);
      f.add(horn(p,{0,.42f,.05f},{0,.8f,-.07f},.225f,.158f),fur,.05f);
      f.add(egg(m,{.185f,.31f,.02f},{.105f,.15f,.165f}),fur,.04f);
      f.add(egg(m,{.185f,.19f,-.14f},{.058f,.044f,.095f}),sock,.02f);
      f.add(horn(m,{.088f,.66f,-.13f},{.1f,.25f,-.2f},.076f,.06f),fur,.03f);
      f.add(egg(m,{.1f,.19f,-.222f},{.064f,.045f,.076f}),sock,.02f);
      f.add(horn(p,{0,.78f,-.06f},{0,.96f,-.09f},.15f,.125f),fur,.04f);
      f.add(egg(p,{0,.7f,-.15f},{.135f,.17f,.09f}),furPale,.04f);
      f.add(horn(p,{0,.66f,-.2f},{0,.5f,-.205f},.07f,.022f),furPale,.03f);
    }
    if(p.y<.95f && p.x>-.25f) {
      float brush=smin(horn(p,a,b,.075f,.12f),horn(p,b,c,.12f,.14f),.03f);
      brush=smin(brush,horn(p,c,d,.14f,.13f),.03f);
      brush=smin(brush,horn(p,d,e,.13f,.095f),.03f);
      float point=horn(p,e,tip,.095f,.024f);
      if(std::min(brush,point)<.04f) {
        // Locks of fur are combed along the brush.
        const float lock=.008f*(1-smooth(0,.5f,std::abs(std::sin(std::atan2(p.z-.05f,p.x-.05f)*9+p.y*16))));
        brush+=lock; point+=lock;
      }
      f.add(brush,fur,.03f);
      f.add(point,furPale,.03f);
    }
    if(p.y>.65f) {
      f.add(egg(p,{0,1.02f,-.1f},{.172f,.15f,.165f}),fur,.04f);
      f.add(horn(m,{.09f,.985f,-.09f},{.228f,.93f,-.05f},.085f,.022f),fur,.04f);
      f.add(horn(p,{0,.992f,-.2f},{0,.957f,-.365f},.082f,.04f),fur,.035f);
      if(f.paint) f.tint(egg(p,{0,.925f,-.17f},{.26f,.065f,.24f}),furPale,.02f);
      P ear=m-P{.105f,1.11f,-.05f};
      ear.z/=.55f;
      f.add(horn(ear,{0,0,0},{.05f,.25f,0},.078f,.028f)*.55f,fur,.03f);
      f.cut(egg(m,{.134f,1.215f,-.092f},{.036f,.092f,.03f}),furPale,.012f);
      if(f.paint) f.tint(ball(m,{.155f,1.36f,-.05f},.075f),sock,.03f,.9f);
    }
    for(const Leaf &blade:*leaves) foliage(f,blade,p,sprig,sprig,.004f);
  };
  // A carved sprig climbs each flank, the longer one on the side the brush leaves bare.
  const Sculptor clay=statue.clay;
  auto sprout=[&](float side,float height,float depth,P along) {
    leaves->push_back(stick(clay,{side*.7f,height,depth},{-side,0,0},along,.058f,.031f,.013f));
  };
  sprout(-1,.3f,.17f,{0,1,.7f}); sprout(-1,.385f,.06f,{0,1,-.7f}); sprout(-1,.47f,.15f,{0,1,.7f});
  sprout(-1,.555f,.04f,{0,1,-.7f}); sprout(-1,.66f,.08f,{0,1,.15f});
  sprout(1,.6f,.04f,{0,1,.7f}); sprout(1,.68f,-.03f,{0,1,-.7f}); sprout(1,.77f,.02f,{0,1,.2f});
  statue.details=[](const Sculptor &clay,Carving &out) {
    out.orb({0,.972f,-.4f},{1,0,0},{0,1,0},{0,0,1},{.031f,.025f,.027f},ink);
    for(float side:{-1.f,1.f}) {
      const P hit=land(clay,{side*.08f,1.048f,-.5f},{0,0,1}), normal=gradient(clay,hit,.01f);
      const P level=normalize(cross({0,1,0},normal)), rise=cross(normal,level);
      const P slant=normalize(level-rise*(side*.34f));
      out.orb(hit+normal*.003f,slant,cross(normal,slant),normal,{.032f,.02f,.012f},ink);
    }
  };
  return statue;
}

// A plump owl: wide head with ear tufts, heavy-lidded eyes in pale discs, leaves for wings.
Statue owl() {
  const Lathe body({{0,.12f},{.19f,.13f},{.25f,.22f},{.272f,.42f},{.264f,.6f},{.228f,.78f},{.17f,.89f},{0,.93f}});
  const Frame discs({.115f,.993f,-.197f},{0,1,0},{.38f,.06f,-1});
  const Leaf wing({.287f,.9f,-.01f},{.287f,.27f,.05f},{1,0,-.2f},.15f,.034f,.075f,.06f);
  const Leaf covert({.305f,.93f,-.05f},{.315f,.56f,-.02f},{1,0,-.3f},.1f,.03f,.04f,.04f);
  const Leaf bib({0,.87f,-.165f},{0,.69f,-.275f},{0,.11f,-.18f},.07f,.022f,.012f,.02f);
  Statue statue;
  statue.low={-.42f,-.03f,-.41f}; statue.high={.42f,1.37f,.41f}; statue.cell=.02f;
  statue.clay=[=](P p,Field &f) {
    stand(f,p);
    const P m{std::abs(p.x),p.y,p.z};
    float plump=body.distance(hypot2(p.x,p.z/.93f),p.y)*.93f;
    if(plump<.05f && p.z<.1f) {
      // Breast feathers are staggered rows of small pillows.
      const float row=std::floor((p.y-.2f)/.085f), v=(p.y-.2f)/.085f-row;
      const float u=std::atan2(p.z,p.x)*(12/(2*pi))+.5f*(int(row)&1), fu=u-std::floor(u)-.5f;
      plump-=.011f*std::sqrt(std::max(0.f,1-4*fu*fu-4*(v-.5f)*(v-.5f)))*smooth(.08f,-.08f,p.z)*smooth(.22f,.3f,p.y)*smooth(.8f,.7f,p.y);
    }
    f.add(plump,plume,.03f);
    if(f.paint) f.tint(egg(p,{0,.5f,-.2f},{.19f,.3f,.16f}),down,.03f,.85f);
    if(p.y<.8f) {
      f.add(horn(p,{0,.5f,.19f},{0,.21f,.295f},.09f,.05f),plume,.04f);
      f.add(egg(m,{.088f,.185f,-.215f},{.058f,.04f,.08f}),gold,.015f);
    }
    if(p.y>.55f) {
      f.add(egg(p,{0,1.0f,-.015f},{.262f,.215f,.232f}),plume,.06f);
      f.add(horn(m,{.15f,1.14f,0},{.235f,1.3f,.03f},.062f,.023f),plume,.04f);
      f.add(horn(m,{0,1.03f,-.228f},{.2f,1.16f,-.1f},.04f,.03f),plume,.03f);
      const P q=discs.local(m);
      f.add(smax(egg(q,{0,0,0},{.112f,.112f,.045f}),.2f-length(q-P{0,0,.233f}),.02f),down,.025f);
      f.add(egg(q,{0,.046f,.03f},{.07f,.03f,.034f}),down,.012f);
      f.add(horn(p,{0,.985f,-.238f},{0,.915f,-.28f},.042f,.015f),gold,.01f);
    }
    if(p.y>.45f && p.y<1.1f) foliage(f,bib,wedge(p,9,-pi/2),leaf,leafEdge);
    foliage(f,wing,m,leaf,leafEdge);
    foliage(f,covert,m,leaf,leafEdge);
  };
  statue.details=[=](const Sculptor &clay,Carving &out) {
    for(float side:{-1.f,1.f}) {
      auto mirror=[&](P p) { return P{side*p.x,p.y,p.z}; };
      const P u=mirror(discs.u), w=mirror(discs.w);
      const P hit=land(clay,mirror(discs.world({0,-.01f,.3f})),w*-1.f);
      out.orb(hit+w*.002f,u,discs.v,w,{.05f,.05f,.012f},gold);
      out.orb(hit+w*.01f,u,discs.v,w,{.038f,.038f,.02f},ink);
    }
  };
  return statue;
}

// A tree-stump tower: bark and roots, a lit doorway, a battlement, and mushrooms at its foot.
Statue rook() {
  const Lathe trunk({{0,.12f},{.325f,.13f},{.345f,.19f},{.305f,.31f},{.268f,.5f},{.258f,.72f},{.268f,.9f},{.305f,.99f},{.33f,1.04f},{.335f,1.1f},{.31f,1.125f},{0,1.125f}});
  const Frame shelf({.35f,.4f,-.2f},{.24f,1,-.14f},{0,0,1});
  const Frame button({-.335f,.275f,-.15f},{-.2f,1,-.1f},{0,0,1});
  auto leaves=std::make_shared<std::vector<Leaf>>();
  Statue statue;
  statue.low={-.46f,-.03f,-.42f}; statue.high={.5f,1.31f,.42f}; statue.cell=.018f;
  statue.clay=[=](P p,Field &f) {
    stand(f,p);
    const float rho=hypot2(p.x,p.z), theta=std::atan2(p.z,p.x);
    float bark=trunk.distance(rho,p.y);
    if(bark<.06f) {
      // The trunk is dressed in staggered courses of blocks, like a keep grown from a stump.
      const float course=(p.y-.3f)/.14f, row=std::floor(course), v=course-row;
      const float u=theta*(9/(2*pi))+.5f*(int(row)&1), h=u-std::floor(u);
      const float seam=std::min(std::min(v,1-v)*.14f,std::min(h,1-h)*(2*pi/9)*rho);
      bark+=.015f*(1-smooth(.005f,.024f,seam))*smooth(.24f,.31f,p.y)*smooth(1.0f,.95f,p.y);
    }
    f.add(bark,wood,.02f);
    if(p.y<.7f) f.add(horn(wedge(p,5,-pi/2+pi/5),{0,.4f,-.235f},{0,.17f,-.322f},.06f,.04f),wood,.045f);
    if(p.y>.7f) {
      f.add(hoop({p.x,p.y-.945f,p.z},.272f,.022f),wood,.02f);
      f.cut(smax(rho-.225f,1.0f-p.y,.02f),hollow,.01f);
      const P q=wedge(p,8,-pi/2);
      f.add(brick({q.x,q.y-1.19f,q.z+.283f},{.068f,.078f,.054f},.016f),wood,.012f);
    }
    if(p.z<0 && p.y<.95f) {
      const float door=arch(p.x,p.y,.082f,.17f,.44f), window=arch(p.x,p.y,.036f,.66f,.715f);
      f.add(smax(std::abs(door-.008f)-.024f,std::max(p.z+.2f,-.318f-p.z),.012f),acorn,.008f);
      f.cut(std::max(door,p.z+.185f),doorway,.006f);
      f.cut(std::max(window,p.z+.2f),doorway,.006f);
    }
    if(p.y<.8f) {
      if(p.x>0) {
        f.add(horn(p,{.27f,.2f,-.155f},{.345f,.39f,-.2f},.036f,.03f),stalk,.02f);
        const P q=shelf.local(p);
        f.add(smax(egg(q,{0,.012f,0},{.112f,.066f,.112f}),-q.y,.014f),fungus,.006f);
      } else {
        f.add(horn(p,{-.285f,.18f,-.12f},{-.332f,.265f,-.148f},.026f,.022f),stalk,.02f);
        const P q=button.local(p);
        f.add(smax(egg(q,{0,.008f,0},{.072f,.044f,.072f}),-q.y,.01f),fungus,.006f);
      }
      for(const Leaf &blade:*leaves) foliage(f,blade,p,leaf,leafEdge,.004f);
    }
  };
  const Sculptor clay=statue.clay;
  auto sprout=[&](float turn,float height,P along) {
    const float a=turn*pi/180;
    leaves->push_back(stick(clay,{std::cos(a)*.7f,height,std::sin(a)*.7f},{-std::cos(a),0,-std::sin(a)},along,.062f,.034f,.014f));
  };
  sprout(-123,.3f,{-.5f,1,0}); sprout(-116,.43f,{.3f,1,0}); sprout(-127,.53f,{-.4f,1,0});
  sprout(-60,.34f,{.5f,1,0}); sprout(-66,.46f,{-.2f,1,0});
  return statue;
}

// The woodland queen: a slender gown under a cloak of leaves, long hair, and a wreath of blossom.
Statue queen() {
  const Lathe gown({{0,.12f},{.32f,.13f},{.345f,.19f},{.325f,.32f},{.27f,.56f},{.205f,.82f},{.16f,1.0f},{.15f,1.1f},{.165f,1.18f},{.14f,1.25f},{.07f,1.29f},{0,1.3f}});
  const Frame wreath({0,1.572f,.02f},{0,.985f,.174f},{0,0,1});
  const P neck{0,1.3f,0};
  const float grown=1.16f;
  auto leaves=std::make_shared<std::vector<Leaf>>();
  for(int i=-2;i<=2;++i) {
    const float lift=(i&1) ? .018f : 0;
    leaves->push_back(drape(90+i*40.f,.17f+lift,1.22f,.345f+lift,.25f,.155f,.03f,.02f,.05f));
  }
  for(float turn:{60.f,120.f,0.f,180.f,-60.f,240.f}) {
    const float lift=turn==0 || turn==180 ? .015f : 0;
    leaves->push_back(drape(turn,.095f+lift,1.305f,.285f+lift,1.0f,.1f,.026f,.03f,.04f));
  }
  Statue statue;
  statue.low={-.44f,-.03f,-.41f}; statue.high={.44f,1.76f,.45f}; statue.cell=.02f;
  statue.clay=[=](P p,Field &f) {
    stand(f,p);
    const P m{std::abs(p.x),p.y,p.z};
    float dress=gown.distance(hypot2(p.x,p.z/.92f),p.y)*.92f;
    if(dress<.05f && p.y<.95f) dress+=.011f*std::sin(std::atan2(p.z,p.x)*11)*smooth(.9f,.45f,p.y);
    f.add(dress,wood,.02f);
    if(p.y>.65f && p.y<1.5f) {
      f.add(egg(p,{0,1.205f,0},{.195f,.07f,.11f}),wood,.05f);
      f.add(horn(m,{.165f,1.19f,0},{.185f,.97f,-.07f},.052f,.046f),wood,.03f);
      f.add(horn(m,{.185f,.97f,-.07f},{.05f,.9f,-.195f},.046f,.038f),wood,.02f);
      f.add(ball(p,{0,.897f,-.212f},.056f),skin,.012f);
    }
    for(const Leaf &blade:*leaves) foliage(f,blade,p,leaf,leafEdge);
    if(p.y>.3f) {
      // Head, hair and wreath are modelled at life size, then enlarged about the neck as a storybook figure's are.
      const P h=neck+(p-neck)*(1/grown), n{std::abs(h.x),h.y,h.z};
      float hair=smax(egg(h,{0,1.51f,.02f},{.152f,.147f,.157f}),-egg(h,{0,1.455f,-.15f},{.098f,.135f,.1f}),.02f);
      hair=smin(hair,horn(h,{0,1.48f,.07f},{0,1.1f,.15f},.145f,.15f),.03f);
      hair=smin(hair,horn(h,{0,1.1f,.15f},{0,.72f,.19f},.15f,.1f),.03f);
      hair=smin(hair,horn(n,{.115f,1.45f,-.02f},{.152f,1.24f,-.06f},.056f,.054f),.02f);
      hair=smin(hair,horn(n,{.152f,1.24f,-.06f},{.128f,1.03f,-.125f},.054f,.028f),.02f);
      if(hair<.04f) hair+=.007f*std::sin(h.x*48+3*std::sin(h.y*9)+h.z*14);
      f.add(horn(h,{0,1.27f,0},{0,1.39f,-.012f},.06f,.052f)*grown,skin,.02f);
      f.add(egg(h,{0,1.485f,-.02f},{.122f,.142f,.128f})*grown,skin,.015f);
      f.add(ball(h,{0,1.47f,-.15f},.02f)*grown,skin,.02f);
      if(f.paint) f.tint(ball(n,{.062f,1.445f,-.118f},.032f),blush,.025f,.7f);
      f.add(hair*grown,tress,.008f);
      const P q=wreath.local(h);
      float garland=hoop(q,.14f,.03f);
      if(garland<.04f) garland+=.008f*std::sin(std::atan2(q.z,q.x)*13);
      f.add(garland*grown,leaf,.01f);
    }
  };
  statue.details=[=](const Sculptor &clay,Carving &out) {
    auto grow=[&](P at) { return neck+(at-neck)*grown; };
    for(float side:{-1.f,1.f}) out.stroke(clay,grow({side*.047f,1.512f,-.14f}),{0,0,1},.03f,205,335,.008f,lash);
    out.stroke(clay,grow({0,1.438f,-.14f}),{0,0,1},.022f,220,320,.0065f,lash);
    const float turns[]={-90,-42,-138,8,172,56,124,90};
    for(int i=0;i<8;++i) {
      const float a=turns[i]*pi/180;
      const P out3=wreath.u*std::cos(a)+wreath.w*std::sin(a);
      out.blossom(grow(wreath.world({.14f*std::cos(a),.012f,.14f*std::sin(a)})+out3*.022f+wreath.v*.018f),out3*.75f+wreath.v*.66f,i==0 ? .07f : .058f,i*.7f);
    }
    const P spots[]={{-.075f,.6f,-.6f},{.09f,.43f,-.6f},{-.02f,.29f,-.6f}};
    const float sizes[]={.056f,.064f,.05f};
    for(int i=0;i<3;++i) {
      const P hit=land(clay,spots[i],{0,0,1});
      out.blossom(hit,gradient(clay,hit,.01f),sizes[i],i*1.1f);
    }
  };
  return statue;
}

// The forest king: a stout robe and leaf cloak, a long beard over his staff, and antlers through a floppy hat.
Statue king() {
  const Lathe robe({{0,.12f},{.335f,.13f},{.355f,.19f},{.34f,.32f},{.305f,.55f},{.27f,.8f},{.25f,.98f},{.225f,1.08f},{.15f,1.16f},{0,1.19f}});
  const Frame hat({0,1.415f,-.005f},{0,.99f,.139f},{0,0,1});
  auto leaves=std::make_shared<std::vector<Leaf>>();
  for(int i=-3;i<=3;++i) {
    leaves->push_back(drape(90+i*40.f,.2f+((i&1) ? .018f : 0),1.12f,.365f+((i&1) ? .018f : 0),.25f,.16f,.03f,.02f,.05f));
    leaves->push_back(drape(90+i*51.43f,.12f,1.22f,.36f+((i&1) ? .015f : 0),.84f,.125f,.028f,.03f,.045f));
  }
  Statue statue;
  statue.low={-.5f,-.03f,-.45f}; statue.high={.5f,2.15f,.47f}; statue.cell=.019f;
  statue.clay=[=](P p,Field &f) {
    stand(f,p);
    const P m{std::abs(p.x),p.y,p.z};
    f.add(robe.distance(hypot2(p.x,p.z/.93f),p.y)*.93f,wood,.02f);
    if(p.y>.55f && p.y<1.3f) {
      f.add(horn(m,{.2f,1.0f,-.03f},{.19f,.86f,-.17f},.075f,.062f),wood,.03f);
      f.add(horn(m,{.19f,.86f,-.17f},{.06f,.88f,-.27f},.062f,.046f),wood,.02f);
      f.add(ball(m,{.05f,.885f,-.275f},.048f),skin,.012f);
    }
    for(const Leaf &blade:*leaves) foliage(f,blade,p,leaf,leafEdge);
    if(p.y<1.35f) {
      f.add(horn(p,{0,.16f,-.345f},{0,1.08f,-.3f},.03f,.027f),staff,.008f);
      f.add(ball(p,{0,1.1f,-.3f},.046f),staff,.02f);
    }
    if(p.y>.5f && p.y<1.75f) {
      float beard=horn(p,{0,1.16f,-.115f},{0,.98f,-.165f},.115f,.105f);
      beard=smin(beard,horn(p,{0,.98f,-.165f},{0,.75f,-.19f},.105f,.03f),.02f);
      beard=smin(beard,horn(m,{.125f,1.26f,-.06f},{.1f,1.03f,-.14f},.075f,.07f),.03f);
      if(beard<.04f) beard+=.008f*std::sin(p.x*52+3.5f*std::sin(p.y*11));
      f.add(egg(p,{0,1.3f,-.02f},{.165f,.165f,.165f}),skin,.03f);
      f.add(ball(p,{0,1.292f,-.192f},.045f),skin,.02f);
      f.add(ball(m,{.088f,1.272f,-.138f},.046f),skin,.03f);
      if(f.paint) {
        f.tint(ball(m,{.095f,1.268f,-.17f},.04f),blush,.03f,.5f);
        f.tint(ball(p,{0,1.29f,-.225f},.03f),blush,.03f,.4f);
      }
      f.add(beard,whisker,.012f);
      f.add(horn(m,{.02f,1.238f,-.195f},{.15f,1.165f,-.155f},.042f,.018f),whisker,.01f);
      f.add(horn(m,{.03f,1.378f,-.168f},{.125f,1.368f,-.128f},.03f,.02f),whisker,.01f);
    }
    if(p.y>1.15f) {
      const P q=hat.local(p);
      const float around=hypot2(q.x,q.z), theta=std::atan2(q.z,q.x), sweep=saturate((around-.13f)/.16f);
      // The brim turns up at the front so the face shows from above, and droops behind.
      const float lift=.012f+(.032f-.05f*std::sin(theta))*sweep*sweep+.01f*std::sin(3*theta+1)*sweep;
      const float a=std::abs(q.y-lift)-.012f, b=around-.282f;
      const float brim=std::min(std::max(a,b),0.f)+hypot2(std::max(a,0.f),std::max(b,0.f))-.01f;
      float cone=smin(horn(q,{0,.03f,0},{0,.19f,0},.168f,.105f),horn(q,{0,.19f,0},{-.03f,.31f,-.01f},.105f,.058f),.02f);
      cone=smin(cone,horn(q,{-.03f,.31f,-.01f},{-.1f,.385f,-.03f},.058f,.024f),.02f);
      f.add(smin(brim,cone,.04f),felt);
      f.add(hoop({q.x,q.y-.082f,q.z},.158f,.02f),acorn,.008f);
      float rack=smin(horn(m,{.12f,1.555f,.02f},{.25f,1.7f,.035f},.042f,.036f),horn(m,{.25f,1.7f,.035f},{.325f,1.9f,.03f},.036f,.029f),.02f);
      rack=smin(rack,horn(m,{.325f,1.9f,.03f},{.305f,2.08f,.01f},.029f,.021f),.02f);
      rack=smin(rack,horn(m,{.22f,1.67f,.035f},{.37f,1.745f,.05f},.03f,.026f),.02f);
      rack=smin(rack,horn(m,{.37f,1.745f,.05f},{.44f,1.87f,.05f},.026f,.021f),.02f);
      rack=smin(rack,horn(m,{.31f,1.86f,.03f},{.22f,1.975f,.02f},.027f,.021f),.02f);
      rack=smin(rack,horn(m,{.33f,1.93f,.03f},{.42f,2.03f,.03f},.025f,.021f),.02f);
      f.add(rack,antler,.02f);
    }
  };
  statue.details=[=](const Sculptor &clay,Carving &out) {
    for(float side:{-1.f,1.f}) out.stroke(clay,{side*.07f,1.352f,-.17f},{0,0,1},.024f,205,335,.008f,lash);
    const float turns[]={-128,-90,-54};
    for(int i=0;i<3;++i) {
      const float a=turns[i]*pi/180;
      const P out3=hat.u*std::cos(a)+hat.w*std::sin(a);
      out.blossom(hat.world({.176f*std::cos(a),.088f,.176f*std::sin(a)}),out3+hat.v*.45f,i==1 ? .058f : .048f,i*.9f);
    }
  };
  return statue;
}

Carving sculpture(int kind) {
  const Statue statue=kind==1 ? pawn() : kind==2 ? fox() : kind==3 ? owl() : kind==4 ? rook() : kind==5 ? queen() : king();
  Carving out;
  carve(statue.clay,statue.low,statue.high,statue.cell,out);
  if(statue.details) statue.details(statue.clay,out);
  return out;
}
}

const Woodland::Figure &Woodland::figure(int kind,int tone) {
  static std::map<int,Figure> figures;
  kind=std::clamp(kind,1,6);
  // The first figure asked for has all six carved, each on a thread of its own, and painted for both sides: a set is
  // never wanted one figure at a time. The carvings are let go once the figures painted from them are made.
  if(figures.empty()) {
    Carving carved[6];
    std::vector<std::thread> carvers;
    for(int each=0;each<6;++each) carvers.emplace_back([&carved,each] { carved[each]=sculpture(each+1); });
    for(auto &carver:carvers) carver.join();
    for(int each=0;each<6;++each) for(int side=0;side<2;++side) {
      const Carving &carving=carved[each];
      Figure figure;
      figure.indices=carving.indices;
      figure.vertices.reserve(carving.points.size());
      for(size_t i=0;i<carving.points.size();++i) {
        const P p=carving.points[i], n=carving.normals[i], c=side ? carving.dark[i] : carving.light[i];
        SculptVertex vertex;
        vertex.position=QVector3D(p.x,p.y,p.z);
        vertex.normal=QVector3D(n.x,n.y,n.z);
        vertex.uv=QVector2D(std::atan2(p.z,p.x)/(2*pi)+.5f,p.y);
        vertex.color=QVector4D(saturate(c.x),saturate(c.y),saturate(c.z),1);
        figure.vertices.push_back(vertex);
      }
      figures.emplace((each+1)*2+side,std::move(figure));
    }
  }
  return figures.at(kind*2+(tone ? 1 : 0));
}
