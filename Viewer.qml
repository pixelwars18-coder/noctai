import QtQuick
import QtQuick.Layouts
import QtMultimedia

// Full-window lightbox for images and videos. ←/→ to browse, Esc to close.
Rectangle {
    id: v
    property var items: []
    property int index: 0
    property string kind: "tti"
    readonly property var item: items[index] || null
    readonly property bool isVideo: kind === "ttv"
    signal reuse(string prompt)
    signal deleted

    function show(list, i, k) { items = list; index = i; kind = k; visible = true; forceActiveFocus() }
    function close() { player.stop(); visible = false }

    visible: false
    color: Theme.alpha(Theme.mSurface, 0.94)
    focus: visible
    opacity: visible ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
    Keys.onEscapePressed: close()
    Keys.onLeftPressed: if (index > 0) index--
    Keys.onRightPressed: if (index < items.length - 1) index++
    MouseArea { anchors.fill: parent; onClicked: v.close(); onWheel: {} }

    Image {
        id: img
        visible: !v.isVideo
        anchors.fill: parent
        anchors.margins: 28
        anchors.bottomMargin: 110
        source: v.item && !v.isVideo ? "file://" + v.item.path : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        mipmap: true
    }
    MediaPlayer {
        id: player
        source: v.visible && v.item && v.isVideo ? "file://" + v.item.path : ""
        videoOutput: out
        audioOutput: AudioOutput {}
        loops: MediaPlayer.Infinite
        onSourceChanged: if (source != "") play()
    }
    VideoOutput {
        id: out
        visible: v.isVideo
        anchors.fill: img
        fillMode: VideoOutput.PreserveAspectFit
    }

    IconButton {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: img.verticalCenter
        visible: v.index > 0
        icon: "chevron-left"
        size: 44
        onClicked: v.index--
    }
    IconButton {
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: img.verticalCenter
        visible: v.index < v.items.length - 1
        icon: "chevron-right"
        size: 44
        onClicked: v.index++
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 18
        height: 76
        radius: Theme.radiusL
        color: Theme.card
        border.color: Theme.mOutline
        MouseArea { anchors.fill: parent }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 12
            spacing: 6
            Column {
                Layout.fillWidth: true
                spacing: 3
                Text {
                    width: parent.width
                    text: v.item ? v.item.prompt : ""
                    elide: Text.ElideRight
                    color: Theme.mOnSurface
                    font.family: Theme.font
                    font.pixelSize: 14
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: v.item ? [v.item.model, v.item.seed !== undefined && v.item.seed !== null && v.item.seed >= 0 ? "seed " + v.item.seed : "",
                                    v.item.seconds ? v.item.seconds + " s" : "", (v.index + 1) + " / " + v.items.length].filter(x => x).join("  ·  ") : ""
                    color: Theme.mOnSurfaceVariant
                    font.family: Theme.font
                    font.pixelSize: 11
                }
            }
            IconButton { icon: "pencil"; tip: "Reuse prompt"; onClicked: { v.reuse(v.item.prompt); v.close() } }
            IconButton { icon: "external-link"; tip: "Open"; onClicked: Api.openPath(v.item.path) }
            IconButton {
                icon: "trash"; tip: "Delete"
                onClicked: {
                    const p = v.item.path
                    player.stop()
                    Api.post("/outputs/delete", { path: p }, () => {
                        const rest = v.items.filter(x => x.path !== p)
                        v.items = rest
                        if (!rest.length) v.close()
                        else v.index = Math.min(v.index, rest.length - 1)
                        v.deleted()
                    })
                }
            }
            IconButton { icon: "x"; tip: "Close (Esc)"; onClicked: v.close() }
        }
    }
}
