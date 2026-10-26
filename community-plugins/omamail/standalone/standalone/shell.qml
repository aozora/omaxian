import QtQuick
import Quickshell
import Quickshell.Io
import "ui" as Omamail

// Standalone host for the Omamail plugin UI: no omarchy-shell, no bar.
// Plugin mode (Service.platform stays unset), so the plugin's own scripts keep
// handling credentials, notifications, clipboard and attachments.
ShellRoot {
  id: host

  property var manifest: ({ id: "omamail", name: "Omamail", version: "0.0.0" })

  FileView {
    path: Quickshell.shellDir + "/manifest.json"
    blockLoading: true
    onLoaded: {
      try { host.manifest = JSON.parse(text()) } catch (e) {}
    }
  }

  // The plugin calls these on the object the shell would normally inject.
  QtObject {
    id: hostApi
    function summon(id, payload) { app.open(payload); return true }
    function toggle(id, payload) { app.open(payload); return true }
    function hide(id) { Qt.quit() }
    function quit() { Qt.quit() }
  }

  // `omamail-app mailto:...` / `--open` reach a running instance through here.
  IpcHandler {
    target: "omamail"
    function summon(payload: string): void { app.open(payload) }
  }

  Omamail.Service { id: svc; shell: hostApi; manifest: host.manifest }
  Omamail.App {
    id: app
    shell: hostApi
    manifest: host.manifest
    service: svc
    standaloneWindowChrome: false
    Component.onCompleted: Qt.callLater(function() {
      app.open(Quickshell.env("OMAMAIL_PAYLOAD") || "{}")
    })
  }
}
