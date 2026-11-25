#pragma once
#include "clay.h"
#include "woodland.h"
#include <functional>
#include <vector>

// Cast each material region separately so a figure can combine wood, metal and inlay.
// Recess shading stays with the sculpted surface.
namespace Figures {
using Field=std::function<float(Clay::P)>;
// `cell` is how finely the solid is cut; `shade` is how far its recesses darken.
// A `turned` solid is the same all round its axis; `company` stands against it and shades it.
struct Mould { Field field; float cell=.017f, shade=.4f; bool turned=false; Field company=nullptr; };
// Part 0 is a piece's body, 1 its metalwork, 2 its dark inlay and 3 the set's second colour.
SculptFigure part(int design,int kind,int part);

// Walk in from outside until a field's surface is met, so details can be set onto it.
inline Clay::P land(const Field &field,Clay::P from,Clay::P toward) {
  toward=Clay::normalize(toward);
  float travelled=0;
  for(int i=0;i<240 && travelled<2;++i) {
    const float d=field(from+toward*travelled);
    if(d<.0015f) break;
    travelled+=std::max(.002f,d*.6f);
  }
  return from+toward*travelled;
}
}

// The moulds for one part of a piece kind (1 pawn to 6 king); none when the piece has no such part.
namespace Orbital { std::vector<Figures::Mould> moulds(int kind,int part); }
namespace Atelier { std::vector<Figures::Mould> moulds(int kind,int part); }
namespace Candy { std::vector<Figures::Mould> moulds(int kind,int part); }
