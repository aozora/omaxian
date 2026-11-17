#include "figures.h"

// Candy Kingdom is moulded confectionery: pillowy gummy rings stacked into a tower, a bonbon
// on a stand, a fat kiss, a carousel pony with a rolled liquorice mane, and plump royalty in gold leaf.
namespace {
using namespace Clay;
using Figures::Field;
using Figures::Mould;

// A gummy ring, rounded almost through.
float gum(P p,float height,float radius,float half) { return disc(p,height,radius,half,half*.9f); }
// Every sweet sits on two rings, scaled to its rank, pressed softly together.
float stand(P p,float scale) { return smin(gum(p,.07f*scale,.34f*scale,.09f*scale),gum(p,.215f*scale,.27f*scale,.07f*scale),.03f*scale); }

float bonbon(P p) {
  const float d=smin(stand(p,.82f),horn(p,{0,.2f,0},{0,.3f,0},.11f,.1f),.03f);
  return smin(d,ball(p,{0,.47f,0},.19f),.035f);
}

// The pony: a big round head tucked over a curved neck and a plump chest, a short soft muzzle, two small ears.
float pony(P p) {
  const P m{std::abs(p.x),p.y,p.z};
  float body=horn(narrow(p,.9f),{0,.27f,.05f},{0,.48f,.085f},.19f,.162f)*.9f;
  body=smin(body,horn(narrow(p,.9f),{0,.48f,.085f},{0,.68f,.04f},.162f,.155f)*.9f,.04f);
  body=smin(body,egg(p,{0,.34f,-.05f},{.165f,.16f,.17f}),.05f);
  body=smin(body,egg(p,{0,.82f,-.03f},{.172f,.165f,.19f}),.05f);
  body=smin(body,horn(narrow(p,.92f),{0,.79f,-.13f},{0,.715f,-.245f},.125f,.098f)*.92f,.04f);
  body=smin(body,horn(m,{.08f,.95f,.02f},{.1f,1.07f,.04f},.048f,.02f),.025f);
  return smin(stand(p,.95f),body,.03f);
}

// The mane is one thick roll: a forelock, over the poll and down the neck, wound up at the end like a liquorice wheel.
Field mane() {
  const std::vector<P> crown{{0,.93f,-.165f},{0,.985f,-.08f},{0,1.0f,0},{0,.97f,.09f},{0,.9f,.16f}};
  const std::vector<P> fall{{0,.9f,.16f},{0,.8f,.2f},{0,.69f,.22f},{0,.58f,.24f},{0,.5f,.255f}};
  std::vector<P> curl;
  for(int i=0;i<=14;++i) {
    const float turn=30*i*pi/180, reach=.12f-.085f*i/14;
    curl.push_back({0,.38f+reach*std::cos(turn),.255f+reach*std::sin(turn)});
  }
  return [=](P p) { return smin(smin(strand(p,crown,.05f,.075f),strand(p,fall,.075f,.062f),.01f),strand(p,curl,.06f,.04f),.012f); };
}

// Eyes closed in a smile: an arch drawn onto each side of the head.
Field lashes() {
  std::vector<P> lid;
  for(int i=0;i<=8;++i) {
    const float a=(25+130*i/8.f)*pi/180;
    lid.push_back(Figures::land(pony,{.5f,.84f+.038f*std::sin(a),-.1f+.045f*std::cos(a)},{-1,0,0})+P{.003f,0,0});
  }
  return [=](P p) { return strand({std::abs(p.x),p.y,p.z},lid,.0115f,.0115f); };
}

// A fat kiss on a soft collar, drawn up to a rounded point.
float kiss(P p) {
  const float d=smin(stand(p,.9f),gum(p,.33f,.2f,.075f),.03f);
  return smin(d,horn(p,{0,.6f,0},{0,.98f,0},.215f,.038f),.03f);
}

// Three pillows and a short round keep, its wall parted into four fat merlons.
float tower(P p) {
  float d=smin(gum(p,.085f,.335f,.105f),gum(p,.275f,.312f,.105f),.03f);
  d=smin(d,gum(p,.465f,.292f,.105f),.03f);
  float keep=smax(disc(p,.69f,.285f,.125f,.08f),-disc(p,.84f,.17f,.1f,.045f),.03f);
  const float gaps=std::min(brick({p.x,p.y-.83f,p.z},{.055f,.1f,.5f},.03f),brick({p.x,p.y-.83f,p.z},{.5f,.1f,.055f},.03f));
  keep=smax(keep,-gaps,.025f);
  return smin(d,keep,.03f);
}

Field queen() {
  const Lathe gown({{0,.24f},{.235f,.26f},{.228f,.34f},{.2f,.45f},{.17f,.56f},{.15f,.66f},{.143f,.73f},{0,.74f}});
  const Lathe bust({{0,.78f},{.14f,.79f},{.152f,.83f},{.185f,.9f},{.218f,.96f},{.232f,1.0f},{.225f,1.04f},{.185f,1.07f},{.09f,1.085f},{0,1.088f}});
  return [=](P p) {
    const float rho=hypot2(p.x,p.z);
    float d=smin(stand(p,1),gown.distance(rho,p.y),.03f);
    d=smin(d,gum(p,.765f,.2f,.05f),.025f);
    return smin(d,bust.distance(rho,p.y),.025f);
  };
}

Field king() {
  const Lathe gown({{0,.24f},{.24f,.26f},{.234f,.35f},{.208f,.48f},{.18f,.61f},{.16f,.73f},{.152f,.82f},{0,.83f}});
  const Lathe bust({{0,.87f},{.148f,.88f},{.16f,.92f},{.192f,.99f},{.225f,1.05f},{.24f,1.09f},{.233f,1.13f},{.19f,1.16f},{.09f,1.175f},{0,1.178f}});
  return [=](P p) {
    const float rho=hypot2(p.x,p.z);
    float d=smin(stand(p,1),gown.distance(rho,p.y),.03f);
    d=smin(d,gum(p,.855f,.208f,.052f),.025f);
    return smin(d,bust.distance(rho,p.y),.025f);
  };
}

// A gold crown: a thick flaring band whose rim rises into points, one of them to the front.
float coronet(P p,float base,float radius,float flare,float band,float peak,int points) {
  const float rho=hypot2(p.x,p.z), h=p.y-base;
  const float turn=(std::atan2(p.z,p.x)+pi/2)*points/(2*pi), valley=2*std::abs(turn-std::round(turn));
  const float wall=std::abs(rho-radius-flare*h)-.022f;
  // The rim climbs steeply, so the distance is eased to stay an honest underestimate.
  return smax(wall,std::max(-h,h-band-peak*(1-valley)),.012f)*.55f;
}

// Five tall points, each tipped with a fat gold bead.
float tiara(P p) {
  return smin(coronet(p,1.03f,.2f,.2f,.06f,.15f,5),ball(wedge(p,5,-pi/2),{0,1.25f,-.244f},.045f),.006f);
}

// A band under four stout arches that sink into the cushion and meet in an orb and a cross.
float regalia(P p) {
  static const std::vector<P> rib{{0,1.19f,-.215f},{0,1.27f,-.236f},{0,1.335f,-.185f},{0,1.37f,-.095f},{0,1.38f,0}};
  float d=smin(coronet(p,1.12f,.208f,.1f,.08f,.03f,8),strand(wedge(p,4,-pi/2),rib,.032f,.032f),.008f);
  d=smin(d,ball(p,{0,1.405f,0},.05f),.008f);
  d=smin(d,horn(p,{0,1.44f,0},{0,1.475f,0},.03f,.027f),.006f);
  return smin(d,pattee(p,{0,1.525f,0},.072f,.024f,.046f,.024f),.008f);
}
}

std::vector<Mould> Candy::moulds(int kind,int part) {
  if(kind<1 || kind>6) return {};
  // Sugar lets light through, so its recesses are barely shaded.
  if(part==0) {
    const Field sweet=kind==1 ? Field(bonbon) : kind==2 ? Field(pony) : kind==3 ? Field(kiss) : kind==4 ? Field(tower) : kind==5 ? queen() : king();
    return {{sweet,kind==1 ? .016f : .018f,.12f}};
  }
  if(part==1 && kind==5) return {{tiara,.009f,.15f}};
  if(part==1 && kind==6) return {{regalia,.009f,.15f}};
  if(part==2 && kind==2) return {{lashes(),.005f,0}};
  if(part==3 && kind==2) return {{mane(),.012f,.12f}};
  // A cushion of the darker sweet swells between the arches of the king's crown.
  if(part==3 && kind==6) return {{+[](P p) { return egg(p,{0,1.235f,0},{.2f,.15f,.2f}); },.014f,.12f}};
  return {};
}
