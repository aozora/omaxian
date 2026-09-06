import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// X11 delta (Phase 9): upstream is a full-screen `WlrLayershell` scrim overlay
// with `WlrKeyboardFocus.Exclusive`. That maps to a full-screen `PanelWindow`
// on X11, which picom's glx backend blacks out (fullscreen unredirection).
// Here the QR sits in a `Ui/CenteredModal` — a content-sized `PopupWindow`
// centred on screen, no full-screen surface. No dimming scrim; Escape / the
// IPC toggle dismiss (the modal's `grabFocus` also dismisses on an outside
// press). `omarchy-network-{qr,password}` were vendored in Phase 5.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string iface: ""
  property string ssid: ""
  property bool secured: false

  property var qrRows: []
  property int qrSize: 0
  property string error: ""
  property bool loading: false
  property bool expectedStop: false
  property bool pendingShow: false
  property string pendingIface: ""
  property string password: ""
  property bool passwordVisible: false
  property string passwordError: ""
  property bool pwExpectedStop: false

  readonly property bool showingQr: qrSize > 0 && !loading && error === ""
  readonly property string fontFamily: Style.font.family

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    root.ssid = payload.ssid !== undefined ? String(payload.ssid) : ""
    generate(String(payload.iface || ""))
    root.opened = true
  }

  function close() {
    root.opened = false
    root.pendingShow = false
    if (qrProc.running) {
      root.expectedStop = true
      qrProc.running = false
    }
    if (pwProc.running) pwProc.running = false
    root.qrSize = 0
    root.qrRows = []
    root.error = ""
    root.loading = false
    root.iface = ""
    root.ssid = ""
    root.secured = false
    root.password = ""
    root.passwordVisible = false
    root.passwordError = ""
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omarchy.wifiqr")
    else close()
  }

  function generate(requestedIface) {
    if (qrProc.running) {
      pendingShow = true
      pendingIface = requestedIface
      if (!expectedStop) {
        expectedStop = true
        qrProc.running = false
      }
      return
    }
    qrSize = 0
    qrRows = []
    error = ""
    loading = true
    expectedStop = false
    iface = ""
    secured = false
    password = ""
    passwordVisible = false
    passwordError = ""
    if (pwProc.running) {
      pwExpectedStop = true
      pwProc.running = false
    }
    qrProc.command = requestedIface
      ? ["omarchy-network-qr", "--meta", requestedIface]
      : ["omarchy-network-qr", "--meta"]
    qrProc.running = true
  }

  function updateQr(raw) {
    var parsed = Model.parseQrOutput(raw)
    qrRows = parsed.matrix.rows
    qrSize = parsed.matrix.size
    if (parsed.meta.ssid !== "") ssid = parsed.meta.ssid
    if (parsed.meta.iface !== "") iface = parsed.meta.iface
    secured = parsed.meta.security !== "" && parsed.meta.security !== "nopass"
    if (qrSize > 0) error = ""
  }

  function togglePassword() {
    if (passwordVisible) { passwordVisible = false; return }
    if (password !== "") { passwordVisible = true; return }
    if (pwProc.running || !iface) return
    passwordError = ""
    pwExpectedStop = false
    pwProc.command = ["omarchy-network-password", iface]
    pwProc.running = true
  }

  Process {
    id: qrProc
    property string stdoutBuf: ""
    property string stderrBuf: ""
    property int maxStdout: 65536
    property int maxStderr: 4096
    property bool overflowed: false
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (qrProc.overflowed) return
        qrProc.stdoutBuf += chunk
        if (qrProc.stdoutBuf.length > qrProc.maxStdout) {
          qrProc.overflowed = true
          qrProc.stdoutBuf = ""
          qrProc.stderrBuf = ""
          qrProc.signal(15)
          qrKillTimer.start()
        }
      }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (qrProc.overflowed) return
        qrProc.stderrBuf += chunk
        if (qrProc.stderrBuf.length > qrProc.maxStderr) {
          qrProc.overflowed = true
          qrProc.stdoutBuf = ""
          qrProc.stderrBuf = ""
          qrProc.signal(15)
          qrKillTimer.start()
        }
      }
    }
    onStarted: {
      qrKillTimer.stop()
      stdoutBuf = ""
      stderrBuf = ""
      overflowed = false
    }
    onExited: function(exitCode) {
      qrKillTimer.stop()
      var out = overflowed ? "" : stdoutBuf
      var err = overflowed ? "" : String(stderrBuf || "").trim()
      stdoutBuf = ""
      stderrBuf = ""
      overflowed = false
      if (!root.expectedStop) {
        if (out) root.updateQr(out)
        if (err) root.error = Util.plain(err, 240)
      }
      root.loading = false
      if (root.pendingShow) {
        root.pendingShow = false
        Qt.callLater(function() { root.generate(root.pendingIface) })
        return
      }
      if (root.expectedStop) return
      if (exitCode !== 0 || root.qrSize === 0) {
        root.qrSize = 0
        root.qrRows = []
        if (root.error === "") root.error = "Could not generate the Wi-Fi QR code"
      }
    }
  }

  Timer {
    id: qrKillTimer
    interval: 2000
    onTriggered: qrProc.signal(9)
  }

  Process {
    id: pwProc
    property string stdoutBuf: ""
    property int maxStdout: 4096
    property bool overflowed: false
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (pwProc.overflowed) return
        pwProc.stdoutBuf += chunk
        if (pwProc.stdoutBuf.length > pwProc.maxStdout) {
          pwProc.overflowed = true
          pwProc.stdoutBuf = ""
          pwProc.signal(15)
          pwKillTimer.start()
        }
      }
    }
    onStarted: {
      pwKillTimer.stop()
      stdoutBuf = ""
      overflowed = false
    }
    onExited: function(exitCode) {
      pwKillTimer.stop()
      var raw = overflowed ? "" : String(stdoutBuf || "").trim()
      stdoutBuf = ""
      overflowed = false
      if (root.pwExpectedStop) return
      if (!root.opened) return
      // Cap before assign; never log the secret.
      if (exitCode === 0 && raw !== "") {
        root.password = raw.length > 4096 ? raw.slice(0, 4096) : raw
        root.passwordVisible = true
      } else {
        root.passwordError = "Could not read the Wi-Fi password"
      }
    }
  }

  Timer {
    id: pwKillTimer
    interval: 2000
    onTriggered: pwProc.signal(9)
  }

  CenteredModal {
    id: modal
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: Style.space(320)
    contentHeight: Math.round(content.implicitHeight)
    onDismissed: root.dismiss()

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismiss()

      ColumnLayout {
        id: content
        anchors.centerIn: parent
        width: parent.width
        spacing: Style.space(14)

        Text {
          textFormat: Text.PlainText
          text: (root.ssid ? Util.plain(root.ssid) : "Wi-Fi").toUpperCase()
          color: Qt.darker(Color.popups.text, 1.0)
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 2
          elide: Text.ElideRight
          Layout.maximumWidth: parent.width
          Layout.alignment: Qt.AlignHCenter
          horizontalAlignment: Text.AlignHCenter
        }

        Rectangle {
          id: qrCanvas
          readonly property int moduleSize: root.qrSize > 0
            ? Math.max(3, Math.floor(Style.space(220) / root.qrSize))
            : 0
          visible: root.showingQr
          width: root.qrSize * moduleSize
          height: width
          color: "white"
          radius: Style.cornerRadius
          Layout.alignment: Qt.AlignHCenter

          Grid {
            anchors.fill: parent
            columns: root.qrSize
            Repeater {
              model: root.qrSize * root.qrSize
              Rectangle {
                required property int index
                readonly property int matrixRow: Math.floor(index / root.qrSize)
                readonly property int matrixColumn: index % root.qrSize
                width: qrCanvas.moduleSize
                height: qrCanvas.moduleSize
                color: root.qrRows[matrixRow].charAt(matrixColumn) === "1" ? "#111111" : "transparent"
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.loading
          text: "Generating QR code…"
          color: Color.popups.text
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          textFormat: Text.PlainText
          visible: root.error !== ""
          text: Util.plain(root.error, 240)
          color: Color.error !== undefined ? Color.error : "#ff6b6b"
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          textFormat: Text.PlainText
          visible: root.showingQr
          text: "Scan to join this network"
          color: Color.popups.text
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          textFormat: Text.PlainText
          visible: root.showingQr && root.secured
          text: root.passwordError !== "" ? root.passwordError
            : root.passwordVisible ? root.password
            : "Show password"
          color: root.passwordError !== "" ? (Color.error !== undefined ? Color.error : "#ff6b6b") : Color.popups.text
          opacity: root.passwordVisible || root.passwordError !== "" ? 1 : 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WrapAnywhere
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.togglePassword()
          }
        }
      }
    }
  }
}
