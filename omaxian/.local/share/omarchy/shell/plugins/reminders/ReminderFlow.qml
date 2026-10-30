import Quickshell
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "ReminderFlowModel.js" as ReminderFlowModel

// X11 delta: upstream is a full-screen scrim overlay on a layer-shell surface
// (picom blacks that out). The two-step prompt (minutes -> message) lives in a
// `Ui/CenteredModal` instead: a content-sized card centred on screen, no
// scrim, still themed with the menu palette. Summoned by `omarchy-reminder -i`
// -> `omarchy-shell shell summon omarchy.reminders`.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string step: "minutes"
  property string minutes: ""
  property string filterText: ""
  property string fontFamily: Style.font.menuFamily

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  readonly property string promptText: root.step === "message" ? I18n.t("reminders.messagePrompt") : I18n.t("reminders.minutesPrompt")

  // Anchor the card to the live bar PanelWindow so opening does not map a
  // second DOCK surface (i3 restack flash of bar + dock).
  readonly property var modalAnchorWindow: {
    var bar = root.shell && root.shell.bar
    if (!bar || typeof bar.panelWindowForScreen !== "function") return null
    return bar.panelWindowForScreen(Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    root.opened = true
    root.step = "minutes"
    root.minutes = ""
    root.filterText = ""
    // CenteredModal re-acquires focus once its popup is mapped.
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omarchy.reminders")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
  }

  function submit() {
    var selection = root.filterText

    if (root.step === "minutes") {
      var nextMinutes = ReminderFlowModel.validMinutes(selection)

      if (!selection.trim()) {
        Qt.callLater(function() { root.dismiss() })
        return
      }

      if (!nextMinutes) {
        Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-notification-send", I18n.t("reminders.invalidTitle"), I18n.t("reminders.invalidBody")])
        return
      }

      root.minutes = nextMinutes
      root.step = "message"
      root.filterText = ""
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      return
    }

    if (root.step === "message") {
      var args = [root.omarchyPath + "/bin/omarchy-reminder"].concat(ReminderFlowModel.reminderArgs(root.minutes, selection))
      // Defer so CenteredModal can leave its Keys handler before unmap + the
      // follow-up omarchy-shell indicators refresh IPC (see CenteredModal).
      Qt.callLater(function() {
        root.dismiss()
        Quickshell.execDetached(args)
      })
    }
  }

  CenteredModal {
    id: modal
    open: root.opened
    anchorWindow: root.modalAnchorWindow
    focusTarget: keyCatcher
    background: root.background
    borderSpec: root.borderSpec
    padding: root.contentMargin
    contentWidth: Style.space(340)
    // Card = prompt row plus padding and border on both sides.
    contentHeight: Math.max(root.headerHeight, Math.round(prompt.implicitHeight))
      + 2 * (root.contentMargin + Math.max(1, Style.space(2)))
    onDismissed: root.dismiss()

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (root.filterText) root.setFilter("")
          else Qt.callLater(function() { root.dismiss() })
          event.accepted = true
        } else if (Util.editsFilter(event, root.filterText)) {
          root.setFilter(Util.editedFilter(event, root.filterText))
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.submit()
          event.accepted = true
        } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
          root.setFilter(root.filterText + event.text)
          event.accepted = true
        }
      }

      Text {
        id: prompt
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.filterText || root.promptText
        color: root.foreground
        opacity: root.filterText ? 1 : 0.58
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        elide: Text.ElideRight
      }
    }
  }
}
