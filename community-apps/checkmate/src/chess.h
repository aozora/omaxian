#pragma once

#include <array>
#include <string>
#include <vector>
#include <atomic>
#include <memory>

namespace Chess {
enum Kind { Empty, Pawn, Knight, Bishop, Rook, Queen, King };
struct Piece {
  int kind = Empty;
  bool white = true;
  int id = -1;
};
struct Move {
  int from = -1, to = -1, promotion = Empty;
  bool operator==(const Move &other) const { return from == other.from && to == other.to && promotion == other.promotion; }
};
struct Position {
  std::array<Piece, 64> board{};
  bool white = true;
  int castle = 15, ep = -1, halfmove = 0, fullmove = 1;
  static Position initial();
  static Position fromFen(const std::string &fen);
  std::string fen() const;
  std::string key() const;
  bool attacked(int square, bool byWhite) const;
  bool check(bool side) const;
  bool insufficient() const;
  std::vector<Move> legal() const;
  // Whether the side to move has any move at all, without listing them.
  bool anyLegal() const;
  // Every move the pieces could make, before asking whether it leaves the mover in check.
  std::vector<Move> candidates() const;
  Position after(Move move) const;
  std::string san(Move move) const;
};
std::string squareName(int square);
int square(const std::string &name);
uint64_t perft(const Position &position, int depth);
Move bestMove(const Position &position, int level, const std::shared_ptr<std::atomic_bool> &cancel,
              const std::vector<Position> &history = {});
}
