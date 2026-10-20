import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// Streaming chat against any Ollama model, with optional thinking and a system prompt.
Item {
    id: page
    signal browse(string kind)

    readonly property var models: Api.local.llm
    property string model: ""
    readonly property var modelInfo: models.find(m => m.id === model)
    readonly property bool canThink: !!modelInfo && (modelInfo.capabilities || []).includes("thinking")
    property bool think: false
    property bool showSettings: false
    property string system: ""
    property real temperature: 0.7
    property var xhr: null
    readonly property bool streaming: xhr !== null

    onModelsChanged: if (!modelInfo && models.length) model = models[0].id

    ListModel { id: msgs }

    function send() {
        const text = input.text.trim()
        if (!text || streaming || !model) return
        input.text = ""
        msgs.append({ role: "user", content: text, thinking: "", tps: 0, error: "", model: "" })
        const history = []
        if (system.trim()) history.push({ role: "system", content: system.trim() })
        for (let i = 0; i < msgs.count; i++) {
            const m = msgs.get(i)
            if (!m.error) history.push({ role: m.role, content: m.content })
        }
        msgs.append({ role: "assistant", content: "", thinking: "", tps: 0, error: "", model: model })
        const idx = msgs.count - 1
        let content = "", thinking = ""
        const body = { model: model, messages: history, options: { temperature: temperature } }
        if (canThink) body.think = think
        xhr = Api.stream("/chat", body, ev => {
            if (ev.error) { msgs.setProperty(idx, "error", ev.error); return }
            if (ev.t) { thinking += ev.t; msgs.setProperty(idx, "thinking", thinking) }
            if (ev.c) { content += ev.c; msgs.setProperty(idx, "content", content) }
            if (ev.done) msgs.setProperty(idx, "tps", ev.tps || 0)
            if (list.atEnd) Qt.callLater(list.positionViewAtEnd)
        }, status => {
            if (status === 0 && !content && !msgs.get(idx).error)
                msgs.setProperty(idx, "error", xhrAborted ? "Stopped" : "Backend not reachable")
            xhrAborted = false
            xhr = null
        })
        Qt.callLater(list.positionViewAtEnd)
    }
    property bool xhrAborted: false
    function stop() { if (xhr) { xhrAborted = true; xhr.abort() } }
    function clear() { stop(); msgs.clear() }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---------------------------------------------------------- header
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 22
            Layout.bottomMargin: 10
            spacing: 10
            Column {
                Layout.fillWidth: true
                Text {
                    text: "Chat"
                    color: Theme.mOnSurface
                    font.family: Theme.font
                    font.pixelSize: 24
                    font.weight: Font.Bold
                }
                Text {
                    text: Api.ollama ? "Ollama " + Api.ollama + " · " + page.models.length + " model" + (page.models.length === 1 ? "" : "s")
                                     : "Ollama is not running: start it with  systemctl start ollama"
                    color: Api.ollama ? Theme.mOnSurfaceVariant : Theme.mError
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
            Chip {
                visible: page.canThink
                text: page.think ? "Thinking on" : "Thinking off"
                icon: "bulb"
                clickable: true
                tint: page.think ? Theme.mTertiary : Theme.mOnSurfaceVariant
                onClicked: page.think = !page.think
                implicitHeight: 32
            }
            Dropdown {
                icon: "message-chatbot"
                placeholder: page.models.length ? "Choose a model" : "No models"
                options: page.models.map(m => ({ value: m.id, text: m.name, sub: m.detail + " · " + Theme.bytes(m.size) }))
                value: page.model
                onPicked: v => page.model = v
            }
            IconButton { icon: "adjustments"; tip: "Settings"; active: page.showSettings; onClicked: page.showSettings = !page.showSettings }
            IconButton { icon: "plus"; tip: "New chat"; enabled: msgs.count > 0; onClicked: page.clear() }
        }

        // ---------------------------------------------------------- settings
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            Layout.preferredHeight: page.showSettings ? settingsCol.implicitHeight + 28 : 0
            visible: Layout.preferredHeight > 1
            clip: true
            radius: Theme.radiusM
            color: Theme.card
            Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
            ColumnLayout {
                id: settingsCol
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10
                Field {
                    Layout.fillWidth: true
                    multiline: true
                    minLines: 2
                    maxLines: 5
                    placeholder: "System prompt (optional): how the assistant should behave"
                    text: page.system
                    onTextChanged: page.system = text
                }
                ParamSlider {
                    Layout.preferredWidth: 300
                    label: "Temperature"
                    from: 0; to: 2; step: 0.05; decimals: 2
                    value: page.temperature
                    onMoved: v => page.temperature = v
                }
            }
        }

        // ---------------------------------------------------------- messages
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            EmptyState {
                anchors.centerIn: parent
                visible: msgs.count === 0
                icon: page.models.length ? "sparkles" : "cloud-download"
                title: page.models.length ? "What's on your mind?" : "No language models yet"
                hint: page.models.length ? "Everything runs on your machine through Ollama."
                                         : "Grab a GGUF from Hugging Face or pull one from the Ollama library."
                action: page.models.length ? "" : "Browse LLMs"
                actionIcon: "search"
                onTriggered: page.browse("llm")
            }

            ListView {
                id: list
                anchors.fill: parent
                anchors.leftMargin: 22
                anchors.rightMargin: 10
                model: msgs
                spacing: 18
                clip: true
                topMargin: 10
                bottomMargin: 10
                readonly property bool atEnd: contentHeight <= height || contentY + height >= contentHeight - 80
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Item {
                    id: row
                    required property int index
                    required property string role
                    required property string content
                    required property string thinking
                    required property real tps
                    required property string error
                    required property string model
                    readonly property bool mine: role === "user"
                    readonly property bool live: page.streaming && index === msgs.count - 1
                    property bool showThink: false
                    width: list.width - 12
                    height: col.implicitHeight

                    Rectangle {
                        visible: !row.mine
                        width: 30; height: 30; radius: 15
                        color: Theme.alpha(Theme.mPrimary, 0.15)
                        Icon { anchors.centerIn: parent; name: "sparkles"; size: 16; color: Theme.mPrimary }
                    }
                    Column {
                        id: col
                        x: row.mine ? row.width - width : 42
                        width: row.mine ? Math.min(bubble.implicitW, row.width * 0.75) : row.width - 42
                        spacing: 6

                        Text {
                            visible: !row.mine && row.thinking !== ""
                            text: (row.live && row.content === "" ? "Thinking…" : "Thoughts") + (row.showThink ? "  ▾" : "  ▸")
                            color: Theme.mTertiary
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: row.showThink = !row.showThink }
                        }
                        Rectangle {
                            visible: row.showThink && row.thinking !== ""
                            width: parent.width
                            height: thinkText.implicitHeight + 20
                            radius: Theme.radiusS
                            color: Theme.alpha(Theme.mTertiary, 0.07)
                            border.color: Theme.alpha(Theme.mTertiary, 0.2)
                            TextEdit {
                                id: thinkText
                                anchors.fill: parent
                                anchors.margins: 10
                                text: row.thinking
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.Wrap
                                color: Theme.mOnSurfaceVariant
                                font.family: Theme.font
                                font.pixelSize: 12
                                font.italic: true
                            }
                        }
                        Rectangle {
                            id: bubble
                            readonly property real implicitW: msgText.implicitWidth + 30
                            width: parent.width
                            height: msgText.implicitHeight + (row.mine ? 20 : 4)
                            radius: Theme.radiusM
                            color: row.mine ? Theme.alpha(Theme.mPrimary, 0.16) : "transparent"
                            visible: row.content !== "" || row.mine
                            TextEdit {
                                id: msgText
                                x: row.mine ? 15 : 0
                                y: row.mine ? 10 : 2
                                width: parent.width - (row.mine ? 30 : 0)
                                text: row.content
                                textFormat: row.mine ? TextEdit.PlainText : TextEdit.MarkdownText
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.Wrap
                                color: Theme.mOnSurface
                                selectionColor: Theme.alpha(Theme.mPrimary, 0.4)
                                font.family: Theme.font
                                font.pixelSize: 14
                                onLinkActivated: link => Qt.openUrlExternally(link)
                            }
                        }
                        Row {
                            visible: row.live && row.content === "" && row.thinking === ""
                            spacing: 5
                            Repeater {
                                model: 3
                                Rectangle {
                                    required property int index
                                    width: 7; height: 7; radius: 4
                                    color: Theme.mPrimary
                                    SequentialAnimation on opacity {
                                        loops: Animation.Infinite
                                        PauseAnimation { duration: index * 160 }
                                        NumberAnimation { from: 0.2; to: 1; duration: 380 }
                                        NumberAnimation { from: 1; to: 0.2; duration: 380 }
                                        PauseAnimation { duration: (2 - index) * 160 }
                                    }
                                }
                            }
                        }
                        Text {
                            visible: row.error !== ""
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: row.error
                            color: Theme.mError
                            font.family: Theme.font
                            font.pixelSize: 12
                        }
                        Row {
                            visible: !row.mine && !row.live && row.content !== ""
                            spacing: 8
                            IconButton {
                                icon: "copy"; tip: "Copy"; size: 26
                                onClicked: { clip.text = row.content; clip.selectAll(); clip.copy(); Api.toast("Copied", false) }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.model + (row.tps ? " · " + row.tps + " tok/s" : "")
                                color: Theme.alpha(Theme.mOnSurfaceVariant, 0.8)
                                font.family: Theme.font
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }
        }

        // ---------------------------------------------------------- composer
        Rectangle {
            Layout.fillWidth: true
            Layout.margins: 22
            Layout.topMargin: 6
            implicitHeight: input.implicitHeight
            radius: Theme.radiusL
            color: "transparent"
            Field {
                id: input
                anchors.left: parent.left
                anchors.right: sendBtn.left
                anchors.rightMargin: 10
                anchors.bottom: parent.bottom
                multiline: true
                maxLines: 8
                radius: Theme.radiusL
                placeholder: page.model ? "Message " + page.model + "…  (Shift+Enter for a new line)" : "Download a model to start chatting"
                enabled: !!page.model
                onSubmitted: page.send()
            }
            Rectangle {
                id: sendBtn
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 46; height: 46; radius: 23
                color: page.streaming ? Theme.mError : Theme.mPrimary
                opacity: page.streaming || input.text.trim() !== "" ? 1 : 0.4
                scale: sendArea.pressed ? 0.9 : 1
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                Behavior on scale { NumberAnimation { duration: Theme.fast } }
                Icon {
                    anchors.centerIn: parent
                    name: page.streaming ? "player-stop-filled" : "arrow-up"
                    size: 21
                    color: page.streaming ? Theme.mSurface : Theme.mOnPrimary
                }
                MouseArea {
                    id: sendArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.streaming ? page.stop() : page.send()
                }
            }
        }
    }
    TextEdit { id: clip; visible: false }
}
