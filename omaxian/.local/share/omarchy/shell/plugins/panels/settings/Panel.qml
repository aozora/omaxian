import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Settings: a real FloatingWindow (i3-managed toplevel), not a PopupWindow
// overlay. Open from the Omarchy menu, Control Panel footer, Super+Ctrl+s,
// or `omarchy-shell shell toggle omaxian.settings`.
//
// i3 matches title "Omaxian Settings" (see config.d/05_rules.conf) to float,
// focus, and centre it. Tabs are Loader'd by URL so a compile failure in one
// tab cannot take down the window. Escape / title-bar × / WM close all dismiss.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null

  property bool opened: false
  property string activeTab: "bar"

  readonly property string windowTitle: "Omaxian Settings"
  readonly property int contentWidth: Style.space(800)
  readonly property int contentHeight: Style.space(540)
  readonly property int windowPad: Style.spacing.popupPadding

  readonly property var tabs: [
    { value: "bar", label: "Bar", icon: "󰍜" },
    { value: "dock", label: "Dock", icon: "󰕰" },
    { value: "appearance", label: "Appearance", icon: "󰸌" },
    { value: "widgets", label: "Widgets", icon: "󰡀" },
    { value: "plugins", label: "Plugins", icon: "󰐱" },
    { value: "startup", label: "Startup", icon: "󰐥" },
    { value: "advanced", label: "Advanced", icon: "" }
  ]

  function tabExists(name) {
    var tab = String(name || "")
    for (var i = 0; i < root.tabs.length; i++) {
      if (root.tabs[i].value === tab) return true
    }
    return false
  }

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) { payload = {} }
    var tab = String(payload.tab || payload.menu || "")
    if (root.tabExists(tab)) root.activeTab = tab
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omaxian.settings")
    else
      root.close()
  }

  readonly property color fg: Color.popups.text
  readonly property color accent: Color.accent
  readonly property string fontFamily: Style.font.family

  FloatingWindow {
    id: win
    title: root.windowTitle
    visible: root.opened
    color: Color.popups.background
    implicitWidth: root.contentWidth
    implicitHeight: root.contentHeight
    minimumSize: Qt.size(Style.space(640), Style.space(420))

    // WM close ($mod+Shift+q / titlebar destroy) — not emitted when we only
    // set visible false via dismiss().
    onClosed: root.dismiss()

    onVisibleChanged: {
      if (visible)
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }

    BorderSurface {
      id: frame
      anchors.fill: parent
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      padding: root.windowPad

      Item {
        id: keyCatcher
        anchors.fill: parent
        anchors.topMargin: frame.contentTopInset
        anchors.rightMargin: frame.contentRightInset
        anchors.bottomMargin: frame.contentBottomInset
        anchors.leftMargin: frame.contentLeftInset
        focus: true

        Keys.onEscapePressed: root.dismiss()

        Item {
          id: titleBar
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(36)

          // Drag the i3 floating window from the title strip. Close button
          // sits above this MouseArea and keeps its own clicks.
          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.OpenHandCursor
            onPressed: win.startSystemMove()
          }

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Settings"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Button {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            z: 1
            text: "×"
            tooltipText: "Close"
            bordered: true
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(8)
            verticalPadding: Style.space(4)
            onClicked: root.dismiss()
          }
        }

        Row {
          id: body
          anchors.top: titleBar.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.topMargin: Style.space(10)
          spacing: Style.space(14)

          Column {
            id: tabStrip
            width: Style.space(160)
            spacing: Style.space(4)

            Repeater {
              model: root.tabs
              delegate: Button {
                required property var modelData
                width: tabStrip.width
                leftAlign: true
                text: modelData.label
                iconText: modelData.icon
                selected: root.activeTab === modelData.value
                bordered: true
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: root.activeTab = modelData.value
              }
            }
          }

          Item {
            id: contentArea
            width: body.width - tabStrip.width - body.spacing
            height: body.height
            clip: true

            readonly property Item activeLoader: {
              if (root.activeTab === "bar") return barLoader
              if (root.activeTab === "dock") return dockLoader
              if (root.activeTab === "appearance") return appearanceLoader
              if (root.activeTab === "widgets") return widgetsLoader
              if (root.activeTab === "plugins") return pluginsLoader
              if (root.activeTab === "startup") return startupLoader
              if (root.activeTab === "advanced") return advancedLoader
              return null
            }

            component TabLoader: Loader {
              id: tabLoader
              property string tabId: ""
              property string tabUrl: ""

              anchors.fill: parent
              visible: root.activeTab === tabId
              asynchronous: false
              active: root.opened && root.activeTab === tabId

              onActiveChanged: {
                if (active) {
                  setSource(Qt.resolvedUrl(tabUrl), {
                    shell: root.shell,
                    pluginRegistry: root.pluginRegistry,
                    barWidgetRegistry: root.barWidgetRegistry,
                    foreground: root.fg
                  })
                } else if (!root.opened) {
                  source = ""
                }
              }

              onStatusChanged: {
                if (status === Loader.Error)
                  console.warn("omaxian.settings tab '" + tabId + "' failed: " + errorString())
              }

              onLoaded: {
                if (!item) return
                if ("shell" in item) item.shell = root.shell
                if ("pluginRegistry" in item) item.pluginRegistry = root.pluginRegistry
                if ("barWidgetRegistry" in item) item.barWidgetRegistry = root.barWidgetRegistry
                if ("foreground" in item) item.foreground = root.fg
              }

              Binding {
                target: tabLoader.item
                property: "shell"
                value: root.shell
                when: tabLoader.item !== null
              }
              Binding {
                target: tabLoader.item
                property: "pluginRegistry"
                value: root.pluginRegistry
                when: tabLoader.item !== null
              }
              Binding {
                target: tabLoader.item
                property: "barWidgetRegistry"
                value: root.barWidgetRegistry
                when: tabLoader.item !== null
              }
            }

            TabLoader { id: barLoader; tabId: "bar"; tabUrl: "BarTab.qml" }
            TabLoader { id: dockLoader; tabId: "dock"; tabUrl: "DockTab.qml" }
            TabLoader { id: appearanceLoader; tabId: "appearance"; tabUrl: "AppearanceTab.qml" }
            TabLoader { id: widgetsLoader; tabId: "widgets"; tabUrl: "WidgetsTab.qml" }
            TabLoader { id: pluginsLoader; tabId: "plugins"; tabUrl: "PluginsTab.qml" }
            TabLoader { id: startupLoader; tabId: "startup"; tabUrl: "StartupTab.qml" }
            TabLoader { id: advancedLoader; tabId: "advanced"; tabUrl: "AdvancedTab.qml" }

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
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              text: {
                var loader = contentArea.activeLoader
                return loader ? ("Tab failed to load:\n" + String(loader.errorString || "")) : ""
              }
            }
          }
        }
      }
    }
  }
}
