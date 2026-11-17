#include "backend.h"

#include <QtConcurrent>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTimer>
#include <algorithm>

namespace {
QString adjudicate(const Chess::Position &p, const std::vector<Chess::Move> &legal, int repetitions) {
  if (legal.empty()) return p.check(p.white) ? (p.white ? "black-wins" : "white-wins") : "stalemate";
  if (p.insufficient()) return "material";
  if (p.halfmove >= 100) return "fifty-moves";
  if (repetitions >= 3) return "repetition";
  return {};
}
}

Backend::Backend(const QString &savePath, QObject *parent) : QObject(parent), m_savePath(savePath) {
  m_reply.setSingleShot(true);
  connect(&m_reply,&QTimer::timeout,this,&Backend::scheduleComputer);
  if (m_savePath.isEmpty()) m_savePath = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/game.json";
  m_repetitions[position().key()] = 1;
  if (m_savePath != ":memory:") {
    QDir().mkpath(QFileInfo(m_savePath).absolutePath());
    m_saveLock = std::make_unique<QLockFile>(m_savePath + ".lock");
    m_saveLock->setStaleLockTime(0);
    if (!m_saveLock->tryLock(0)) {
      m_saveBlocked = true;
      m_error = tr("Another Checkmate window owns this saved game, or its folder is not writable.");
    }
  }
  if (ownsSave()) restore();
  refresh();
  QTimer::singleShot(0, this, &Backend::scheduleComputer);
}
Backend::~Backend() { cancelComputer(); }
int Backend::checkSquare() const {
  if (!checked()) return -1;
  for (int s = 0; s < 64; ++s) if (position().board[s].kind == Chess::King && position().board[s].white == position().white) return s;
  return -1;
}
QVariantList Backend::targets() const {
  QVariantList result;
  for (auto move : m_legal) if (move.from == m_selected && !result.contains(move.to)) result.append(move.to);
  return result;
}
void Backend::refresh() {
  m_legal = position().legal();
  m_outcome = adjudicate(position(),m_legal,m_repetitions[position().key()]);
  if (m_pieces.isEmpty()) {
    for (int id = 0; id < 32; ++id) m_pieces.append(QVariantMap{{"id",id},{"kind",1},{"white",true},{"square",0},{"alive",false}});
  }
  for (int id = 0; id < 32; ++id) {
    auto record = m_pieces[id].toMap(); record["alive"] = false; m_pieces[id] = record;
  }
  for (int s = 0; s < 64; ++s) {
    const auto p = position().board[s];
    if (p.kind) m_pieces[p.id] = QVariantMap{{"id",p.id},{"kind",p.kind},{"white",p.white},{"square",s},{"alive",true}};
  }
  emit changed();
}
void Backend::selectSquare(int square) {
  if (square < 0 || square >= 64 || finished() || m_thinking || promotionPending() || (m_computer && whiteTurn() != m_humanWhite)) return;
  if (m_selected >= 0 && square != m_selected && move(m_selected,square)) return;
  const auto p = position().board[square];
  m_selected = square == m_selected || !p.kind || p.white != whiteTurn() ? -1 : square;
  emit changed();
}
bool Backend::move(int from, int to, int promotion) {
  if (finished() || m_thinking || (m_computer && whiteTurn() != m_humanWhite)) return false;
  for (auto candidate : m_legal) if (candidate.from == from && candidate.to == to) {
    if (candidate.promotion && !promotion) {
      m_pending = candidate; emit changed(); return true;
    }
    if (candidate.promotion == promotion) { m_pending = {}; apply(candidate); return true; }
  }
  return false;
}
void Backend::promote(int kind) {
  if (!promotionPending()) return;
  move(m_pending.from,m_pending.to,kind);
}
void Backend::cancelSelection() { m_pending = {}; m_selected = -1; emit changed(); }
void Backend::apply(Chess::Move move) {
  const auto piece = position().board[move.from];
  const bool capture = position().board[move.to].kind || (piece.kind == Chess::Pawn && move.to == position().ep);
  m_notation.append(QString::fromStdString(position().san(move)));
  m_positions.push_back(position().after(move));
  m_moves.push_back(move);
  ++m_repetitions[position().key()];
  m_selected = -1;
  refresh();
  emit moved(piece.id,piece.kind == Chess::Knight,capture);
  save();
  m_reply.start(m_reducedMotion ? 0 : 420);
}
void Backend::cancelComputer() {
  ++m_generation;
  m_reply.stop();
  if (m_cancel) m_cancel->store(true);
  m_thinking = false;
}
void Backend::scheduleComputer() {
  if (!m_computer || whiteTurn() == m_humanWhite || finished() || m_thinking) return;
  m_thinking = true;
  auto cancel = m_cancel = std::make_shared<std::atomic_bool>(false);
  const auto generation = m_generation;
  const auto p = position();
  const int difficulty = m_difficulty;
  // Only what came after the last capture or pawn move can be repeated.
  const size_t reversible = std::min(m_positions.size(),size_t(p.halfmove) + 1);
  const std::vector<Chess::Position> history(m_positions.end() - reversible,m_positions.end());
  auto watcher = new QFutureWatcher<Chess::Move>(this);
  connect(watcher,&QFutureWatcher<Chess::Move>::finished,this,[this,watcher,generation,cancel] {
    auto result = watcher->result();
    watcher->deleteLater();
    if (cancel->load() || generation != m_generation) return;
    m_thinking = false;
    if (std::find(m_legal.begin(),m_legal.end(),result) != m_legal.end()) apply(result);
    else { m_error = tr("The computer could not choose a legal move. Undo or start a new game."); emit changed(); }
  });
  watcher->setFuture(QtConcurrent::run([p,difficulty,cancel,history] { return Chess::bestMove(p,difficulty,cancel,history); }));
  emit changed();
}
void Backend::newGame(bool computer, int difficulty, bool humanWhite) {
  cancelComputer();
  // A window that does not own the save may still start afresh; its game is simply not kept, as its footer says.
  if (ownsSave()) { m_saveBlocked = false; m_error.clear(); }
  m_computer = computer; m_difficulty = std::clamp(difficulty,0,2); m_humanWhite = humanWhite;
  m_positions = {Chess::Position::initial()}; m_moves.clear(); m_notation.clear(); m_pending = {}; m_selected = -1;
  m_repetitions.clear(); m_repetitions[position().key()] = 1;
  refresh(); save(); scheduleComputer();
}
void Backend::undo() {
  if (!canUndo()) return;
  cancelComputer();
  do {
    --m_repetitions[position().key()];
    m_positions.pop_back(); m_moves.pop_back(); m_notation.removeLast();
  } while (m_computer && !m_moves.empty() && whiteTurn() != m_humanWhite);
  m_selected = -1; m_pending = {};
  refresh(); save(); scheduleComputer();
}
void Backend::dismissError() { m_error.clear(); emit changed(); }
void Backend::reportSocket(const QString &reason) {
  // A save problem is the more pressing thing to read, so it is not replaced.
  if (m_error.isEmpty()) m_error = tr("Opening Checkmate again will open another window: %1").arg(reason);
  emit changed();
}
void Backend::setPieceSet(int value) {
  if (value < 0 || value > 3 || value == m_pieceSet) return;
  m_pieceSet = value; emit preferencesChanged(); save();
}
void Backend::setReducedMotion(bool value) {
  if (value == m_reducedMotion) return;
  m_reducedMotion = value; emit preferencesChanged();
}
void Backend::setMovesOpen(bool value) {
  if (value == m_movesOpen) return;
  m_movesOpen = value; emit preferencesChanged(); save();
}
void Backend::save() {
  if (m_savePath == ":memory:" || m_saveBlocked || !ownsSave()) return;
  QJsonArray moves;
  for (auto m : m_moves) moves.append(QJsonArray{m.from,m.to,m.promotion});
  QJsonObject data{{"version",1},{"moves",moves},{"computer",m_computer},{"humanWhite",m_humanWhite},
                   {"difficulty",m_difficulty},{"pieceSet",m_pieceSet},{"movesOpen",m_movesOpen}};
  QDir().mkpath(QFileInfo(m_savePath).absolutePath());
  QSaveFile file(m_savePath);
  file.setDirectWriteFallback(false);
  const auto bytes = QJsonDocument(data).toJson();
  if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size() || !file.commit()) {
    m_saveFailed = true;
    m_error = tr("Could not save your game: %1").arg(file.errorString()); emit changed();
  } else if (m_saveFailed) {
    m_saveFailed = false; m_error.clear(); emit changed();
  }
}
void Backend::restore() {
  if (m_savePath == ":memory:" || !QFile::exists(m_savePath)) return;
  QFile file(m_savePath);
  if (!file.open(QIODevice::ReadOnly)) { m_saveBlocked = true; m_error = tr("Could not open your saved game: %1").arg(file.errorString()); return; }
  if (file.size() > 2 * 1024 * 1024) {
    m_saveBlocked = true; m_error = tr("The saved game is too large to open."); return;
  }
  QJsonParseError error;
  auto data = QJsonDocument::fromJson(file.readAll(),&error).object();
  auto invalid = [&] {
    m_saveBlocked = true;
    m_positions = {Chess::Position::initial()}; m_moves.clear(); m_notation.clear();
    // Keep the damaged save intact until the player explicitly starts again.
    m_repetitions.clear(); m_repetitions[position().key()] = 1;
    m_error = tr("The saved game is damaged. Start a new game to replace it.");
  };
  if (error.error != QJsonParseError::NoError || data["version"].toInt() != 1 || !data["moves"].isArray() || data["moves"].toArray().size() > 20000) { invalid(); return; }
  for (auto value : data["moves"].toArray()) {
    auto entry = value.toArray();
    if (entry.size() != 3) { invalid(); return; }
    Chess::Move move{entry[0].toInt(-1),entry[1].toInt(-1),entry[2].toInt(-1)};
    const auto legal = position().legal();
    if (!adjudicate(position(),legal,m_repetitions[position().key()]).isEmpty() || std::find(legal.begin(),legal.end(),move) == legal.end()) { invalid(); return; }
    m_notation.append(QString::fromStdString(position().san(move)));
    m_positions.push_back(position().after(move)); m_moves.push_back(move);
    ++m_repetitions[position().key()];
  }
  m_computer = data["computer"].toBool(true); m_humanWhite = data["humanWhite"].toBool(true);
  m_difficulty = std::clamp(data["difficulty"].toInt(1),0,2); m_pieceSet = std::clamp(data["pieceSet"].toInt(),0,3);
  m_movesOpen = data["movesOpen"].toBool();
}
