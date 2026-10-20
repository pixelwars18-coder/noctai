import QtQuick

Text {
    property string name: "file"
    property real size: 18
    text: Theme.glyph(name)
    font.family: Theme.iconFont
    font.pixelSize: size
    color: Theme.mOnSurface
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    Accessible.ignored: true
}
