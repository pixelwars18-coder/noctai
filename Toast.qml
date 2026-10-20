import QtQuick

// Bottom-centered transient message.
Rectangle {
    id: t
    property string text
    property bool error: false
    function show(msg, err) { text = msg; error = err; shown = true; timer.restart() }
    property bool shown: false

    anchors.horizontalCenter: parent.horizontalCenter
    y: shown ? parent.height - height - 24 : parent.height + 10
    width: Math.min(label.implicitWidth + 58, parent.width - 80)
    height: 42
    radius: 21
    color: Theme.mSurfaceVariant
    border.color: error ? Theme.mError : Theme.mOutline
    opacity: shown ? 1 : 0
    Behavior on y { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutBack } }
    Behavior on opacity { NumberAnimation { duration: Theme.normal } }
    Timer { id: timer; interval: t.error ? 6000 : 3200; onTriggered: t.shown = false }
    Icon {
        id: ico
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        name: t.error ? "alert-triangle" : "circle-check"
        size: 17
        color: t.error ? Theme.mError : Theme.mTertiary
    }
    Text {
        id: label
        anchors.left: ico.right
        anchors.leftMargin: 9
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: t.text
        elide: Text.ElideRight
        color: Theme.mOnSurface
        font.family: Theme.font
        font.pixelSize: 13
    }
    MouseArea { anchors.fill: parent; onClicked: t.shown = false }
}
