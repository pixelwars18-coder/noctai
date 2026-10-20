import QtQuick

// Tiny delayed tooltip drawn under its parent; costs nothing until shown.
Loader {
    id: tip
    property string text
    property bool shown: false
    active: false
    z: 100
    anchors.top: parent.bottom
    anchors.topMargin: 6
    anchors.horizontalCenter: parent.horizontalCenter
    Timer { running: tip.shown; interval: 550; onTriggered: tip.active = true }
    onShownChanged: if (!shown) active = false
    sourceComponent: Rectangle {
        implicitWidth: label.implicitWidth + 16
        implicitHeight: label.implicitHeight + 8
        radius: height / 2
        color: Theme.mSurfaceVariant
        border.color: Theme.mOutline
        opacity: 0
        scale: 0.9
        Component.onCompleted: { opacity = 1; scale = 1 }
        Behavior on opacity { OpacityAnimator { duration: Theme.fast } }
        Behavior on scale { ScaleAnimator { duration: Theme.normal; easing.type: Easing.OutBack } }
        Text {
            id: label
            anchors.centerIn: parent
            text: tip.text
            color: Theme.mOnSurface
            font.family: Theme.font
            font.pixelSize: 11
        }
    }
}
