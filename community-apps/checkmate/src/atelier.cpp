#include "figures.h"

// Midnight Atelier is a turned Staunton set: stout boxwood and walnut on brass shoes, a brass
// ring under each crowned head, and a horse carved the way a club knight is.
namespace {
using namespace Clay;
using Figures::Field;
using Figures::Mould;

// Every piece stands on the same foot, scaled to its rank: a wooden bead over a brass shoe.
// Both are drawn taut: their short chamfers lie beside the long flat of the sole.
const Lathe sole({{0,-.02f},{.34f,-.02f},{.35f,0},{.35f,.06f},{.336f,.078f},{.334f,.09f},{.346f,.115f},{.343f,.14f},{.318f,.168f},{.275f,.188f},{.235f,.2f},{0,.2f}},true);
const Lathe shoe({{0,-.022f},{.346f,-.022f},{.361f,-.012f},{.365f,.005f},{.365f,.05f},{.359f,.066f},{.34f,.075f},{0,.075f}},true);
const float rank[]={0,.8f,.95f,.92f,.95f,.98f,1};
// The horse's head is laid out along its own axis: across, above the nose line, and down it from the poll.
const Frame skull({0,.88f,-.02f},{0,.789f,-.614f},{0,-.614f,-.789f});

// A piece's wood: what the lathe turns, and the head then carved onto it, cut as finely as `cell`.
struct Wood { Field turned, carved; float cell=.013f; };

float foot(P p,float scale) { return sole.distance(hypot2(p.x,p.z)/scale,p.y/scale)*scale; }
Field band(float height,float radius,float tube) { return [=](P p) { return hoop({p.x,p.y-height,p.z},radius,tube); }; }
// The nearer of two solids; either may be absent.
Field either(Field a,Field b) {
  if(!a) return b;
  if(!b) return a;
  return [=](P p) { return std::min(a(p),b(p)); };
}

Wood pawn() {
  const Lathe stem({{0,.12f},{.19f,.135f},{.174f,.166f},{.144f,.208f},{.118f,.27f},{.1f,.34f},{.092f,.4f},{0,.41f}});
  Wood wood;
  wood.turned=[=](P p) {
    float d=smin(foot(p,.8f),stem.distance(hypot2(p.x,p.z),p.y),.012f);
    d=smin(d,disc(p,.425f,.172f,.021f,.019f),.006f);
    d=smin(d,horn(p,{0,.44f,0},{0,.5f,0},.092f,.082f),.01f);
    return smin(d,ball(p,{0,.6f,0},.16f),.012f);
  };
  return wood;
}

// How deep the middle of the neck lies at a height: back from the chest, then forward again to the poll.
float spine(float height) {
  return height<.6f ? .085f*saturate((height-.33f)/.27f) : height<.84f ? .085f-.05f*(height-.6f)/.24f : .035f-.055f*saturate((height-.84f)/.04f);
}

// The horse: a neck arched back over a deep chest, the head tucked in with a carved mouth, nostrils
// and brow, and a mane laid over the crest in combed strands that end in points down each side.
Field knight() {
  const Frame forelock({0,.972f,-.068f},{0,-.614f,-.789f},{1,0,0});
  return [=](P p) {
    const float d=smin(foot(p,.95f),disc(p,.215f,.258f,.032f,.022f),.01f);
    if(p.y<.12f) return d;
    const P m{std::abs(p.x),p.y,p.z};
    const float neck=smin(horn(narrow(p,.8f),{0,.33f,0},{0,.6f,.085f},.205f,.16f)*.8f,horn(narrow(p,.72f),{0,.6f,.085f},{0,.84f,.035f},.16f,.132f)*.72f,.04f);
    float horse=smin(neck,egg(p,{0,.4f,-.105f},{.16f,.16f,.15f}),.05f);
    if(p.y>.5f && p.z<.25f) {
      float head=horn(narrow(p,.74f),{0,.88f,-.02f},{0,.705f,-.245f},.122f,.07f)*.74f;
      // Cheek, the swell of the nose, and a lower lip under the cut of the mouth.
      head=smin(head,egg(p,{0,.79f,-.06f},{.098f,.1f,.1f}),.03f);
      head=smin(head,egg(p,{0,.69f,-.255f},{.058f,.058f,.065f}),.02f);
      head=smin(head,egg(p,{0,.652f,-.212f},{.046f,.034f,.052f}),.015f);
      head=smin(head,egg(forelock.local(p),{0,0,0},{.03f,.065f,.042f}),.012f);
      const P q=skull.local(p), s{std::abs(q.x),q.y,q.z};
      head=smin(head,horn(s,{.06f,.078f,.02f},{.068f,.07f,.095f},.016f,.013f),.012f);
      // Pricked ears, hollowed toward the front.
      const float ear=smax(horn(m,{.056f,.95f,.02f},{.07f,1.1f,0},.04f,.012f),-egg(m,{.066f,1.03f,-.022f},{.02f,.05f,.02f}),.006f);
      head=smin(head,ear,.015f);
      head=smax(head,-egg(s,{0,-.042f,.35f},{.2f,.013f,.075f}),.004f);
      head=smax(head,-ball(s,{.04f,.008f,.345f},.019f),.004f);
      horse=smin(horse,head,.035f);
    }
    if(p.y>.2f && p.z>-.08f) {
      // The mane lies over the back of the neck like a cape: its edge falls in points, its strands wander as they run down.
      const float behind=p.z-spine(p.y);
      float mane=smax(smax(neck-.024f,.035f+.02f*std::sin(24*p.y)-behind,.008f),p.y-.99f,.01f);
      mane+=.008f*std::sin(8*std::atan2(m.x,behind)+2*std::sin(9*p.y));
      horse=smin(horse,mane*.8f,.008f);
    }
    return smin(d,horse,.03f);
  };
}

// Foot, stem and collar come off the lathe; the mitre is carved and set on the collar.
Wood bishop() {
  const Lathe stem({{0,.14f},{.23f,.155f},{.21f,.195f},{.176f,.25f},{.146f,.33f},{.125f,.44f},{.112f,.56f},{.106f,.66f},{.106f,.71f},{0,.72f}});
  const Lathe mitre({{0,.75f},{.105f,.76f},{.135f,.805f},{.162f,.875f},{.172f,.945f},{.163f,1.02f},{.132f,1.1f},{.083f,1.17f},{.036f,1.208f},{0,1.218f}});
  Wood wood;
  wood.turned=[=](P p) {
    const float d=smin(foot(p,.92f),stem.distance(hypot2(p.x,p.z),p.y),.012f);
    return smin(d,disc(p,.73f,.195f,.022f,.02f),.006f);
  };
  wood.carved=[=](P p) {
    const float head=smin(mitre.distance(hypot2(p.x,p.z),p.y),ball(p,{0,1.246f,0},.044f),.008f);
    // The mitre's cut climbs from its middle to one shoulder, open to the front and the back.
    const float across=-.819f*(p.x-.01f)+.574f*(p.y-.975f), along=.574f*(p.x-.01f)+.819f*(p.y-.975f);
    return smax(head,-std::max(std::abs(across)-.017f,-.03f-along),.004f);
  };
  wood.cell=.009f;
  return wood;
}

Wood rook() {
  const Lathe tower({{0,.15f},{.25f,.165f},{.235f,.205f},{.215f,.26f},{.2f,.34f},{.194f,.45f},{.198f,.54f},{.212f,.6f},{.224f,.63f},{0,.635f}});
  const Lathe turret({{0,.665f},{.21f,.67f},{.246f,.695f},{.268f,.725f},{.274f,.765f},{.274f,.865f},{.266f,.88f},{.256f,.885f},{0,.885f}},true);
  Wood wood;
  wood.turned=[=](P p) {
    const float d=smin(foot(p,.95f),tower.distance(hypot2(p.x,p.z),p.y),.012f);
    return smin(d,disc(p,.652f,.255f,.022f,.02f),.006f);
  };
  // The turret is hollowed, and six crenels are sawn through its wall.
  wood.carved=[=](P p) {
    const float d=smax(turret.distance(hypot2(p.x,p.z),p.y),-disc(p,.91f,.195f,.1f,.012f),.008f);
    const P q=wedge(p,6,pi/6);
    return smax(d,-brick({q.x,q.y-.88f,q.z+.255f},{.048f,.058f,.12f},.008f),.006f);
  };
  wood.cell=.011f;
  return wood;
}

Wood queen() {
  const Lathe stem({{0,.15f},{.25f,.168f},{.228f,.21f},{.192f,.268f},{.16f,.355f},{.138f,.47f},{.124f,.6f},{.116f,.72f},{.114f,.79f},{0,.8f}});
  const Lathe cup({{0,.83f},{.118f,.84f},{.126f,.89f},{.142f,.97f},{.172f,1.06f},{.208f,1.14f},{.232f,1.19f},{.24f,1.225f},{.228f,1.243f},{.205f,1.215f},{.17f,1.188f},{.11f,1.215f},{.05f,1.24f},{0,1.245f}});
  Wood wood;
  wood.turned=[=](P p) {
    const float d=smin(foot(p,.98f),stem.distance(hypot2(p.x,p.z),p.y),.012f);
    return smin(d,disc(p,.812f,.208f,.023f,.021f),.006f);
  };
  // An open coronet: the standing rim scooped between eight points with a pearl on each, around a domed cap and its ball.
  wood.carved=[=](P p) {
    float head=smax(cup.distance(hypot2(p.x,p.z),p.y),-ball(wedge(p,8,pi/8),{0,1.275f,-.25f},.068f),.008f);
    head=smin(head,ball(wedge(p,8,0),{0,1.262f,-.222f},.038f),.006f);
    head=smin(head,horn(p,{0,1.235f,0},{0,1.28f,0},.045f,.032f),.008f);
    return smin(head,ball(p,{0,1.318f,0},.052f),.006f);
  };
  wood.cell=.01f;
  return wood;
}

Wood king() {
  const Lathe stem({{0,.15f},{.255f,.17f},{.235f,.212f},{.2f,.27f},{.168f,.36f},{.145f,.48f},{.13f,.62f},{.122f,.76f},{.12f,.85f},{0,.86f}});
  const Lathe cup({{0,.89f},{.125f,.9f},{.132f,.95f},{.148f,1.03f},{.178f,1.12f},{.21f,1.19f},{.228f,1.235f},{.232f,1.262f},{.222f,1.282f},{.19f,1.294f},{.12f,1.318f},{.05f,1.332f},{0,1.335f}});
  Wood wood;
  wood.turned=[=](P p) {
    const float rho=hypot2(p.x,p.z);
    float d=smin(foot(p,1),stem.distance(rho,p.y),.012f);
    d=smin(d,disc(p,.872f,.215f,.024f,.022f),.006f);
    return smin(d,cup.distance(rho,p.y),.006f);
  };
  return wood;
}

Wood timber(int kind) {
  if(kind==2) {
    Wood wood;
    wood.carved=knight();
    return wood;
  }
  return kind==1 ? pawn() : kind==3 ? bishop() : kind==4 ? rook() : kind==5 ? queen() : king();
}

// Shoe and rings are turned like the wood they clasp; the king's cross is cut fine enough to keep its arrises.
std::vector<Mould> metal(int kind) {
  const float scale=rank[kind];
  std::vector<Mould> brass{{[=](P p) { return shoe.distance(hypot2(p.x,p.z)/scale,p.y/scale)*scale; },.011f,.3f,true}};
  // A ring rests on the collar beneath each crowned head, and the king carries his cross.
  if(kind==3) brass.push_back({band(.768f,.136f,.027f),.009f,.3f,true});
  if(kind==5) brass.push_back({band(.851f,.148f,.028f),.009f,.3f,true});
  if(kind==6) {
    brass.push_back({band(.912f,.152f,.029f),.009f,.3f,true});
    brass.push_back({+[](P p) { return smin(pattee(p,{0,1.44f,0},.085f,.024f,.048f,.024f),horn(p,{0,1.325f,0},{0,1.375f,0},.042f,.03f),.008f); },.004f,.3f});
  }
  return brass;
}
}

std::vector<Mould> Atelier::moulds(int kind,int part) {
  if(kind<1 || kind>6) return {};
  // The knight's eyes are beads of ebony set under the brow either side of the skull.
  if(part==2 && kind==2) return {{+[](P p) { const P q=skull.local(p); return egg({std::abs(q.x),q.y,q.z},{.07f,.048f,.055f},{.018f,.019f,.028f}); },.006f,.15f}};
  if(part!=0 && part!=1) return {};
  // Wood and brass each shade the other where they meet, so the metal sits on the piece rather than over it.
  const Wood wood=timber(kind);
  std::vector<Mould> brass=metal(kind);
  if(part==1) {
    const Field against=either(wood.turned,wood.carved);
    for(Mould &mould:brass) mould.company=against;
    return brass;
  }
  Field metalwork;
  for(const Mould &mould:brass) metalwork=either(metalwork,mould.field);
  std::vector<Mould> body;
  if(wood.turned) body.push_back({wood.turned,.012f,.45f,true,either(metalwork,wood.carved)});
  if(wood.carved) body.push_back({wood.carved,wood.cell,.45f,false,either(metalwork,wood.turned)});
  return body;
}
