# Development

[← README](../README.md)

```
manifest.json      plugin metadata
preview.png        marketplace preview, the same shot as the README hero
BarWidget.qml      the bar item; owns the button, forwards to the panel
Panel.qml          state, network, and the popup
lib/Net.js         host allowlist, URL builders, curl argv
lib/Model.js       parsing and normalisation of every response
lib/Places.js      the bundled index: search, nearest station
lib/Symbols.js     MeteoSwiss symbol numbers to glyphs and descriptions
lib/I18n.js        interface strings
ui/Chart.qml       the chart used by all three detail views
ui/StatCell.qml    one measured value with its forecast band
ui/PlaceChip.qml   a town in the favourites strip
ui/SwissCross.qml  the cross laid over the bar icon
ui/TickBox.qml     the warning on/off ticks
data/              generated indexes; see tools/build-data.sh
tools/test.js      unit tests for lib/*.js
docs/              the manual, the data and security notes, and their images
```

The QML is a view over `lib/*.js`, and that is where the tests are:

```bash
node tools/test.js
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" Panel.qml
```

To iterate, copy the checkout to
`~/.config/omarchy/plugins/jmaeder.swissweather/`. Saving a file there reloads
plugin code, but a component already mounted in the bar keeps its old
definition — run `omarchy-restart-shell` to be sure you are looking at your
edit.
