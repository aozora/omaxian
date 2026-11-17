#include "klondike.h"

#include <algorithm>

namespace Klondike {

Game::Game(std::uint32_t seed) : m_seed(seed) {
  // The shuffle is spelled out rather than left to the standard library, so
  // a saved seed deals the same game on every machine and compiler.
  std::uint64_t state = seed;
  auto next = [&state] {
    std::uint64_t z = (state += 0x9E3779B97F4A7C15ull);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
    return z ^ (z >> 31);
  };
  int deck[52];
  for (int i = 0; i < 52; ++i) deck[i] = i;
  for (int i = 51; i > 0; --i) std::swap(deck[i], deck[next() % (i + 1)]);
  int dealt = 0;
  for (int column = 0; column < 7; ++column)
    for (int row = 0; row <= column; ++row) m_piles[Tableau + column].push_back({deck[dealt++], row == column});
  while (dealt < 52) m_piles[Stock].push_back({deck[dealt++], false});
}

bool Game::canMove(int from, int index, int to) const {
  if (from < Waste || from >= Piles || to < Foundation || to >= Piles || from == to) return false;
  const auto &source = m_piles[from];
  if (index < 0 || index >= int(source.size()) || !source[index].up) return false;
  const int count = int(source.size()) - index;
  if (from < Tableau && count != 1) return false;
  const Card card = source[index];
  const auto &target = m_piles[to];
  if (to < Tableau) return count == 1 && card.suit() == to - Foundation && card.rank() == int(target.size());
  if (target.empty()) return card.rank() == 12;
  return target.back().up && target.back().red() != card.red() && target.back().rank() == card.rank() + 1;
}

std::vector<int> Game::targets(int from, int index) const {
  std::vector<int> result;
  for (int to = Foundation; to < Piles; ++to)
    if (canMove(from, index, to)) result.push_back(to);
  return result;
}

int Game::bestTarget(int from, int index) const {
  if (from < Waste || from >= Piles || index < 0 || index >= int(m_piles[from].size())) return -1;
  const int home = Foundation + m_piles[from][index].suit();
  if (from >= Tableau || from == Waste) {
    if (canMove(from, index, home)) return home;
  }
  int empty = -1;
  for (int to = Tableau; to < Piles; ++to) {
    if (!canMove(from, index, to)) continue;
    if (!m_piles[to].empty()) return to;
    // A king already at the foot of its column gains nothing from another empty one.
    if (empty < 0 && !(from >= Tableau && index == 0)) empty = to;
  }
  return empty;
}

bool Game::play(int from, int to, int count) {
  Move move{from, to, count, false};
  if (from == Stock && to == Waste) {
    auto &stock = m_piles[Stock];
    if (stock.empty() || count != std::min(int(Draw), int(stock.size()))) return false;
    for (int i = 0; i < count; ++i) {
      m_piles[Waste].push_back({stock.back().id, true});
      stock.pop_back();
    }
  } else if (from == Waste && to == Stock) {
    auto &waste = m_piles[Waste];
    if (!m_piles[Stock].empty() || waste.empty() || count != int(waste.size())) return false;
    while (!waste.empty()) {
      m_piles[Stock].push_back({waste.back().id, false});
      waste.pop_back();
    }
  } else {
    if (from < 0 || from >= Piles || count < 1 || count > int(m_piles[from].size())) return false;
    auto &source = m_piles[from];
    const int index = int(source.size()) - count;
    if (!canMove(from, index, to)) return false;
    m_piles[to].insert(m_piles[to].end(), source.begin() + index, source.end());
    source.resize(index);
    if (from >= Tableau && !source.empty() && !source.back().up) {
      source.back().up = true;
      move.flip = true;
    }
  }
  m_moves.push_back(move);
  return true;
}

bool Game::drawStock() {
  if (!m_piles[Stock].empty()) return play(Stock, Waste, std::min(int(Draw), int(m_piles[Stock].size())));
  return play(Waste, Stock, int(m_piles[Waste].size()));
}

bool Game::undo() {
  if (m_moves.empty()) return false;
  const Move move = m_moves.back();
  m_moves.pop_back();
  auto &from = m_piles[move.from];
  auto &to = m_piles[move.to];
  if (move.from == Stock || move.to == Stock) {
    // Draws and recycles both turn the cards over one at a time.
    for (int i = 0; i < move.count; ++i) {
      from.push_back({to.back().id, move.from == Waste});
      to.pop_back();
    }
    return true;
  }
  if (move.flip) from.back().up = false;
  from.insert(from.end(), to.end() - move.count, to.end());
  to.resize(to.size() - move.count);
  return true;
}

int Game::home() const {
  int total = 0;
  for (int pile = Foundation; pile < Tableau; ++pile) total += int(m_piles[pile].size());
  return total;
}

bool Game::finishable() const {
  if (won() || !m_piles[Stock].empty() || !m_piles[Waste].empty()) return false;
  for (int pile = Tableau; pile < Piles; ++pile)
    for (const Card &card : m_piles[pile])
      if (!card.up) return false;
  return true;
}

bool Game::finishStep() {
  if (!finishable()) return false;
  for (int pile = Tableau; pile < Piles; ++pile) {
    if (m_piles[pile].empty()) continue;
    const int top = int(m_piles[pile].size()) - 1;
    const int home = Foundation + m_piles[pile][top].suit();
    if (canMove(pile, top, home)) return play(pile, home, 1);
  }
  return false;
}

bool Game::placeable(const Card &card) const {
  if (card.rank() == int(m_piles[Foundation + card.suit()].size())) return true;
  for (int to = Tableau; to < Piles; ++to) {
    const auto &pile = m_piles[to];
    if (pile.empty() ? card.rank() == 12 : pile.back().red() != card.red() && pile.back().rank() == card.rank() + 1) return true;
  }
  return false;
}

bool Game::stockHelps() const {
  // Nothing played from the waste changes what a pass shows, so one full
  // pass from a fresh stock shows every card the stock will ever offer.
  std::vector<Card> stock = m_piles[Stock], waste = m_piles[Waste];
  for (bool recycled = false;;) {
    if (stock.empty()) {
      if (recycled || waste.empty()) return false;
      stock.assign(waste.rbegin(), waste.rend());
      waste.clear();
      recycled = true;
    }
    for (int i = 0; i < Draw && !stock.empty(); ++i) {
      waste.push_back(stock.back());
      stock.pop_back();
    }
    if (placeable(waste.back())) return true;
  }
}

std::optional<Move> Game::hint() const {
  // A card just brought down from a foundation is there to be built on, not sent straight back.
  const int pulled = !m_moves.empty() && m_moves.back().from >= Foundation && m_moves.back().from < Tableau ? m_moves.back().to : -1;
  auto homeFor = [this](const Card &card) { return card.rank() == int(m_piles[Foundation + card.suit()].size()); };
  // A card that can go home.
  for (int from = Waste; from < Piles; from = from == Waste ? int(Tableau) : from + 1) {
    if (m_piles[from].empty() || from == pulled) continue;
    const int top = int(m_piles[from].size()) - 1;
    const int home = Foundation + m_piles[from][top].suit();
    if (canMove(from, top, home)) return Move{from, home, 1, false};
  }
  // A whole run that leaves its column, turning a card or clearing the space.
  for (int from = Tableau; from < Piles; ++from) {
    const auto &pile = m_piles[from];
    int index = 0;
    while (index < int(pile.size()) && !pile[index].up) ++index;
    if (index >= int(pile.size())) continue;
    for (int to = Tableau; to < Piles; ++to) {
      if (!canMove(from, index, to)) continue;
      if (index == 0 && m_piles[to].empty()) continue;
      return Move{from, to, int(pile.size()) - index, false};
    }
  }
  // Part of a run, when the card it uncovers can then go home. Never onto the
  // card just brought down, which is kept for the move it came down for.
  for (int from = Tableau; from < Piles; ++from) {
    const auto &pile = m_piles[from];
    for (int index = int(pile.size()) - 1; index > 0 && pile[index - 1].up; --index) {
      for (int to = Tableau; to < Piles; ++to) {
        if (to == pulled || m_piles[to].empty() || !canMove(from, index, to)) continue;
        if (homeFor(pile[index - 1])) return Move{from, to, int(pile.size()) - index, false};
      }
    }
  }
  if (!m_piles[Waste].empty()) {
    const int top = int(m_piles[Waste].size()) - 1;
    for (int to = Tableau; to < Piles; ++to)
      if (canMove(Waste, top, to)) return Move{Waste, to, 1, false};
  }
  // A card back down from its foundation, when that gives the waste's card a
  // place to go, or a column's run one that turns the card beneath it. Only
  // those: each is a step that cannot be taken back, so hints never go round.
  for (int home = Foundation; home < Tableau; ++home) {
    if (m_piles[home].size() < 2) continue;
    const Card card = m_piles[home].back();
    for (int to = Tableau; to < Piles; ++to) {
      if (!canMove(home, int(m_piles[home].size()) - 1, to)) continue;
      auto builds = [&](const Card &other) { return other.red() != card.red() && other.rank() + 1 == card.rank(); };
      if (!m_piles[Waste].empty() && builds(m_piles[Waste].back())) return Move{home, to, 1, false};
      for (int from = Tableau; from < Piles; ++from) {
        const auto &pile = m_piles[from];
        if (from == to || pile.empty()) continue;
        int index = int(pile.size()) - 1;
        while (index > 0 && pile[index - 1].up) --index;
        if (index > 0 && builds(pile[index])) return Move{home, to, 1, false};
      }
    }
  }
  // Turning the stock, as long as it has something to offer.
  if (stockHelps()) {
    if (!m_piles[Stock].empty()) return Move{Stock, Waste, std::min(int(Draw), int(m_piles[Stock].size())), false};
    return Move{Waste, Stock, int(m_piles[Waste].size()), false};
  }
  return std::nullopt;
}

}
