#include "figures.h"

// Orbital Orders is a court among the stars in miniature: pale ceramic or gunmetal hulls on
// ringed decks, gold instruments and edging for the officers, and small lights behind dark glass.
namespace {
using namespace Clay;
using Figures::Field;
using Figures::Mould;

// Every piece stands on a deck, scaled to its rank: a plate under a low cone, a gold ring let into the step.
// Each hull rises from inside the deck, so no hem of it is cut where the two meet.
const Lathe deck({{0,.04f},{.31f,.05f},{.3f,.085f},{.25f,.118f},{.2f,.15f},{0,.15f}});
const float rank[]={0,.82f,.95f,.92f,.98f,1,1};

float base(P p,float scale) {
  const P q=p*(1/scale);
  return smin(disc(q,.025f,.35f,.045f,.014f),deck.distance(hypot2(q.x,q.z),q.y),.006f)*scale;
}
float ring(P p,float height,float radius,float tube) { return hoop({p.x,p.y-height,p.z},radius,tube); }

// A plate cut to an outline seen from the side, thickest along its middle and bevelled flat to a fine edge.
// The outline is traced as (depth+.6, height); a knot given twice is a sharp corner.
struct Plate {
  Lathe outline;
  float edge,bevel,thick;
  float rim(P p) const { return outline.distance(p.z+.6f,p.y); }
  float distance(P p) const {
    const float d=rim(p);
    return smax(d,std::abs(p.x)-std::min(thick,edge+bevel*std::max(-d,0.f)),.004f)*.75f;
  }
};

// The sentinel: a beacon dome on a flared collar, parted all the way round by a slot of dark glass.
Field sentinel() {
  const Lathe neck({{0,.1f},{.168f,.11f},{.15f,.17f},{.122f,.25f},{.106f,.33f},{.116f,.38f},{.15f,.408f},{0,.42f}});
  return [=](P p) {
    const float rho=hypot2(p.x,p.z);
    const float dome=smax(egg(p,{0,.6f,0},{.2f,.215f,.2f}),-std::max(std::abs(p.y-.6f)-.036f,.183f-rho),.006f);
    return smin(neck.distance(rho,p.y),dome,.008f);
  };
}

// The comet steed is all blades: a sail of a neck swelling to a breastplate, a long wedge of a head
// with a hard brow, and two fins swept back from the crown.
const Plate sail{Lathe({{.39f,.1f},{.39f,.1f},{.35f,.36f},{.4f,.56f},{.5f,.74f},{.55f,.86f},{.55f,.86f},{.67f,.97f},{.67f,.97f},
                        {.79f,.8f},{.87f,.5f},{.86f,.3f},{.83f,.1f},{.83f,.1f},{.39f,.1f},{.39f,.1f}}),.025f,.8f,.125f};
const Plate helm{Lathe({{.18f,.72f},{.18f,.72f},{.44f,.93f},{.44f,.93f},{.58f,1.06f},{.58f,1.06f},{.73f,.97f},{.73f,.97f},
                        {.65f,.8f},{.65f,.8f},{.4f,.71f},{.4f,.71f},{.18f,.72f},{.18f,.72f}}),.018f,.75f,.085f};
const Plate fin{Lathe({{.5f,.97f},{.5f,.97f},{.9f,1.26f},{.9f,1.26f},{.71f,.9f},{.71f,.9f},{.5f,.97f},{.5f,.97f}}),.014f,.6f,.032f};
float steed(P p) {
  // Each plate is only measured near where it stands.
  float d=p.y<1.1f ? sail.distance(p) : 1e9f;
  if(p.y>.58f) d=smin(d,helm.distance(p),.012f);
  // The fins lean apart as they rise.
  if(p.y>.78f && p.z>-.22f) d=std::min(d,fin.distance({std::abs(p.x)-.048f-.2f*(p.y-.95f),p.y,p.z}));
  return d;
}
// Gold edging follows the whole silhouette of sail and helm.
float edging(P p) {
  if(std::abs(p.x)>.12f) return std::abs(p.x)-.016f;
  const float rim=std::min(sail.rim(p),helm.rim(p))-.013f;
  return std::max(std::max(rim,std::abs(p.x)-.016f),std::max(.2f-p.y,-rim-.05f));
}
// A slit of light lies under each brow.
Field visor() {
  const float side=Figures::land(steed,{.5f,.925f,-.09f},{-1,0,0}).x;
  const Frame brow({0,.925f,-.09f},{0,.763f,-.646f},{0,-.646f,-.763f});
  return [=](P p) { const P q=brow.local(p); return egg({std::abs(q.x),q.y,q.z},{side,0,0},{.016f,.016f,.07f}); };
}

// The halo spire: a slender hull that carries a ring and its light.
Field spire() {
  const Lathe hull({{0,.11f},{.19f,.12f},{.172f,.19f},{.14f,.32f},{.108f,.48f},{.084f,.64f},{.068f,.78f},{.062f,.87f},{.074f,.91f},{0,.92f}});
  return [=](P p) { return smin(hull.distance(hypot2(p.x,p.z),p.y),disc(p,.82f,.088f,.014f,.008f),.004f); };
}
float halo(P p) {
  float d=std::min(hoop({p.x,p.z,p.y-1.1f},.15f,.021f),horn(p,{0,.94f,0},{0,1.27f,0},.011f,.011f));
  d=smin(d,horn(p,{0,.9f,0},{0,.955f,0},.05f,.036f),.008f);
  return smin(d,ball(p,{0,1.295f,0},.03f),.006f);
}
// A seam of light runs down the front of the hull.
Field seam() {
  const Field hull=spire();
  std::vector<P> line;
  for(int i=0;i<8;++i) line.push_back(Figures::land(hull,{0,.25f+.074f*i,-.6f},{0,0,1}));
  return [=](P p) { return strand(p,line,.011f,.011f); };
}

// The bastion: a waisted keep under a ring of eight merlons, a lit port below each.
// The keep is drawn taut so its crown throws no lip, and the merlons are rounded as broadly as a cell so they cut clean.
Field bastion() {
  const Lathe keep({{0,.06f},{.215f,.07f},{.215f,.13f},{.2f,.2f},{.186f,.32f},{.186f,.5f},{.2f,.6f},{.236f,.66f},{.262f,.7f},{.27f,.74f},{.27f,.93f},{.262f,.95f},{0,.95f}},true);
  return [=](P p) {
    float d=keep.distance(hypot2(p.x,p.z),p.y);
    d=smax(d,-disc(p,1.0f,.2f,.11f,.012f),.012f);
    const P gap=wedge(p,8,pi/8), port=wedge(p,8,0);
    d=smax(d,-brick({gap.x,gap.y-.955f,gap.z+.25f},{.04f,.05f,.1f},.01f),.01f);
    return smax(d,-brick({port.x,port.y-.81f,port.z+.27f},{.022f,.05f,.04f},.01f),.005f);
  };
}

// The crescent regent: four broad panels overlap as they wind up her gown, and her shoulders
// carry a moon as thick as the hull itself, lined with gold and cradling its light.
const Lathe gown({{0,.06f},{.24f,.07f},{.24f,.13f},{.235f,.22f},{.215f,.4f},{.185f,.6f},{.16f,.78f},{.152f,.86f},{.168f,.93f},{.195f,.97f},{.19f,1.0f},{.14f,1.02f},{0,1.03f}});
const float wind=.9f;
// How far the panels stand off one another, fading out at hem and shoulder.
float lift(float height) { return .07f*smooth(.16f,.3f,height)*smooth(.97f,.87f,height); }
float sickle(P p) { return std::max(hypot2(p.x-.02f,p.y-1.24f)-.24f,.2f-hypot2(p.x+.07f,p.y-1.29f)); }
float regent(P p) {
  const float rho=hypot2(p.x,p.z), turn=4*std::atan2(p.z,p.x)/(2*pi)+wind*p.y, lap=turn-std::floor(turn)-.5f, rise=lift(p.y);
  auto panel=[&](float along) { return gown.distance(rho+rise*along,p.y); };
  // Each panel steps down onto the next. This one is cut square where it begins, the one before runs on
  // beneath it, and the next one's step is measured from behind, so the field stays whole across every step.
  const float here=std::max(panel(lap),-rho*std::sin((lap+.5f)*pi/2)), next=std::max(panel(lap-1),rho*std::sin((.5f-lap)*pi/2));
  // The panels wind as they rise, so the field is eased to stay an honest underestimate.
  const float dress=std::min(std::min(here,panel(lap+1)),next)*.65f;
  const float s=sickle(p), moon=smax(s,std::abs(p.z)-.02f-.5f*std::min(std::max(-s,0.f),.09f),.01f)*.8f;
  return smin(dress,moon,.02f);
}
// Gold piping runs up the proud edge of every panel.
float piping(P p) {
  const P q=wedge(p,4,-wind*p.y*pi/2);
  const float d=hypot2(q.x,gown.distance(-q.z-lift(p.y)*.5f+.004f,p.y))-.011f;
  return std::max(d,std::max(p.y-.93f,.22f-p.y))*.7f;
}
// The moon's inner curve is lined with gold, and a gold ring closes her collar.
float lining(P p) {
  const float arc=std::max(std::abs(hypot2(p.x+.07f,p.y-1.29f)-.2f)-.013f,hypot2(p.x-.02f,p.y-1.24f)-.236f);
  return std::min(std::max(arc,std::abs(p.z)-.03f),ring(p,.985f,.196f,.013f));
}

// The armillary sovereign: a pleated robe under a mantle with broad shoulders and a standing collar,
// parted down the front, with the rings of an armillary nested in the collar.
const Lathe robe({{0,.06f},{.25f,.07f},{.25f,.13f},{.245f,.22f},{.228f,.4f},{.208f,.6f},{.195f,.8f},{.19f,.95f},{.17f,1.05f},{.12f,1.1f},{0,1.11f}});
const Lathe mantle({{0,.52f},{.2f,.5f},{.258f,.5f},{.264f,.53f},{.25f,.7f},{.236f,.86f},{.242f,.95f},{.264f,1.02f},{.27f,1.06f},{.245f,1.09f},
                    {.218f,1.13f},{.224f,1.17f},{.21f,1.185f},{.17f,1.17f},{.1f,1.13f},{0,1.12f}});
// Where the mantle parts: negative inside an opening that widens toward the hem, and inside the vee of the collar.
float parting(P p) {
  const float a=(8+37*saturate((1.05f-p.y)/.55f))*pi/180;
  return std::min(std::abs(p.x)*std::cos(a)+p.z*std::sin(a),std::max(std::abs(p.x)-(p.y-1.0f)*.5f,p.z+.05f));
}
float sovereign(P p) {
  const float rho=hypot2(p.x,p.z);
  const float pleat=.03f*(1-std::abs(std::cos(4*std::atan2(p.z,p.x))))*smooth(.18f,.3f,p.y)*smooth(1.0f,.9f,p.y);
  const float cloak=smax(mantle.distance(rho,p.y),-parting(p)*.9f,.008f);
  return smin(robe.distance(rho+pleat,p.y)*.8f,cloak,.006f);
}
// Gold braid edges the parting and the hem.
float braid(P p) {
  const float skin=mantle.distance(hypot2(p.x,p.z),p.y);
  const float lapel=std::max(std::max(std::abs(parting(p))-.014f,skin-.008f),std::max(-skin-.03f,.5f-p.y));
  return std::min(lapel,std::max(ring(p,.515f,.258f,.015f),-parting(p)));
}
Field armillary() {
  const P heart{0,1.35f,0};
  const Frame meridian(heart,{0,0,1},{0,1,0}), ecliptic(heart,{.34f,.94f,0},{0,0,1}), orbit(heart,{.68f,.33f,.65f},{0,1,0});
  return [=](P p) {
    float d=std::min(hoop(meridian.local(p),.19f,.015f),std::min(hoop(ecliptic.local(p),.174f,.015f),hoop(orbit.local(p),.158f,.015f)));
    d=std::min(d,horn(p,{0,1.1f,0},{0,1.575f,0},.012f,.012f));
    d=smin(d,horn(p,{0,1.11f,0},{0,1.19f,0},.05f,.02f),.01f);
    return std::min(d,ball(p,{0,1.585f,0},.028f));
  };
}
// A figure's hull above its deck.
Field figure(int kind) {
  return kind==1 ? sentinel() : kind==2 ? Field(steed) : kind==3 ? spire() : kind==4 ? bastion() : kind==5 ? Field(regent) : Field(sovereign);
}
}

std::vector<Mould> Orbital::moulds(int kind,int part) {
  if(kind<1 || kind>6) return {};
  if(part==0) {
    const float scale=rank[kind];
    const Field deck=[=](P p) { return base(p,scale); }, hull=figure(kind);
    // The deck's rounded rim is finer than any grid cell, so it is always turned. The sentinel and the
    // spire are round all the way up and are turned whole; the others are carved and stand on it.
    if(kind==1 || kind==3) return {{[=](P p) { return smin(deck(p),hull(p),.008f); },.01f,.5f,true}};
    return {{deck,.01f,.5f,true,hull},{hull,kind==2 ? .013f : kind==4 ? .011f : .017f,.5f,false,deck}};
  }
  if(part==1) {
    const float scale=rank[kind];
    // Plain rings and discs about the axis are turned, so their rims run true.
    std::vector<Mould> gold{{[=](P p) { return ring(p,.07f*scale,.322f*scale,.013f); },.007f,.3f,true}};
    if(kind==1) gold.push_back({+[](P p) { return ring(p,.405f,.148f,.016f); },.008f,.3f,true});
    if(kind==2) gold.push_back({edging,.007f,.3f});
    if(kind==3) gold.push_back({halo,.007f,.3f});
    if(kind==4) gold.push_back({+[](P p) { return std::min(ring(p,.7f,.264f,.014f),ring(p,.41f,.186f,.012f)); },.007f,.3f,true});
    if(kind==5) { gold.push_back({lining,.007f,.3f}); gold.push_back({piping,.006f,.3f}); }
    if(kind==6) { gold.push_back({braid,.007f,.3f}); gold.push_back({armillary(),.007f,.3f}); }
    return gold;
  }
  if(part==2) {
    // Dark glass: the band round the sentinel's dome, and the well of the bastion.
    if(kind==1) return {{+[](P p) { return disc(p,.6f,.19f,.033f,.006f); },.01f,.2f,true}};
    if(kind==4) return {{+[](P p) { return disc(p,.892f,.196f,.008f,.003f); },.006f,.2f,true}};
  }
  if(part==3) {
    // Lights: a lens, eye slits, the orbs the instruments hold, and what shows through ports and seams.
    if(kind==1) return {{+[](P p) { return egg(p,{0,.6f,-.186f},{.052f,.034f,.03f}); },.006f,0}};
    if(kind==2) return {{visor(),.005f,0}};
    if(kind==3) return {{+[](P p) { return ball(p,{0,1.1f,0},.066f); },.01f,0},{seam(),.005f,0}};
    if(kind==4) return {{+[](P p) { return disc(p,.81f,.247f,.046f,.004f); },.01f,0,true}};
    if(kind==5) return {{+[](P p) { return ball(p,{-.07f,1.165f,0},.078f); },.012f,0}};
    const P gem=Figures::land(sovereign,{0,.86f,-.6f},{0,0,1});
    return {{+[](P p) { return ball(p,{0,1.35f,0},.055f); },.01f,0},{[=](P p) { return egg(p,gem,{.036f,.048f,.02f}); },.006f,0}};
  }
  return {};
}
