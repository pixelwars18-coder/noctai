import QtQuick

// Filled (primary) or tonal pill button with optional icon and an inline progress fill.
Rectangle {
    id: btn
    property string text
    property string icon
    property bool filled: true
    property bool danger: false
    property real progress: -1          // 0..1 draws a fill behind the label
    property real size: 38
    signal clicked

    readonly property color base: danger ? Theme.mError : filled ? Theme.mPrimary : Theme.alpha(Theme.mOnSurface, 0.08)
    readonly property color ink: danger || filled ? (danger ? Theme.mSurface : Theme.mOnPrimary) : Theme.mOnSurface

    implicitHeight: size
    implicitWidth: row.implicitWidth + size * 0.9
    radius: height / 2
    color: progress >= 0 ? Theme.alpha(base, 0.35) : area.containsMouse ? Qt.lighter(base, filled ? 1.08 : 1.6) : base
    opacity: enabled ? 1 : 0.4
    scale: area.pressed ? 0.96 : 1
    clip: true
    Accessible.role: Accessible.Button
    Accessible.name: text
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }

    Rectangle {
        visible: btn.progress >= 0
        width: parent.width * Math.max(0, Math.min(1, btn.progress))
        height: parent.height
        radius: parent.radius
        color: btn.base
        Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Icon {
            visible: btn.icon !== ""
            name: btn.icon
            size: btn.size * 0.46
            color: btn.ink
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: btn.text
            color: btn.ink
            font.family: Theme.font
            font.pixelSize: btn.size * 0.36
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
