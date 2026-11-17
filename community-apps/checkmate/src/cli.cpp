#include "cli.h"
#include "backend.h"
#include <QCoreApplication>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <iostream>

int runCli(int argc, char **argv) {
  QCoreApplication app(argc,argv);
  app.setApplicationName("checkmate");
  const auto args=app.arguments();
  const QString command=args.value(1);
  const bool json=args.contains("--json");
  auto fail=[&](const QString &message) { std::cerr << message.toStdString() << '\n'; return 1; };
  if (command=="legal") {
    QStringList positional=args.mid(2); positional.removeAll("--json");
    if (positional.size()>1) return fail("Usage: checkmate legal ['FEN'] [--json]");
    try {
      const auto p=positional.isEmpty() ? Chess::Position::initial() : Chess::Position::fromFen(positional.first().toStdString());
      QJsonArray moves;
      for (auto move : p.legal()) {
        auto text=Chess::squareName(move.from)+Chess::squareName(move.to);
        if (move.promotion) text+=char(std::tolower(" PNBRQK"[move.promotion]));
        moves.append(QString::fromStdString(text));
      }
      if (json) std::cout << QJsonDocument(QJsonObject{{"fen",QString::fromStdString(p.fen())},{"moves",moves}}).toJson(QJsonDocument::Compact).constData() << '\n';
      else for (auto value : moves) std::cout << value.toString().toStdString() << '\n';
      return 0;
    } catch (const std::exception &error) { return fail(QString::fromUtf8(error.what())); }
  }
  if (command!="inspect" && command!="export") return fail("Unknown command. Use checkmate --help.");
  if (args.size()!=(json ? 3 : 2)) return fail("Usage: checkmate inspect|export [--json]");
  QFile file(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)+"/game.json");
  if (!file.open(QIODevice::ReadOnly)) return fail("Could not read saved game: "+file.errorString());
  if (file.size()>2*1024*1024) return fail("Saved game is too large.");
  QJsonParseError error;
  const auto data=QJsonDocument::fromJson(file.readAll(),&error).object();
  if (error.error!=QJsonParseError::NoError || data["version"].toInt()!=1 || !data["moves"].isArray() || data["moves"].toArray().size()>20000) return fail("Invalid saved game.");
  Backend game(":memory:"); game.newGame(false,0);
  for (auto value : data["moves"].toArray()) {
    const auto move=value.toArray();
    if (move.size()!=3 || !game.move(move[0].toInt(-1),move[1].toInt(-1),move[2].toInt(-1)) || game.promotionPending()) return fail("Invalid move in saved game.");
  }
  if (command=="inspect") {
    QJsonObject result{{"fen",game.fen()},{"moves",QJsonArray::fromStringList(game.moves())},
                       {"outcome",game.outcome()},{"whiteToMove",game.whiteTurn()}};
    if (json) std::cout << QJsonDocument(result).toJson(QJsonDocument::Compact).constData() << '\n';
    else std::cout << game.fen().toStdString() << '\n';
  } else {
    const QString result=game.outcome()=="white-wins" ? "1-0" : game.outcome()=="black-wins" ? "0-1" : game.finished() ? "1/2-1/2" : "*";
    QString pgn="[Event \"Checkmate\"]\n[Result \""+result+"\"]\n\n";
    const auto moves=game.moves();
    for (int i=0;i<moves.size();++i) {
      if (i%2==0) pgn+=QString::number(i/2+1)+". ";
      pgn+=moves[i]+" ";
    }
    pgn+=result+"\n";
    if (json) std::cout << QJsonDocument(QJsonObject{{"pgn",pgn}}).toJson(QJsonDocument::Compact).constData() << '\n';
    else std::cout << pgn.toStdString();
  }
  return 0;
}
