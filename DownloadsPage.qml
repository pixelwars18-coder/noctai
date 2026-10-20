import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Live view of model downloads (Hugging Face snapshots and Ollama pulls).
Item {
    id: page

    // Rolling speed estimate per download id.
    property var speeds: ({})
    property var last: ({})
    Connections {
        target: Api
        function onDownloadsChanged() {
            const now = Date.now(), s = Object.assign({}, page.speeds), l = {}
            for (const d of Api.downloads) {
                const p = page.last[d.id]
                if (p && now > p.t) s[d.id] = 0.7 * (s[d.id] || 0) + 0.3 * Math.max(0, (d.done - p.done) / ((now - p.t) / 1000))
                l[d.id] = { t: now, done: d.done }
            }
            page.speeds = s
            page.last = l
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 22
            Column {
                Layout.fillWidth: true
                Text {
                    text: "Downloads"
                    color: Theme.mOnSurface
                    font.family: Theme.font
                    font.pixelSize: 24
                    font.weight: Font.Bold
                }
                Text {
                    text: Api.activeDownloads ? Api.activeDownloads + " in progress" : "Nothing downloading"
                    color: Theme.mOnSurfaceVariant
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
            PillButton {
                visible: Api.downloads.length > Api.activeDownloads
                text: "Clear finished"
                icon: "clear-all"
                filled: false
                size: 34
                onClicked: Api.post("/download/clear", {}, () => Api.poll())
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            EmptyState {
                anchors.centerIn: parent
                visible: Api.downloads.length === 0
                icon: "cloud-download"
                title: "No downloads"
                hint: "Models you download from the Models page show up here."
            }
            ListView {
                id: list
                anchors.fill: parent
                anchors.leftMargin: 22
                anchors.rightMargin: 12
                spacing: 8
                clip: true
                model: Api.downloads
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool live: !["done", "error", "cancelled"].includes(modelData.status)
                    readonly property color tone: modelData.status === "error" ? Theme.mError : modelData.status === "done" ? Theme.mTertiary : Theme.mPrimary
                    width: list.width - 10
                    height: 78
                    radius: Theme.radiusM
                    color: Theme.card
                    Rectangle {
                        id: badge
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40; height: 40; radius: 12
                        color: Theme.alpha(row.tone, 0.15)
                        Icon {
                            anchors.centerIn: parent
                            name: row.modelData.status === "done" ? "check" : row.modelData.status === "error" ? "alert-triangle" : Theme.kind(row.modelData.kind).icon
                            size: 19
                            color: row.tone
                        }
                    }
                    Column {
                        anchors.left: badge.right
                        anchors.leftMargin: 14
                        anchors.right: act.left
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        RowLayout {
                            width: parent.width
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.label
                                elide: Text.ElideMiddle
                                color: Theme.mOnSurface
                                font.family: Theme.font
                                font.pixelSize: 14
                                font.weight: Font.Medium
                            }
                            Text {
                                text: row.live ? Math.round(row.modelData.progress * 100) + "%" : ""
                                color: Theme.mOnSurface
                                font.family: Theme.font
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: 6
                            radius: 3
                            color: Theme.alpha(Theme.mOnSurface, 0.1)
                            Rectangle {
                                width: parent.width * Math.min(1, row.modelData.status === "done" ? 1 : row.modelData.progress)
                                height: parent.height
                                radius: 3
                                color: row.tone
                                Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                            }
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: row.modelData.status === "error" ? row.modelData.error
                                : row.modelData.status === "done" ? "Done · " + Theme.bytes(row.modelData.total) + " · " + Theme.kind(row.modelData.kind).task
                                : row.modelData.status === "cancelled" ? "Cancelled"
                                : [row.modelData.total ? Theme.bytes(row.modelData.done) + " of " + Theme.bytes(row.modelData.total) : row.modelData.status,
                                   page.speeds[row.modelData.id] > 1000 ? Theme.bytes(page.speeds[row.modelData.id]) + "/s" : ""].filter(x => x).join(" · ")
                            color: row.modelData.status === "error" ? Theme.mError : Theme.mOnSurfaceVariant
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                    }
                    IconButton {
                        id: act
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.live
                        icon: "x"
                        tip: "Cancel"
                        onClicked: Api.post("/download/cancel", { id: row.modelData.id }, () => Api.poll())
                    }
                }
            }
        }
    }
}
