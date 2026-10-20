import QtQuick

// Small rounded label, optionally clickable.
Rectangle {
    id: chip
    property string text
    property string icon
    property color tint: Theme.mOnSurfaceVariant
    property bool clickable: false
    property bool strong: false
    signal clicked

    implicitHeight: 24
    implicitWidth: row.implicitWidth + 18
    radius: height / 2
    color: strong ? tint : Theme.alpha(tint, area.containsMouse ? 0.24 : 0.14)
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Icon {
            visible: chip.icon !== ""
            name: chip.icon
            size: 13
            color: chip.strong ? Theme.mSurface : chip.tint
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: chip.text
            color: chip.strong ? Theme.mSurface : chip.tint
            font.family: Theme.font
            font.pixelSize: 11
            font.weight: Font.DemiBold
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        enabled: chip.clickable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.clicked()
    }
}
