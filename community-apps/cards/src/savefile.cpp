#include "savefile.h"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>

namespace SaveFile {

Result read(const QString &path, Klondike::Game *game, QJsonObject *data, QString *problem) {
  if (!QFile::exists(path)) return Result::Missing;
  QFile file(path);
  if (!file.open(QIODevice::ReadOnly)) {
    if (problem) *problem = file.errorString();
    return Result::Unreadable;
  }
  if (file.size() > MaxBytes) return Result::TooLarge;
  QJsonParseError error;
  const QJsonObject saved = QJsonDocument::fromJson(file.readAll(), &error).object();
  const qint64 seed = saved["seed"].toInteger();
  if (error.error != QJsonParseError::NoError || saved["version"].toInt() != 1 || !saved["moves"].isArray()
      || saved["moves"].toArray().size() > MaxMoves || seed <= 0 || seed > 0xffffffffll)
    return Result::Damaged;
  Klondike::Game replayed{quint32(seed)};
  for (const auto value : saved["moves"].toArray()) {
    const QJsonArray move = value.toArray();
    // A won game takes no more moves, so a save that goes on past one is not ours.
    if (move.size() != 3 || replayed.won() || !replayed.play(move[0].toInt(-1), move[1].toInt(-1), move[2].toInt(-1))) return Result::Damaged;
  }
  *game = replayed;
  if (data) *data = saved;
  return Result::Ok;
}

}
