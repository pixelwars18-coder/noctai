import QtQuick

// Round icon button with hover tint, press squish and an optional "active" pill.
Rectangle {
    id: btn
    property string icon
    property string tip
    property bool active: false
    property real size: 34
    signal clicked

    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    color: active ? Theme.mPrimary : area.containsMouse ? Theme.hover : "transparent"
    opacity: enabled ? 1 : 0.35
    scale: area.pressed ? 0.88 : 1
    activeFocusOnTab: false
    Accessible.role: Accessible.Button
    Accessible.name: tip
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }

    Icon {
        anchors.centerIn: parent
        name: btn.icon
        size: btn.size * 0.53
        color: btn.active ? Theme.mOnPrimary : Theme.mOnSurface
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
    ToolTipLite { text: btn.tip; shown: area.containsMouse && btn.tip !== "" }
}
