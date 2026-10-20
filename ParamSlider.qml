import QtQuick
import QtQuick.Controls

// Labelled slider: "Steps ........ 25". Scroll wheel and drag both work.
Item {
    id: ps
    property string label
    property real value
    property real from: 0
    property real to: 100
    property real step: 1
    property int decimals: 0
    property string suffix
    signal moved(real value)

    implicitHeight: 46
    implicitWidth: 260

    Text {
        anchors.left: parent.left
        anchors.top: parent.top
        text: ps.label
        color: Theme.mOnSurfaceVariant
        font.family: Theme.font
        font.pixelSize: 12
    }
    Text {
        anchors.right: parent.right
        anchors.top: parent.top
        text: Number(ps.value).toFixed(ps.decimals) + ps.suffix
        color: Theme.mOnSurface
        font.family: Theme.font
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }
    Slider {
        id: s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 24
        from: ps.from
        to: ps.to
        stepSize: ps.step
        snapMode: Slider.SnapAlways
        value: ps.value
        onMoved: ps.moved(value)
        background: Rectangle {
            x: s.leftPadding
            y: s.topPadding + s.availableHeight / 2 - height / 2
            width: s.availableWidth
            height: 6
            radius: 3
            color: Theme.alpha(Theme.mOnSurface, 0.1)
            Rectangle {
                width: s.visualPosition * parent.width
                height: parent.height
                radius: 3
                color: Theme.mPrimary
            }
        }
        handle: Rectangle {
            x: s.leftPadding + s.visualPosition * (s.availableWidth - width)
            y: s.topPadding + s.availableHeight / 2 - height / 2
            width: s.pressed ? 20 : 16
            height: width
            radius: width / 2
            color: Theme.mPrimary
            border.color: Theme.mSurface
            border.width: 3
            Behavior on width { NumberAnimation { duration: Theme.fast } }
        }
    }
}
