#pragma once

#include "klondike.h"
#include <QJsonObject>
#include <QString>

// Reading a saved game back, shared by the window and the headless commands
// so both accept exactly the same files.
namespace SaveFile {

// A game that has made this many moves stops recording more, so what is
// written can always be read back.
enum { MaxMoves = 100000, MaxBytes = 2 * 1024 * 1024 };

enum class Result { Missing, Unreadable, TooLarge, Damaged, Ok };

// Replays the save at `path` into `game`, and hands back everything else it
// holds in `data`. `problem` gets the system's words when it cannot be read.
Result read(const QString &path, Klondike::Game *game, QJsonObject *data = nullptr, QString *problem = nullptr);

}
