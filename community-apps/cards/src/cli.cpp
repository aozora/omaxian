#include "cli.h"
#include "klondike.h"
#include "savefile.h"
#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>
#include <QStandardPaths>
#include <iostream>

using namespace Klondike;

namespace {
// "AS", "10H", "KD": the rank, then the suit's initial.
QString name(const Card &card) {
  static const char *ranks[] = {"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"};
  return QString(ranks[card.rank()]) + "SHDC"[card.suit()];
}

QJsonArray names(const std::vector<Card> &pile, bool hidden) {
  QJsonArray result;
  for (const Card &card : pile) result.append(hidden && !card.up ? QString("??") : name(card));
  return result;
}

QJsonObject describe(const Game &game) {
  QJsonArray foundations, tableau;
  for (int pile = Foundation; pile < Tableau; ++pile) foundations.append(names(game.pile(pile), false));
  for (int pile = Tableau; pile < Piles; ++pile) tableau.append(names(game.pile(pile), true));
  return {{"seed", qint64(game.seed())}, {"moves", int(game.moves().size())}, {"home", game.home()},
          {"won", game.won()}, {"stock", int(game.pile(Stock).size())}, {"waste", names(game.pile(Waste), false)},
          {"foundations", foundations}, {"tableau", tableau}};
}

void print(const Game &game, bool json) {
  const QJsonObject state = describe(game);
  if (json) {
    std::cout << QJsonDocument(state).toJson(QJsonDocument::Compact).constData() << '\n';
    return;
  }
  auto line = [](const QJsonValue &cards) {
    QStringList words;
    for (const auto card : cards.toArray()) words << card.toString();
    return words.isEmpty() ? std::string("-") : words.join(' ').toStdString();
  };
  std::cout << "Stock " << state["stock"].toInt() << "  Waste " << line(state["waste"]) << '\n';
  for (int suit = 0; suit < 4; ++suit) std::cout << "Home " << "SHDC"[suit] << "  " << line(state["foundations"].toArray()[suit]) << '\n';
  for (int column = 0; column < 7; ++column) std::cout << "Column " << column + 1 << "  " << line(state["tableau"].toArray()[column]) << '\n';
}
}

int runCli(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  app.setApplicationName("cards");
  QStringList args = app.arguments().mid(1);
  const QString command = args.takeFirst();
  const bool json = args.removeAll("--json") > 0;
  auto fail = [&](const QString &message) { std::cerr << message.toStdString() << '\n'; return 1; };
  if (command == "deal") {
    if (args.size() > 1) return fail("Usage: cards deal [SEED] [--json]");
    bool ok = true;
    const quint32 seed = args.isEmpty() ? QRandomGenerator::global()->bounded(1u, 0xffffffffu) : args.first().toUInt(&ok);
    if (!ok || seed == 0) return fail("The seed is a whole number from 1 to 4294967295.");
    print(Game(seed), json);
    return 0;
  }
  if (command != "inspect") return fail("Unknown command. Use cards --help.");
  if (!args.isEmpty()) return fail("Usage: cards inspect [--json]");
  Game game;
  QString problem;
  switch (SaveFile::read(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/game.json", &game, nullptr, &problem)) {
  case SaveFile::Result::Missing: return fail("There is no saved game.");
  case SaveFile::Result::Unreadable: return fail("Could not read saved game: " + problem);
  case SaveFile::Result::TooLarge: return fail("Saved game is too large.");
  case SaveFile::Result::Damaged: return fail("Invalid saved game.");
  case SaveFile::Result::Ok: break;
  }
  print(game, json);
  return 0;
}
