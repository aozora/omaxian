import Quickshell
import QtQuick
import qs.Commons
import qs.Ui
import "ReminderFlowModel.js" as ReminderFlowModel

// X11 delta (Phase 9): upstream is a full-screen `WlrLayershell` scrim overlay
// (picom blacks that out). Here the two-step prompt (minutes → message) lives
// in a `Ui/CenteredModal` — a content-sized card centred on screen. Replaces
// the fragile `omarchy-reminder -i` rofi path (the repo's `.rasi` theme files
// segfault rofi 1.7.5). Summoned by `omarchy-reminder -i` →
// `omarchy-shell shell summon omarchy.reminders`.
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

  readonly property string promptText: root.step === "message" ? "Reminder message" : "Remind in minutes"

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    root.opened = true
    root.step = "minutes"
    root.minutes = ""
    root.filterText = ""
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
        root.dismiss()
        return
      }

      if (!nextMinutes) {
        Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-notification-send", "Invalid reminder", "Enter the number of minutes"])
        return
      }

      root.minutes = nextMinutes
      root.step = "message"
      root.filterText = ""
      return
    }

    if (root.step === "message") {
      var args = [root.omarchyPath + "/bin/omarchy-reminder"].concat(ReminderFlowModel.reminderArgs(root.minutes, selection))
      root.dismiss()
      Quickshell.execDetached(args)
    }
  }

  CenteredModal {
    id: modal
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: Style.space(340)
    contentHeight: Math.round(prompt.implicitHeight) + Style.space(20)
    onDismissed: root.dismiss()

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (root.filterText) root.setFilter("")
          else root.dismiss()
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
        text: root.filterText || (root.promptText + "…")
        color: Color.popups.text
        opacity: root.filterText ? 1 : 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        elide: Text.ElideRight
      }
    }
  }
}
