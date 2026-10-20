import QtQuick

// Centered icon + title + hint + optional action.
Column {
    id: es
    property string icon: "sparkles"
    property string title
    property string hint
    property string action
    property string actionIcon
    signal triggered

    spacing: 10
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 76
        height: 76
        radius: 38
        color: Theme.alpha(Theme.mPrimary, 0.12)
        Icon {
            anchors.centerIn: parent
            name: es.icon
            size: 36
            color: Theme.mPrimary
        }
    }
    Item { width: 1; height: 4 }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: es.title
        color: Theme.mOnSurface
        font.family: Theme.font
        font.pixelSize: 18
        font.weight: Font.DemiBold
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(implicitWidth, 420)
        visible: es.hint !== ""
        text: es.hint
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        color: Theme.mOnSurfaceVariant
        font.family: Theme.font
        font.pixelSize: 13
    }
    Item { width: 1; height: 4; visible: es.action !== "" }
    PillButton {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: es.action !== ""
        text: es.action
        icon: es.actionIcon
        onClicked: es.triggered()
    }
}
