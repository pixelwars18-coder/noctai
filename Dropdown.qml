import QtQuick
import QtQuick.Controls

// Pill selector with a themed popup list. `options` is [{value, text, sub?}].
Rectangle {
    id: dd
    property var options: []
    property var value
    property string placeholder: "Select"
    property string icon
    signal picked(var value)

    readonly property var current: options.find(o => o.value === value)
    implicitHeight: 38
    implicitWidth: Math.min(340, Math.max(160, label.implicitWidth + 70))
    radius: height / 2
    color: area.containsMouse || pop.visible ? Theme.alpha(Theme.mOnSurface, 0.1) : Theme.field
    border.width: 1
    border.color: pop.visible ? Theme.selectedBorder : Theme.alpha(Theme.mOutline, 0.8)
    Behavior on color { ColorAnimation { duration: Theme.fast } }

    Icon {
        id: ico
        visible: dd.icon !== ""
        name: dd.icon
        size: 16
        color: Theme.mPrimary
        anchors.left: parent.left
        anchors.leftMargin: 13
        anchors.verticalCenter: parent.verticalCenter
    }
    Text {
        id: label
        anchors.left: ico.visible ? ico.right : parent.left
        anchors.leftMargin: ico.visible ? 8 : 15
        anchors.right: chev.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: dd.current ? dd.current.text : dd.placeholder
        color: dd.current ? Theme.mOnSurface : Theme.mOnSurfaceVariant
        elide: Text.ElideRight
        font.family: Theme.font
        font.pixelSize: 13
        font.weight: Font.Medium
    }
    Icon {
        id: chev
        name: "chevron-down"
        size: 15
        color: Theme.mOnSurfaceVariant
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        rotation: pop.visible ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (dd.options.length) pop.open()
    }

    Popup {
        id: pop
        y: dd.height + 6
        width: Math.max(dd.width, 240)
        height: Math.min(list.contentHeight + 12, 360)
        padding: 6
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.fast }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }
        }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.fast } }
        background: Rectangle {
            radius: Theme.radiusM
            color: Theme.mSurfaceVariant
            border.color: Theme.mOutline
        }
        contentItem: ListView {
            id: list
            clip: true
            model: dd.options
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            delegate: Rectangle {
                required property var modelData
                width: list.width
                height: modelData.sub ? 46 : 36
                radius: Theme.radiusS
                color: modelData.value === dd.value ? Theme.selected : ma.containsMouse ? Theme.hover : "transparent"
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.right: tick.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        width: parent.width
                        text: modelData.text
                        color: Theme.mOnSurface
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 13
                    }
                    Text {
                        visible: !!modelData.sub
                        width: parent.width
                        text: modelData.sub || ""
                        color: Theme.mOnSurfaceVariant
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                }
                Icon {
                    id: tick
                    name: "check"
                    size: 15
                    color: Theme.mPrimary
                    opacity: modelData.value === dd.value ? 1 : 0
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { dd.value = modelData.value; dd.picked(modelData.value); pop.close() }
                }
            }
        }
    }
}
