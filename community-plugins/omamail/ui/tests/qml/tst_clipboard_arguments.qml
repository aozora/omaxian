import QtQuick
import QtTest
import Quickshell
import "../.." as Omamail

Item {
  Component { id: factory; Omamail.Service {} }
  TestCase {
    name: "ClipboardArguments"
    function init() { Quickshell.detachedCommands = [] }

    // Omaxian: copyText uses a Qt TextEdit clipboard proxy (no external CLI).
    // Option-looking sender text must still copy without spawning a process.
    function test_sender_text_uses_qt_clipboard_without_process() {
      var service = createTemporaryObject(factory, parent)
      verify(service)
      var values = ["--version", "--clear", "-p", "--type=text/html",
        "田中 \"quoted\" \\ body\nline two", "", "trailing\r\n"]
      for (var i = 0; i < values.length; i++) {
        verify(service.copyText(values[i]))
        compare(Quickshell.detachedCommands, [])
      }
    }

    function test_nul_is_refused_before_any_process_starts() {
      var service = createTemporaryObject(factory, parent)
      verify(service)
      verify(!service.copyText("--clear\0text"))
      compare(Quickshell.detachedCommands, [])
    }

    function test_native_clipboard_receives_text_without_process_arguments() {
      var service = createTemporaryObject(factory, parent)
      verify(service)
      var copied = []
      service.platform = {setClipboard: function(text) { copied.push(text); return true }}
      verify(service.copyText("--clear"))
      compare(copied, ["--clear"])
      compare(Quickshell.detachedCommands, [])
    }
  }
}
