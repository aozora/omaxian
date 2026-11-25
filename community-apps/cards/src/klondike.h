#pragma once

#include <cstdint>
#include <optional>
#include <vector>

// The rules of Klondike, with no Qt in them: thirteen piles of cards, the
// moves between them, and enough history to take every one back.
namespace Klondike {

// Ids run 0 to 51: thirteen spades, hearts, diamonds, then clubs, ace first.
struct Card {
  int id = 0;
  bool up = false;
  int suit() const { return id / 13; }
  int rank() const { return id % 13; }
  bool red() const { return suit() == 1 || suit() == 2; }
};

// Pile numbers: the stock, the waste, a foundation per suit, seven columns.
enum { Stock = 0, Waste = 1, Foundation = 2, Tableau = 6, Piles = 13 };

// The stock turns three cards at a time, of which only the last can be played.
enum { Draw = 3 };

// `count` cards off the top of `from` onto `to`. A draw is Stock to Waste and
// a recycle is Waste to Stock. `flip` records that the move turned the card
// it uncovered, so undo can turn it back.
struct Move {
  int from = -1, to = -1, count = 0;
  bool flip = false;
  bool operator==(const Move &other) const { return from == other.from && to == other.to && count == other.count; }
};

class Game {
public:
  explicit Game(std::uint32_t seed = 1);

  std::uint32_t seed() const { return m_seed; }
  const std::vector<Card> &pile(int index) const { return m_piles[index]; }
  const std::vector<Move> &moves() const { return m_moves; }

  // Whether the cards from `index` to the top of `from` may go onto `to`.
  bool canMove(int from, int index, int to) const;
  std::vector<int> targets(int from, int index) const;
  // Where a double click sends those cards: home if it can, else a column.
  int bestTarget(int from, int index) const;

  bool play(int from, int to, int count);
  // Turns cards from the stock, or brings the waste back round when it is empty.
  bool drawStock();
  bool undo();

  int home() const;
  bool won() const { return home() == 52; }
  // Nothing is hidden any more, so the rest can only go one way.
  bool finishable() const;
  bool finishStep();
  // The next move worth making, or nothing when there is none to be found.
  std::optional<Move> hint() const;

private:
  // Whether a lone card has anywhere to go: its foundation or a column.
  bool placeable(const Card &card) const;
  // Whether turning the stock, all the way round, ever shows a card that can be played.
  bool stockHelps() const;
  std::uint32_t m_seed;
  std::vector<Card> m_piles[Piles];
  std::vector<Move> m_moves;
};

}
