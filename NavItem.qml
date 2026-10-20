import QtQuick

// Navigation rail entry: icon in a pill that fills when active, label underneath.
Item {
    id: nav
    property string icon
    property string label
    property bool active: false
    property int badge: 0
    signal clicked

    implicitWidth: 64
    implicitHeight: 58
    Accessible.role: Accessible.PageTab
    Accessible.name: label

    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        y: 4
        width: nav.active ? 54 : area.containsMouse ? 46 : 40
        height: 32
        radius: 16
        color: nav.active ? Theme.mPrimary : area.containsMouse ? Theme.hover : "transparent"
        Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        Icon {
            anchors.centerIn: parent
            name: nav.icon
            size: 19
            color: nav.active ? Theme.mOnPrimary : Theme.mOnSurfaceVariant
        }
        Rectangle {
            visible: nav.badge > 0
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: -3
            width: Math.max(17, badgeText.implicitWidth + 8)
            height: 17
            radius: 9
            color: Theme.mTertiary
            border.color: Theme.mSurface
            border.width: 2
            Text {
                id: badgeText
                anchors.centerIn: parent
                text: nav.badge
                color: Theme.mSurface
                font.family: Theme.font
                font.pixelSize: 9
                font.weight: Font.Bold
            }
        }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: pill.bottom
        anchors.topMargin: 4
        text: nav.label
        color: nav.active ? Theme.mOnSurface : Theme.mOnSurfaceVariant
        font.family: Theme.font
        font.pixelSize: 11
        font.weight: nav.active ? Font.DemiBold : Font.Normal
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: nav.clicked()
    }
}
