import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Widgets

// One page per generator kind (tti, ttv, tts, tta): prompt + parameters on the left,
// the gallery of past results on the right.
Item {
    id: page
    required property string kind
    signal browse(string kind)
    signal view(var items, int index)

    readonly property var info: Theme.kind(kind)
    readonly property bool visual: kind === "tti" || kind === "ttv"
    readonly property var models: Api.local[kind] || []
    property string model: ""
    readonly property var modelInfo: models.find(m => m.id === model)
    readonly property var defaults: modelInfo ? (modelInfo.defaults || {}) : {}
    property var values: ({})
    property string jobId: ""
    readonly property var job: Api.jobs.find(j => j.id === jobId) || null
    readonly property bool running: !!job && ["queued", "loading", "running"].includes(job.status)
    property var results: []

    onModelsChanged: if (!modelInfo && models.length) model = models[0].id
    onModelChanged: resetParams()
    Component.onCompleted: reload()
    Connections {
        target: Api
        function onOutputsRevChanged() { page.reload() }
        function onOnlineChanged() { if (Api.online) page.reload() }
    }

    // [key, label, from, to, step, decimals, suffix]; a control appears when the model has a default for it.
    readonly property var schema: ({
        tti: [["width", "Width", 256, 2048, 64, 0, " px"], ["height", "Height", 256, 2048, 64, 0, " px"],
              ["steps", "Steps", 1, 80, 1, 0, ""], ["guidance", "Guidance", 0, 20, 0.5, 1, ""], ["count", "Images", 1, 4, 1, 0, ""]],
        ttv: [["width", "Width", 256, 1280, 32, 0, " px"], ["height", "Height", 256, 1280, 32, 0, " px"],
              ["frames", "Frames", 9, 161, 8, 0, ""], ["fps", "FPS", 4, 30, 1, 0, ""],
              ["steps", "Steps", 1, 80, 1, 0, ""], ["guidance", "Guidance", 0, 15, 0.5, 1, ""]],
        tts: [["speed", "Speed", 0.5, 2, 0.05, 2, "×"]],
        tta: [["duration", "Duration", 1, 30, 1, 0, " s"], ["steps", "Steps", 10, 200, 5, 0, ""], ["guidance", "Guidance", 0, 15, 0.5, 1, ""]]
    })
    readonly property var controls: (schema[kind] || []).filter(c => c[0] === "count" || defaults[c[0]] !== undefined)
    readonly property bool diffusion: kind === "tti" || kind === "ttv" || (kind === "tta" && defaults.steps !== undefined)

    function resetParams() {
        const m = models.find(x => x.id === model)
        values = Object.assign({ count: 1, seed: -1, voice: "af_heart" }, m ? m.defaults : {})
        seedField.text = ""
    }
    function setValue(k, x) { const v = Object.assign({}, values); v[k] = x; values = v }

    function reload() {
        Api.get("/outputs?kind=" + kind, d => { if (Array.isArray(d)) page.results = d })
    }
    function generate() {
        if (running) { Api.post("/cancel", { id: jobId }); return }
        const prompt = promptField.text.trim()
        if (!prompt || !model) return
        const p = Object.assign({}, values)
        p.negative = negField.text.trim()
        p.seed = parseInt(seedField.text.trim()); if (isNaN(p.seed)) p.seed = -1
        Api.post("/generate", { kind: kind, model: model, prompt: prompt, params: p }, d => {
            if (d.error) Api.toast(d.error, true)
            else { page.jobId = d.id; Api.poll() }
        })
    }
    function remove(path) { Api.post("/outputs/delete", { path: path }, () => page.reload()) }

    // ---------------------------------------------------------- audio playback (speech/audio pages)
    property string playing: ""
    MediaPlayer {
        id: player
        audioOutput: AudioOutput {}
        onPlaybackStateChanged: if (playbackState === MediaPlayer.StoppedState) page.playing = ""
    }
    function toggle(path) {
        if (playing === path && player.playbackState === MediaPlayer.PlayingState) { player.pause(); return }
        if (playing !== path) { player.source = "file://" + path; playing = path }
        player.play()
    }
    onVisibleChanged: if (!visible) player.pause()

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ---------------------------------------------------------- controls column
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 360
            color: Theme.alpha(Theme.mSurfaceVariant, 0.35)

            Flickable {
                id: side
                anchors.fill: parent
                contentHeight: sideCol.implicitHeight + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}

                ColumnLayout {
                    id: sideCol
                    x: 22
                    y: 22
                    width: side.width - 44
                    spacing: 14

                    Column {
                        Layout.fillWidth: true
                        Text {
                            text: page.info.title
                            color: Theme.mOnSurface
                            font.family: Theme.font
                            font.pixelSize: 24
                            font.weight: Font.Bold
                        }
                        Text {
                            text: page.models.length + " " + page.info.noun + (page.models.length === 1 ? "" : "s") + " installed"
                            color: Theme.mOnSurfaceVariant
                            font.family: Theme.font
                            font.pixelSize: 12
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Dropdown {
                            Layout.fillWidth: true
                            icon: page.info.icon
                            placeholder: page.models.length ? "Choose a model" : "No models installed"
                            options: page.models.map(m => ({ value: m.id, text: m.name, sub: m.detail + " · " + Theme.bytes(m.size) }))
                            value: page.model
                            onPicked: v => page.model = v
                        }
                        IconButton { icon: "cloud-download"; tip: "Get more models"; onClicked: page.browse(page.kind) }
                    }

                    Text {
                        text: page.kind === "tts" ? "Text" : "Prompt"
                        color: Theme.mOnSurfaceVariant
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    Field {
                        id: promptField
                        Layout.fillWidth: true
                        multiline: true
                        minLines: 4
                        maxLines: 10
                        placeholder: ({ tti: "A lighthouse on a cliff at dusk, volumetric light, film grain",
                                        ttv: "A red fox trotting through fresh snow, slow motion, golden hour",
                                        tts: "Type what you want to hear spoken…",
                                        tta: "Warm lo-fi hip hop beat with vinyl crackle and soft piano" })[page.kind]
                        onSubmitted: page.generate()
                    }
                    Field {
                        id: negField
                        visible: page.diffusion
                        Layout.fillWidth: true
                        multiline: true
                        minLines: 1
                        maxLines: 4
                        placeholder: "Negative prompt (optional)"
                        onSubmitted: page.generate()
                    }

                    Dropdown {
                        visible: !!page.modelInfo && (page.modelInfo.voices || []).length > 0
                        Layout.fillWidth: true
                        icon: "user"
                        options: (page.modelInfo && page.modelInfo.voices || []).map(v => ({ value: v, text: v, sub: ({ a: "American English", b: "British English", j: "Japanese", z: "Mandarin", e: "Spanish", f: "French", h: "Hindi", i: "Italian", p: "Portuguese" })[v[0]] || "" }))
                        value: page.values.voice
                        onPicked: v => page.setValue("voice", v)
                    }

                    Repeater {
                        model: page.controls
                        delegate: ParamSlider {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData[1]
                            from: modelData[2]; to: modelData[3]; step: modelData[4]; decimals: modelData[5]; suffix: modelData[6]
                            value: page.values[modelData[0]] ?? modelData[2]
                            onMoved: v => page.setValue(modelData[0], v)
                        }
                    }
                    RowLayout {
                        visible: page.diffusion
                        Layout.fillWidth: true
                        spacing: 8
                        Field {
                            id: seedField
                            Layout.fillWidth: true
                            icon: "dice-3"
                            placeholder: "Random seed"
                        }
                        IconButton {
                            icon: "history"
                            tip: "Reuse last seed"
                            enabled: !!page.job && page.job.seed !== undefined
                            onClicked: seedField.text = String(page.job.seed)
                        }
                    }

                    PillButton {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        size: 46
                        enabled: page.running || (!!page.model && promptField.text.trim() !== "")
                        icon: page.running ? "player-stop-filled" : "sparkles"
                        text: !page.running ? "Generate"
                              : page.job.status === "queued" ? "Queued · Cancel"
                              : page.job.status === "loading" ? "Loading model · Cancel"
                              : page.job.steps ? "Step " + page.job.step + " / " + page.job.steps + " · Cancel"
                              : "Generating · Cancel"
                        progress: page.running ? (page.job.status === "running" ? page.job.progress : 0) : -1
                        onClicked: page.generate()
                    }
                    Text {
                        visible: !!page.job && page.job.status === "error"
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: page.job ? page.job.error : ""
                        color: Theme.mError
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    Text {
                        visible: !!page.job && page.job.status === "done"
                        text: page.job ? "Done in " + page.job.seconds + " s · seed " + page.job.seed : ""
                        color: Theme.mOnSurfaceVariant
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    Text {
                        visible: page.kind === "ttv" && !!page.modelInfo
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Video is heavy: start small (fewer frames, 480p). Large models stream from system RAM."
                        color: Theme.alpha(Theme.mOnSurfaceVariant, 0.8)
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                }
            }
        }

        // ---------------------------------------------------------- results
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            RowLayout {
                id: resHeader
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 22
                Text {
                    Layout.fillWidth: true
                    text: page.results.length ? page.results.length + " result" + (page.results.length === 1 ? "" : "s") : ""
                    color: Theme.mOnSurfaceVariant
                    font.family: Theme.font
                    font.pixelSize: 13
                }
                IconButton {
                    icon: "folder-open"
                    tip: "Open output folder"
                    onClicked: Api.openPath(Api.outputs + "/" + page.kind)
                }
            }

            EmptyState {
                anchors.centerIn: parent
                visible: page.results.length === 0
                icon: page.models.length ? page.info.icon : "cloud-download"
                title: page.models.length ? "Nothing generated yet" : "No " + page.info.noun + "s yet"
                hint: page.models.length ? "Write a prompt and hit Generate. Results land here and in " + (Api.outputs || "the output folder") + "."
                                         : "Download one from Hugging Face to get started."
                action: page.models.length ? "" : "Browse " + page.info.label.toLowerCase() + " models"
                actionIcon: "search"
                onTriggered: page.browse(page.kind)
            }

            GridView {
                id: grid
                visible: page.visual
                anchors.fill: parent
                anchors.topMargin: 66
                anchors.leftMargin: 18
                anchors.rightMargin: 8
                clip: true
                readonly property int cols: Math.max(1, Math.floor((width - 10) / 240))
                cellWidth: Math.floor((width - 10) / cols)
                cellHeight: cellWidth
                model: page.visual ? page.results : []
                ScrollBar.vertical: ScrollBar {}
                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    width: grid.cellWidth
                    height: grid.cellHeight
                    ClippingRectangle {
                        anchors.fill: parent
                        anchors.margins: 5
                        radius: Theme.radiusM
                        color: Theme.card
                        scale: hov.containsMouse ? 1.0 : 0.985
                        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
                        Image {
                            anchors.fill: parent
                            source: "file://" + cell.modelData.thumb
                            sourceSize.width: 480
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.normal } }
                        }
                        Rectangle {
                            visible: page.kind === "ttv"
                            anchors.centerIn: parent
                            width: 46; height: 46; radius: 23
                            color: Theme.alpha(Theme.mSurface, 0.6)
                            Icon { anchors.centerIn: parent; name: "player-play-filled"; size: 20; color: Theme.mOnSurface }
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 64
                            opacity: hov.containsMouse ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                            gradient: Gradient {
                                GradientStop { position: 0; color: "transparent" }
                                GradientStop { position: 1; color: Theme.alpha(Theme.mSurface, 0.92) }
                            }
                            Text {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 10
                                text: cell.modelData.prompt
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                                color: Theme.mOnSurface
                                font.family: Theme.font
                                font.pixelSize: 11
                            }
                        }
                    }
                    MouseArea {
                        id: hov
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.view(page.results, cell.index)
                    }
                }
            }

            ListView {
                id: audioList
                visible: !page.visual
                anchors.fill: parent
                anchors.topMargin: 66
                anchors.leftMargin: 22
                anchors.rightMargin: 12
                spacing: 8
                clip: true
                model: page.visual ? [] : page.results
                ScrollBar.vertical: ScrollBar {}
                delegate: Rectangle {
                    id: arow
                    required property var modelData
                    readonly property bool current: page.playing === modelData.path
                    readonly property bool isPlaying: current && player.playbackState === MediaPlayer.PlayingState
                    width: audioList.width - 10
                    height: 68
                    radius: Theme.radiusM
                    color: current ? Theme.selected : ahov.containsMouse ? Theme.alpha(Theme.mOnSurface, 0.09) : Theme.card
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    MouseArea { id: ahov; anchors.fill: parent; hoverEnabled: true; onClicked: page.toggle(arow.modelData.path) }
                    Rectangle {
                        id: playBtn
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42; height: 42; radius: 21
                        color: Theme.mPrimary
                        Icon {
                            anchors.centerIn: parent
                            name: arow.isPlaying ? "player-pause-filled" : "player-play-filled"
                            size: 18
                            color: Theme.mOnPrimary
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.toggle(arow.modelData.path) }
                    }
                    Column {
                        anchors.left: playBtn.right
                        anchors.leftMargin: 14
                        anchors.right: actions.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Text {
                            width: parent.width
                            text: arow.modelData.prompt || arow.modelData.name
                            elide: Text.ElideRight
                            color: Theme.mOnSurface
                            font.family: Theme.font
                            font.pixelSize: 13
                        }
                        Rectangle {
                            visible: arow.current
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Theme.alpha(Theme.mOnSurface, 0.12)
                            Rectangle {
                                width: player.duration > 0 ? parent.width * player.position / player.duration : 0
                                height: parent.height
                                radius: 2
                                color: Theme.mPrimary
                            }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ev => player.position = player.duration * ev.x / width
                            }
                        }
                        Text {
                            visible: !arow.current
                            width: parent.width
                            text: arow.modelData.model.split("/").pop() + (arow.modelData.seconds ? " · made in " + arow.modelData.seconds + " s" : "")
                            elide: Text.ElideRight
                            color: Theme.mOnSurfaceVariant
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                    }
                    Row {
                        id: actions
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        IconButton { icon: "pencil"; tip: "Reuse text"; size: 30; onClicked: promptField.text = arow.modelData.prompt }
                        IconButton { icon: "external-link"; tip: "Open"; size: 30; onClicked: Api.openPath(arow.modelData.path) }
                        IconButton { icon: "trash"; tip: "Delete"; size: 30; onClicked: { if (arow.current) player.stop(); page.remove(arow.modelData.path) } }
                    }
                }
            }
        }
    }

    function reusePrompt(p) { promptField.text = p }
}
