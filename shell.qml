//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
// Noctai: a Noctalia-styled local AI studio for Quickshell.
// Chat (Ollama), text-to-image, text-to-video, text-to-speech and text-to-audio, plus a
// Hugging Face / Ollama model browser. Run:  ./noctai   (a second launch just raises the window)
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    IpcHandler {
        target: "noctai"
        function show(): void { win.visible = true }
        function page(name: string): void {
            const i = ["chat", "image", "video", "speech", "audio", "models", "downloads"].indexOf(name)
            if (i >= 0) view.go(i)
            win.visible = true
        }
        // Renders the window to a PNG (handy for bug reports): noctai-ipc snapshot /tmp/x.png
        function snapshot(path: string): void { view.grabToImage(r => r.saveToFile(path)) }
    }

    FloatingWindow {
        id: win
        title: "Noctai"
        implicitWidth: 1240
        implicitHeight: 800
        minimumSize: Qt.size(900, 600)
        color: "transparent"
        onVisibleChanged: if (!visible) Qt.quit()

        AppView {
            id: view
            anchors.fill: parent
        }
    }
}
