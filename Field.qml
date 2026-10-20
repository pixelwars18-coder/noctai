import QtQuick
import QtQuick.Controls

// Rounded text input; multi-line when `multiline` (Enter submits, Shift+Enter breaks a line).
Rectangle {
    id: f
    property alias text: edit.text
    property string placeholder
    property string icon
    property bool multiline: false
    property int minLines: 1
    property int maxLines: 8
    property alias input: edit
    signal submitted

    readonly property real lineH: edit.font.pixelSize * 1.45
    implicitHeight: multiline ? Math.min(maxLines * lineH, Math.max(minLines * lineH, edit.contentHeight)) + 22 : 40
    radius: multiline ? Theme.radiusM : height / 2
    color: Theme.field
    border.width: 1
    border.color: edit.activeFocus ? Theme.selectedBorder : Theme.alpha(Theme.mOutline, 0.8)
    Behavior on border.color { ColorAnimation { duration: Theme.fast } }

    Icon {
        id: ico
        visible: f.icon !== ""
        name: f.icon
        size: 17
        color: Theme.mOnSurfaceVariant
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: f.multiline ? undefined : parent.verticalCenter
        anchors.top: f.multiline ? parent.top : undefined
        anchors.topMargin: 12
    }
    ScrollView {
        id: sv
        anchors.fill: parent
        anchors.leftMargin: ico.visible ? 38 : 14
        anchors.rightMargin: 10
        anchors.topMargin: f.multiline ? 11 : 0
        anchors.bottomMargin: f.multiline ? 11 : 0
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        TextArea {
            id: edit
            wrapMode: f.multiline ? TextEdit.Wrap : TextEdit.NoWrap
            verticalAlignment: f.multiline ? TextEdit.AlignTop : TextEdit.AlignVCenter
            topPadding: 0; bottomPadding: 0; leftPadding: 0; rightPadding: 0
            color: Theme.mOnSurface
            selectionColor: Theme.alpha(Theme.mPrimary, 0.4)
            selectedTextColor: Theme.mOnSurface
            placeholderText: f.placeholder
            placeholderTextColor: Theme.alpha(Theme.mOnSurfaceVariant, 0.8)
            font.family: Theme.font
            font.pixelSize: 14
            background: null
            height: f.multiline ? undefined : sv.height
            Keys.onReturnPressed: ev => {
                if (f.multiline && (ev.modifiers & Qt.ShiftModifier)) { ev.accepted = false; return }
                f.submitted()
            }
            Keys.onEnterPressed: ev => f.submitted()
        }
    }
}
