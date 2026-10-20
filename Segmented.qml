import QtQuick

// Segmented button group with a sliding highlight. `items` is [{value, text, icon?}].
Rectangle {
    id: seg
    property var items: []
    property var value
    signal picked(var value)

    readonly property int index: Math.max(0, items.findIndex(i => i.value === value))
    implicitHeight: 38
    implicitWidth: row.implicitWidth + 8
    radius: height / 2
    color: Theme.field
    border.color: Theme.alpha(Theme.mOutline, 0.8)

    Rectangle {
        readonly property Item target: rep.count > seg.index ? rep.itemAt(seg.index) : null
        x: target ? row.x + target.x : 4
        width: target ? target.width : 0
        y: 4
        height: parent.height - 8
        radius: height / 2
        color: Theme.mPrimary
        Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
    }
    Row {
        id: row
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
            id: rep
            model: seg.items
            delegate: Item {
                required property var modelData
                required property int index
                readonly property bool on: index === seg.index
                width: content.implicitWidth + 28
                height: seg.height - 8
                Row {
                    id: content
                    anchors.centerIn: parent
                    spacing: 6
                    Icon {
                        visible: !!modelData.icon
                        name: modelData.icon || ""
                        size: 15
                        color: on ? Theme.mOnPrimary : Theme.mOnSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: modelData.text
                        color: on ? Theme.mOnPrimary : Theme.mOnSurface
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: on ? Font.DemiBold : Font.Normal
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { seg.value = modelData.value; seg.picked(modelData.value) }
                }
            }
        }
    }
}
