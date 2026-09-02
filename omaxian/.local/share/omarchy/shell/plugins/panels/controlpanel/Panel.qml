import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Control Panel: one bar icon, one popup, a vertical tab sidebar switching
// between panes that used to each be their own bar-icon+popup pair
// (wallpaper, theme, audio, bluetooth, monitor). A brand new, self-contained
// plugin — it does not import or modify any of those original widgets; each
// tab here is its own fresh implementation.
//
// Tabs are Loader'd by URL (not inlined as typed children) so a compile/import
// failure in one tab — e.g. Quickshell.Bluetooth missing/stub — cannot take
// down the whole bar widget. The gear icon still mounts; only that tab's
// pane shows an error string.
//
// Sidebar is vertical, not a horizontal strip: a horizontal row of all 5 tab
// labels is wider than the narrowest tab's own content (Audio, 380px), which
// overflowed the popup on open. A vertical list's width doesn't grow with
// tab count, and Row's own implicitHeight (max of its children) means the
// popup is never shorter than the full tab list even when the active tab's
// content is short.
//
// Keyboard model: deliberately NOT wrapped in a single Ui/PanelKeyCatcher
// the way a single-purpose panel (e.g. plugins/panels/monitor) is — that
// would eat Left/Right/h/l before a cursor-driven tab's own key handling
// ever saw them. Only Tab/Backtab (switch bar panel) and Escape (close) are
// handled at this top level, regardless of which child currently holds
// focus; everything else is scoped naturally by normal Qt focus rules to
// whichever child has it.
Panel {
  id: root
  moduleName: "omaxian.controlpanel"
  ipcTarget: "omaxian.controlpanel"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits, matching every other Phase-5-style panel in this repo.
  manageIpc: false

  property string activeTab: "audio"

  readonly property var tabs: [
    { value: "audio", label: "Audio", icon: "󰕾" },
    { value: "bluetooth", label: "Bluetooth", icon: "󰂯" },
    { value: "wallpaper", label: "Wallpaper", icon: "󰥶" },
    { value: "theme", label: "Theme", icon: "󰸌" },
    { value: "monitor", label: "Monitor", icon: "󰍹" }
  ]

  function showTab(name) {
    var tab = String(name || "")
    var found = false
    for (var i = 0; i < root.tabs.length; i++) {
      if (root.tabs[i].value === tab) { found = true; break }
    }
    if (!found) return
    root.activeTab = tab
    root.open()
  }

  IpcHandler {
    target: "omaxian.controlpanel"
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function showTab(name: string): void { root.showTab(name) }
  }

  // Compat for menu / i3 keybinds that still call `theme` / `wallpapers`
  // IPC (those bar widgets were folded into this panel and are off the
  // default layout, so their IpcHandlers are not mounted).
  IpcHandler {
    target: "theme"
    function toggle(): void { root.showTab("theme") }
    function hide(): void { if (root.activeTab === "theme") root.close() }
  }

  IpcHandler {
    target: "wallpapers"
    function toggle(): void { root.showTab("wallpaper") }
    function hide(): void { if (root.activeTab === "wallpaper") root.close() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰒓"
    tooltipText: "Control Panel"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    // + verticalContentInset (misleadingly named — it's padding*2 + a
    // uniform border width, the same on every side): layoutRow is anchored
    // left/right to the padded interior, not sized off its own
    // implicitWidth, so contentWidth has to request the full desired
    // *outer* size (content + insets) or the interior clips it. Same
    // reasoning fittedContentHeight already bakes in for height; there's no
    // fittedContentWidth equivalent, so it's added here explicitly.
    contentWidth: panel.fittedContentWidth(layoutRow.implicitWidth + panel.verticalContentInset)
    contentHeight: panel.fittedContentHeight(layoutRow.implicitHeight)

    focusTarget: keyCatcher

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.close(); event.accepted = true; return
        }
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          root.switchPanel((event.modifiers & Qt.ShiftModifier) || event.key === Qt.Key_Backtab ? -1 : 1)
          event.accepted = true
        }
      }

      // Sidebar (left) + content (right), instead of a horizontal tab strip
      // above the content: with 5 tabs a horizontal Ui/ButtonGroup row is
      // wider than the narrowest tab's own content (Audio, 380px), so the
      // strip overflowed the popup on open. A vertical list doesn't have
      // that problem — its width is fixed regardless of tab count — and
      // Row's own implicitHeight (max of its children's) means the popup is
      // never shorter than the full tab list, even when the active tab's
      // content is short.
      Row {
        id: layoutRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Column {
          id: tabStripColumn
          spacing: Style.space(4)

          Repeater {
            model: root.tabs

            delegate: Button {
              required property var modelData
              width: Style.space(160)
              leftAlign: true
              text: modelData.label
              iconText: modelData.icon
              selected: root.activeTab === modelData.value
              bordered: true
              foreground: root.bar ? root.bar.foreground : Color.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: root.activeTab = modelData.value
            }
          }

          Item { height: Style.space(8); width: 1 }

          Button {
            width: Style.space(160)
            leftAlign: true
            text: "Settings"
            iconText: ""
            bordered: true
            foreground: root.bar ? root.bar.foreground : Color.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: {
              root.close()
              Qt.callLater(function() {
                if (root.bar && root.bar.shell && typeof root.bar.shell.toggle === "function")
                  root.bar.shell.toggle("omaxian.settings")
              })
            }
          }
        }

        Item {
          id: contentArea

          readonly property Item activeLoader: {
            if (root.activeTab === "audio") return audioLoader
            if (root.activeTab === "bluetooth") return bluetoothLoader
            if (root.activeTab === "wallpaper") return wallpaperLoader
            if (root.activeTab === "theme") return themeLoader
            if (root.activeTab === "monitor") return monitorLoader
            return null
          }
          readonly property Item activeItem: {
            var loader = activeLoader
            return loader && loader.status === Loader.Ready ? loader.item : null
          }
          implicitWidth: {
            if (activeItem) return activeItem.implicitWidth
            // Keep a usable pane size while loading / on error so the popup
            // doesn't collapse to the sidebar alone.
            return Style.space(380)
          }
          implicitHeight: {
            if (activeItem) return activeItem.implicitHeight
            return Style.space(200)
          }
          width: implicitWidth
          height: implicitHeight

          // Shared wiring for every tab Loader: defer compilation until the
          // tab is selected, inject bar/active via setSource (so first-frame
          // bindings like root.bar.foreground don't run against null — that
          // left Audio/Bluetooth/Monitor as blank panes after the URL-Loader
          // split), and surface compile errors instead of killing the icon.
          component TabLoader: Loader {
            id: tabLoader
            property string tabId: ""
            property string tabUrl: ""
            property bool needsBar: true
            property bool emitsPicked: false
            property bool _pickedHooked: false

            anchors.fill: parent
            visible: root.activeTab === tabId
            asynchronous: false

            // Load while this tab is selected and the popup is open; drop the
            // source when the popup closes so the next open is a clean slate.
            active: root.opened && root.activeTab === tabId

            onActiveChanged: {
              if (active) {
                var props = { active: true }
                if (needsBar) props.bar = root.bar
                setSource(Qt.resolvedUrl(tabUrl), props)
              } else if (!root.opened) {
                source = ""
                _pickedHooked = false
              }
            }

            onStatusChanged: {
              if (status === Loader.Error)
                console.warn("omaxian.controlpanel tab '" + tabId + "' failed: " + errorString())
            }

            onLoaded: {
              if (!item) return
              if (needsBar) item.bar = root.bar
              item.active = root.opened && visible
              if (emitsPicked && item.picked && !_pickedHooked) {
                item.picked.connect(function() { root.close() })
                _pickedHooked = true
              }
            }

            Binding {
              target: tabLoader.item
              property: "active"
              value: root.opened && tabLoader.visible
              when: tabLoader.item !== null
            }
            Binding {
              target: tabLoader.item
              property: "bar"
              value: root.bar
              when: tabLoader.needsBar && tabLoader.item !== null
            }
          }

          TabLoader {
            id: audioLoader
            tabId: "audio"
            tabUrl: "AudioTab.qml"
          }
          TabLoader {
            id: bluetoothLoader
            tabId: "bluetooth"
            tabUrl: "BluetoothTab.qml"
          }
          TabLoader {
            id: wallpaperLoader
            tabId: "wallpaper"
            tabUrl: "WallpaperTab.qml"
            needsBar: false
            emitsPicked: true
          }
          TabLoader {
            id: themeLoader
            tabId: "theme"
            tabUrl: "ThemeTab.qml"
            needsBar: false
            emitsPicked: true
          }
          TabLoader {
            id: monitorLoader
            tabId: "monitor"
            tabUrl: "MonitorTab.qml"
          }

          Text {
            anchors.centerIn: parent
            visible: {
              var loader = contentArea.activeLoader
              return !!(loader && loader.visible && loader.status === Loader.Error)
            }
            width: parent.width - Style.space(24)
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            color: Color.urgent
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.size
            text: {
              var loader = contentArea.activeLoader
              // Qt 6 Loader exposes errorString as a string property, not a method.
              return loader ? ("Tab failed to load:\n" + String(loader.errorString || "")) : ""
            }
          }
        }
      }
    }
  }
}
