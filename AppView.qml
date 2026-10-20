import QtQuick
import QtQuick.Layouts
import Quickshell

// Window content: navigation rail + pages + overlays.
Rectangle {
    id: app
    color: Theme.mSurface
    radius: Theme.radiusL
    border.color: Theme.alpha(Theme.mOutline, 0.7)
    clip: true

    // 0 chat · 1..4 generators · 5 models · 6 downloads
    property int pageIndex: 0
    readonly property var genKinds: ["tti", "ttv", "tts", "tta"]

    function browse(kind) { models.setKind(kind); pageIndex = 5 }
    function go(i) { pageIndex = i }

    Connections {
        target: Api
        function onToast(text, error) { toast.show(text, error) }
    }

    Shortcut { sequences: ["Ctrl+1"]; onActivated: app.go(0) }
    Shortcut { sequences: ["Ctrl+2"]; onActivated: app.go(1) }
    Shortcut { sequences: ["Ctrl+3"]; onActivated: app.go(2) }
    Shortcut { sequences: ["Ctrl+4"]; onActivated: app.go(3) }
    Shortcut { sequences: ["Ctrl+5"]; onActivated: app.go(4) }
    Shortcut { sequences: ["Ctrl+M"]; onActivated: app.go(5) }
    Shortcut { sequences: ["Ctrl+J"]; onActivated: app.go(6) }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---------------------------------------------------------- rail
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 84
            color: Theme.alpha(Theme.mSurfaceVariant, 0.6)

            Column {
                anchors.top: parent.top
                anchors.topMargin: 18
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 44; height: 44; radius: 14
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.mPrimary }
                        GradientStop { position: 1; color: Theme.mTertiary }
                    }
                    Icon { anchors.centerIn: parent; name: "sparkles"; size: 24; color: Theme.mOnPrimary }
                }
                Item { width: 1; height: 12 }
                Repeater {
                    model: Theme.kinds
                    delegate: NavItem {
                        required property var modelData
                        required property int index
                        icon: modelData.icon
                        label: modelData.label
                        active: app.pageIndex === index
                        badge: index > 0 ? Api.jobs.filter(j => j.kind === modelData.key && ["queued", "loading", "running"].includes(j.status)).length : 0
                        onClicked: app.go(index)
                    }
                }
                Rectangle { width: 36; height: 1; color: Theme.mOutline; anchors.horizontalCenter: parent.horizontalCenter }
                NavItem { icon: "packages"; label: "Models"; active: app.pageIndex === 5; onClicked: app.go(5) }
                NavItem { icon: "cloud-download"; label: "Downloads"; active: app.pageIndex === 6; badge: Api.activeDownloads; onClicked: app.go(6) }
            }

            // VRAM gauge; click frees GPU memory (unloads diffusion pipeline + Ollama models).
            Item {
                id: gauge
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
                width: 64
                height: 74
                readonly property real frac: Api.gpu ? Api.gpu.used / Api.gpu.total : 0
                Canvas {
                    id: ring
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 46; height: 46
                    property real frac: gauge.frac
                    property color fg: gauge.frac > 0.85 ? Theme.mError : Theme.mPrimary
                    property color bg: Theme.alpha(Theme.mOnSurface, 0.1)
                    onFracChanged: requestPaint()
                    onFgChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d")
                        c.reset()
                        c.lineWidth = 4.5
                        c.lineCap = "round"
                        c.strokeStyle = bg
                        c.beginPath(); c.arc(23, 23, 19, 0, Math.PI * 2); c.stroke()
                        c.strokeStyle = fg
                        c.beginPath(); c.arc(23, 23, 19, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac); c.stroke()
                    }
                    Icon { anchors.centerIn: parent; name: "cpu"; size: 17; color: Api.online ? Theme.mOnSurface : Theme.mError }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: ring.bottom
                    anchors.topMargin: 5
                    text: !Api.online ? (Api.starting ? "starting" : "offline") : Api.gpu ? (Api.gpu.used / 1024).toFixed(1) + "/" + Math.round(Api.gpu.total / 1024) + "G" : "CPU"
                    color: Theme.mOnSurfaceVariant
                    font.family: Theme.font
                    font.pixelSize: 10
                }
                MouseArea {
                    id: gma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Api.post("/unload", {}, () => { Api.toast("Freed GPU memory", false); Api.poll() })
                }
                ToolTipLite {
                    anchors.top: undefined
                    anchors.bottom: parent.top
                    anchors.bottomMargin: 6
                    anchors.horizontalCenter: undefined
                    anchors.left: parent.left
                    text: (Api.gpu ? Api.gpu.name + " · " : "") + (Api.loaded ? "loaded: " + Api.loaded.split("/").pop() + " · " : "") + "click to free VRAM"
                    shown: gma.containsMouse
                }
            }
        }

        // ---------------------------------------------------------- pages
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ChatPage {
                anchors.fill: parent
                visible: app.pageIndex === 0
                onBrowse: k => app.browse(k)
            }
            Repeater {
                model: app.genKinds
                delegate: GenPage {
                    id: gp
                    required property string modelData
                    required property int index
                    anchors.fill: parent
                    kind: modelData
                    visible: app.pageIndex === index + 1
                    onBrowse: k => app.browse(k)
                    onView: (items, i) => viewer.show(items, i, gp.kind)
                    Connections {
                        target: viewer
                        enabled: gp.visible
                        function onReuse(p) { gp.reusePrompt(p) }
                        function onDeleted() { gp.reload() }
                    }
                }
            }
            ModelsPage {
                id: models
                anchors.fill: parent
                visible: app.pageIndex === 5
            }
            DownloadsPage {
                anchors.fill: parent
                visible: app.pageIndex === 6
            }

            // Backend failed to come up: show why.
            Rectangle {
                anchors.fill: parent
                visible: !Api.online && !Api.starting && Api.logTail !== ""
                color: Theme.alpha(Theme.mSurface, 0.96)
                Column {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 80, 760)
                    spacing: 12
                    EmptyState {
                        anchors.horizontalCenter: parent.horizontalCenter
                        icon: "plug-connected-x"
                        title: "The backend isn't running"
                        hint: "Noctai starts server.py from " + Api.home + ". Its last output:"
                        action: "Retry"
                        actionIcon: "refresh"
                        onTriggered: { Api.logTail = ""; Api.startBackend() }
                    }
                    Rectangle {
                        width: parent.width
                        height: Math.min(260, logText.implicitHeight + 24)
                        radius: Theme.radiusM
                        color: Theme.card
                        clip: true
                        Text {
                            id: logText
                            anchors.fill: parent
                            anchors.margins: 12
                            text: Api.logTail
                            wrapMode: Text.WrapAnywhere
                            color: Theme.mOnSurfaceVariant
                            font.family: Theme.mono
                            font.pixelSize: 11
                            verticalAlignment: Text.AlignBottom
                        }
                    }
                }
            }
        }
    }

    Viewer { id: viewer; anchors.fill: parent }
    Toast { id: toast }
}
