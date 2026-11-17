#pragma once

#include "chess.h"
#include <QObject>
#include <QFutureWatcher>
#include <QVariantList>
#include <QStringList>
#include <QTimer>
#include <QLockFile>
#include <unordered_map>

class Backend : public QObject {
  Q_OBJECT
  Q_PROPERTY(QVariantList pieces READ pieces NOTIFY changed)
  Q_PROPERTY(QVariantList targets READ targets NOTIFY changed)
  Q_PROPERTY(int selected READ selected NOTIFY changed)
  Q_PROPERTY(bool whiteTurn READ whiteTurn NOTIFY changed)
  Q_PROPERTY(bool thinking READ thinking NOTIFY changed)
  Q_PROPERTY(bool checked READ checked NOTIFY changed)
  Q_PROPERTY(int checkSquare READ checkSquare NOTIFY changed)
  Q_PROPERTY(bool finished READ finished NOTIFY changed)
  Q_PROPERTY(QString outcome READ outcome NOTIFY changed)
  Q_PROPERTY(QStringList moves READ moves NOTIFY changed)
  Q_PROPERTY(bool canUndo READ canUndo NOTIFY changed)
  Q_PROPERTY(bool promotionPending READ promotionPending NOTIFY changed)
  Q_PROPERTY(int lastFrom READ lastFrom NOTIFY changed)
  Q_PROPERTY(int lastTo READ lastTo NOTIFY changed)
  Q_PROPERTY(bool computer READ computer NOTIFY changed)
  Q_PROPERTY(bool humanWhite READ humanWhite NOTIFY changed)
  Q_PROPERTY(int difficulty READ difficulty NOTIFY changed)
  Q_PROPERTY(int pieceSet READ pieceSet WRITE setPieceSet NOTIFY preferencesChanged)
  // Stills every animation. The window offers no switch for it, and it is not saved: it is how the tests hold the board still.
  Q_PROPERTY(bool reducedMotion READ reducedMotion WRITE setReducedMotion NOTIFY preferencesChanged)
  Q_PROPERTY(bool movesOpen READ movesOpen WRITE setMovesOpen NOTIFY preferencesChanged)
  Q_PROPERTY(bool saveHealthy READ saveHealthy NOTIFY changed)
  Q_PROPERTY(QString error READ error NOTIFY changed)
  Q_PROPERTY(QString fen READ fen NOTIFY changed)
public:
  explicit Backend(const QString &savePath = {}, QObject *parent = nullptr);
  ~Backend() override;
  QVariantList pieces() const { return m_pieces; }
  QVariantList targets() const;
  int selected() const { return m_selected; }
  bool whiteTurn() const { return position().white; }
  bool thinking() const { return m_thinking; }
  bool checked() const { return position().check(position().white); }
  // Where the king in check stands, or -1.
  int checkSquare() const;
  bool finished() const { return !m_outcome.isEmpty(); }
  QString outcome() const { return m_outcome; }
  QStringList moves() const { return m_notation; }
  bool canUndo() const { return !m_moves.empty() && (!m_computer || m_humanWhite || m_moves.size() > 1); }
  bool promotionPending() const { return m_pending.to >= 0; }
  int lastFrom() const { return m_moves.empty() ? -1 : m_moves.back().from; }
  int lastTo() const { return m_moves.empty() ? -1 : m_moves.back().to; }
  bool computer() const { return m_computer; }
  bool humanWhite() const { return m_humanWhite; }
  int difficulty() const { return m_difficulty; }
  int pieceSet() const { return m_pieceSet; }
  bool reducedMotion() const { return m_reducedMotion; }
  bool movesOpen() const { return m_movesOpen; }
  bool saveHealthy() const { return ownsSave() && !m_saveBlocked && !m_saveFailed; }
  QString error() const { return m_error; }
  // The save is held by another process, rather than out of reach for some other reason.
  bool saveContended() const { return m_saveLock && m_saveLock->error() == QLockFile::LockFailedError; }
  // The socket a second launch would knock on could not be opened.
  void reportSocket(const QString &reason);
  bool ownsSave() const { return m_savePath == ":memory:" || (m_saveLock && m_saveLock->isLocked()); }
  QString fen() const { return QString::fromStdString(position().fen()); }
  const Chess::Position &position() const { return m_positions.back(); }
  Q_INVOKABLE void selectSquare(int square);
  Q_INVOKABLE bool move(int from, int to, int promotion = Chess::Empty);
  Q_INVOKABLE void promote(int kind);
  Q_INVOKABLE void cancelSelection();
  Q_INVOKABLE void newGame(bool computer, int difficulty, bool humanWhite = true);
  Q_INVOKABLE void undo();
  Q_INVOKABLE void dismissError();
  void setPieceSet(int value);
  void setReducedMotion(bool value);
  void setMovesOpen(bool value);
signals:
  void changed();
  void preferencesChanged();
  void moved(int id, bool knight, bool capture);
private:
  void apply(Chess::Move move);
  void refresh();
  void scheduleComputer();
  void cancelComputer();
  void save();
  void restore();
  std::vector<Chess::Position> m_positions{Chess::Position::initial()};
  std::unordered_map<std::string,int> m_repetitions;
  std::unique_ptr<QLockFile> m_saveLock;
  std::vector<Chess::Move> m_moves;
  std::vector<Chess::Move> m_legal;
  QStringList m_notation;
  QVariantList m_pieces;
  int m_selected = -1;
  Chess::Move m_pending;
  QString m_outcome, m_error, m_savePath;
  bool m_computer = true, m_humanWhite = true, m_thinking = false;
  int m_difficulty = 1, m_pieceSet = 0;
  bool m_reducedMotion = false, m_movesOpen = false, m_saveBlocked = false, m_saveFailed = false;
  unsigned m_generation = 0;
  // The pause before the computer answers, so the player's piece lands first. Undo and a new game stop it.
  QTimer m_reply;
  std::shared_ptr<std::atomic_bool> m_cancel;
};
