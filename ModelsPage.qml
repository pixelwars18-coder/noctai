import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// Browse Hugging Face (and the Ollama library for LLMs), download, and manage installed models.
Item {
    id: page
    property string kind: "llm"
    property string query: ""
    property string sort: "trendingScore"
    property var results: []
    property bool loading: false
    property string error: ""
    property string expanded: ""
    property var details: ({})
    property string confirmDelete: ""
    property var pending: null

    readonly property var installed: Api.local[kind] || []
    readonly property var installedIds: installed.map(m => m.id)
    readonly property real vram: Api.gpu ? Api.gpu.total * 1048576 : 10e9

    function search() {
        if (pending) pending.abort()
        loading = true
        error = ""
        expanded = ""
        pending = Api.get("/search?kind=" + kind + "&sort=" + sort + "&q=" + Api.q(query), d => {
            pending = null
            loading = false
            if (Array.isArray(d)) results = d
            else { results = []; error = d.error }
        })
    }
    function toggle(id) {
        expanded = expanded === id ? "" : id
        if (expanded && !details[id]) Api.get("/info?kind=" + kind + "&repo=" + Api.q(id), d => {
            const x = Object.assign({}, details)
            x[id] = d
            details = x
        })
    }
    function download(body) {
        Api.post("/download", Object.assign({ kind: kind }, body), d => {
            if (d.error) Api.toast(d.error, true)
            else { Api.toast("Downloading " + d.label, false); Api.poll() }
        })
    }
    function isInstalled(id, quant) {
        if (kind !== "llm") return installedIds.includes(id)
        const n = ("hf.co/" + id + (quant ? ":" + quant : "")).toLowerCase()
        return installedIds.some(x => x.toLowerCase() === n || (!quant && x.toLowerCase().startsWith(n + ":")))
    }
    function remove(m) {
        if (confirmDelete !== m.id) { confirmDelete = m.id; confirmTimer.restart(); return }
        confirmDelete = ""
        Api.post("/delete", { kind: kind, id: m.id }, d => {
            if (d.error) Api.toast(d.error, true)
            else { Api.toast("Deleted " + m.name, false); Api.refreshLocal(page.kind) }
        })
    }
    Timer { id: confirmTimer; interval: 3000; onTriggered: page.confirmDelete = "" }
    Timer { id: debounce; interval: 380; onTriggered: page.search() }
    onKindChanged: { details = ({}); search() }
    onSortChanged: search()
    Component.onCompleted: search()
    Connections {
        target: Api
        function onOnlineChanged() { if (Api.online && (page.error || !page.results.length)) page.search() }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 22
            Layout.bottomMargin: 14
            spacing: 12
            Column {
                Layout.fillWidth: true
                Text {
                    text: "Models"
                    color: Theme.mOnSurface
                    font.family: Theme.font
                    font.pixelSize: 24
                    font.weight: Font.Bold
                }
                Text {
                    text: page.kind === "llm" ? "GGUF builds from Hugging Face, pulled straight into Ollama"
                                              : "From Hugging Face · stored in ~/.cache/huggingface" + (Api.hfToken ? " · signed in" : "")
                    color: Theme.mOnSurfaceVariant
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
            Segmented {
                items: Theme.kinds.map(k => ({ value: k.key, text: k.task, icon: k.icon }))
                value: page.kind
                onPicked: v => page.kind = v
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            spacing: 10
            Field {
                id: searchField
                Layout.fillWidth: true
                icon: "search"
                placeholder: page.kind === "llm" ? "Search GGUF models, or type an Ollama name like llama3.2 / gemma3:4b"
                                                 : "Search " + Theme.kind(page.kind).noun + "s on Hugging Face"
                onTextChanged: { page.query = text; debounce.restart() }
                onSubmitted: { debounce.stop(); page.search() }
            }
            Dropdown {
                implicitWidth: 170
                icon: "arrows-sort"
                options: [{ value: "trendingScore", text: "Trending" }, { value: "downloads", text: "Most downloaded" },
                          { value: "likes", text: "Most liked" }, { value: "lastModified", text: "Recently updated" }]
                value: page.sort
                onPicked: v => page.sort = v
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 12
            clip: true
            spacing: 6
            leftMargin: 22
            rightMargin: 22
            bottomMargin: 22
            model: page.results
            ScrollBar.vertical: ScrollBar {}
            boundsBehavior: Flickable.StopAtBounds

            header: Column {
                width: list.width - 44
                spacing: 6
                bottomPadding: 10

                Text {
                    visible: page.installed.length > 0
                    text: "Installed"
                    color: Theme.mPrimary
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    bottomPadding: 2
                }
                Repeater {
                    model: page.installed
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        height: 52
                        radius: Theme.radiusM
                        color: Theme.card
                        Icon {
                            id: ico
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            name: "circle-check-filled"
                            size: 20
                            color: Theme.mTertiary
                        }
                        Column {
                            anchors.left: ico.right
                            anchors.leftMargin: 12
                            anchors.right: actions.left
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                width: parent.width
                                text: modelData.name
                                elide: Text.ElideRight
                                color: Theme.mOnSurface
                                font.family: Theme.font
                                font.pixelSize: 14
                                font.weight: Font.Medium
                            }
                            Text {
                                text: [modelData.detail, Theme.bytes(modelData.size), Api.loaded === modelData.id ? "loaded on GPU" : ""].filter(x => x).join(" · ")
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
                            spacing: 4
                            IconButton {
                                visible: page.kind !== "llm"
                                icon: "external-link"
                                tip: "Open on Hugging Face"
                                size: 30
                                onClicked: Qt.openUrlExternally("https://huggingface.co/" + modelData.id)
                            }
                            PillButton {
                                visible: page.confirmDelete === modelData.id
                                text: "Delete " + Theme.bytes(modelData.size) + "?"
                                danger: true
                                size: 30
                                onClicked: page.remove(modelData)
                            }
                            IconButton {
                                visible: page.confirmDelete !== modelData.id
                                icon: "trash"
                                tip: "Delete"
                                size: 30
                                onClicked: page.remove(modelData)
                            }
                        }
                    }
                }

                Item { width: 1; height: 8; visible: page.installed.length > 0 }
                RowLayout {
                    width: parent.width
                    Text {
                        Layout.fillWidth: true
                        text: page.query ? "Results for “" + page.query + "”" : "Discover"
                        color: Theme.mPrimary
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Text {
                        visible: page.loading
                        text: "Searching…"
                        color: Theme.mOnSurfaceVariant
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                }
                Text {
                    visible: page.error !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: page.error
                    color: Theme.mError
                    font.family: Theme.font
                    font.pixelSize: 12
                }

                // Pull straight from the Ollama library when the query looks like a model tag.
                Rectangle {
                    readonly property string name: page.query.trim().toLowerCase()
                    visible: page.kind === "llm" && /^[a-z0-9][a-z0-9._-]*(\/[a-z0-9._-]+)?(:[a-z0-9._-]+)?$/.test(name)
                    width: parent.width
                    height: 52
                    radius: Theme.radiusM
                    color: oma.containsMouse ? Theme.alpha(Theme.mPrimary, 0.16) : Theme.alpha(Theme.mPrimary, 0.09)
                    border.color: Theme.alpha(Theme.mPrimary, 0.3)
                    Icon {
                        id: oico
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        name: "brand-docker"
                        size: 20
                        color: Theme.mPrimary
                    }
                    Text {
                        anchors.left: oico.right
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Pull <b>" + parent.name + "</b> from the Ollama library"
                        textFormat: Text.StyledText
                        color: Theme.mOnSurface
                        font.family: Theme.font
                        font.pixelSize: 13
                    }
                    Icon {
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        name: "download"
                        size: 18
                        color: Theme.mPrimary
                    }
                    MouseArea {
                        id: oma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.download({ repo: parent.name, ollama: parent.name, label: parent.name })
                    }
                }
            }

            delegate: Rectangle {
                id: res
                required property var modelData
                readonly property bool open: page.expanded === modelData.id
                readonly property var det: page.details[modelData.id]
                readonly property string org: modelData.id.split("/")[0]
                readonly property string nm: modelData.id.split("/").slice(1).join("/")
                width: list.width - 44
                height: head.height + (open ? body.implicitHeight + 14 : 0)
                radius: Theme.radiusM
                color: open ? Theme.card : rma.containsMouse ? Theme.alpha(Theme.mOnSurface, 0.05) : "transparent"
                border.color: open ? Theme.alpha(Theme.mOutline, 0.9) : "transparent"
                clip: true
                Behavior on height { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: Theme.fast } }

                Item {
                    id: head
                    width: parent.width
                    height: 56
                    MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.toggle(res.modelData.id) }
                    Rectangle {
                        id: avatar
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34; height: 34; radius: 10
                        color: Theme.alpha(Theme.mSecondary, 0.16)
                        Text {
                            anchors.centerIn: parent
                            text: res.org.slice(0, 1).toUpperCase()
                            color: Theme.mSecondary
                            font.family: Theme.font
                            font.pixelSize: 15
                            font.weight: Font.Bold
                        }
                    }
                    Column {
                        anchors.left: avatar.right
                        anchors.leftMargin: 12
                        anchors.right: chips.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            width: parent.width
                            text: res.nm
                            elide: Text.ElideRight
                            color: Theme.mOnSurface
                            font.family: Theme.font
                            font.pixelSize: 14
                            font.weight: Font.Medium
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: res.org + (res.modelData.downloads ? "  ·  ↓ " + Theme.count(res.modelData.downloads) : "") + (res.modelData.likes ? "  ·  ♥ " + Theme.count(res.modelData.likes) : "")
                                  + (res.modelData.updated ? "  ·  " + res.modelData.updated.slice(0, 10) : "")
                            color: Theme.mOnSurfaceVariant
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                    }
                    Row {
                        id: chips
                        anchors.right: chev.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Chip { visible: !!res.modelData.suggested; text: "Suggested"; icon: "star"; tint: Theme.mTertiary }
                        Chip { visible: res.modelData.gated; text: "Gated"; icon: "lock"; tint: Theme.mSecondary }
                        Chip { visible: page.isInstalled(res.modelData.id, ""); text: "Installed"; icon: "check"; tint: Theme.mTertiary }
                    }
                    Icon {
                        id: chev
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron-down"
                        size: 16
                        color: Theme.mOnSurfaceVariant
                        rotation: res.open ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
                    }
                }

                Column {
                    id: body
                    visible: res.open
                    anchors.top: head.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 58
                    anchors.rightMargin: 16
                    spacing: 10

                    Text {
                        visible: !res.det
                        text: "Loading details…"
                        color: Theme.mOnSurfaceVariant
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    Text {
                        visible: !!res.det && !!res.det.error
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: res.det && res.det.error ? res.det.error : ""
                        color: Theme.mError
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    Text {
                        visible: !!res.det && !res.det.error
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: res.det ? [res.det.license ? "License: " + res.det.license : "", res.det.library ? "Library: " + res.det.library : "",
                                         res.det.gated ? "Gated: accept the license on huggingface.co, then run  hf auth login" : ""].filter(x => x).join("   ·   ") : ""
                        color: Theme.mOnSurfaceVariant
                        font.family: Theme.font
                        font.pixelSize: 12
                    }

                    // LLM: one chip per quantization.
                    Flow {
                        visible: page.kind === "llm" && !!res.det && !res.det.error
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: page.kind === "llm" && res.det && res.det.files ? res.det.files : []
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool fits: modelData.size < page.vram * 0.92
                                readonly property bool have: page.isInstalled(res.modelData.id, modelData.quant)
                                readonly property bool rec: modelData.quant === "Q4_K_M"
                                height: 40
                                width: qcol.implicitWidth + 24
                                radius: Theme.radiusS
                                color: have ? Theme.alpha(Theme.mTertiary, 0.15) : qma.containsMouse ? Theme.selected : Theme.field
                                border.color: rec ? Theme.selectedBorder : Theme.alpha(Theme.mOutline, 0.8)
                                opacity: fits || have ? 1 : 0.55
                                Column {
                                    id: qcol
                                    anchors.centerIn: parent
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: (have ? "✓ " : "") + modelData.quant
                                        color: have ? Theme.mTertiary : Theme.mOnSurface
                                        font.family: Theme.font
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: Theme.bytes(modelData.size) + (rec ? " · best" : !fits ? " · > VRAM" : "")
                                        color: Theme.mOnSurfaceVariant
                                        font.family: Theme.font
                                        font.pixelSize: 10
                                    }
                                }
                                MouseArea {
                                    id: qma
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !parent.have
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: page.download({ repo: res.modelData.id, quant: modelData.quant, size: modelData.size,
                                                               label: res.nm + " " + modelData.quant })
                                }
                            }
                        }
                    }
                    Text {
                        visible: page.kind === "llm" && !!res.det && !res.det.error && (res.det.files || []).length === 0
                        text: "No single-file GGUF quantizations found in this repo."
                        color: Theme.mOnSurfaceVariant
                        font.family: Theme.font
                        font.pixelSize: 12
                    }

                    // Everything else: one download for the set of files the pipeline needs.
                    Row {
                        visible: page.kind !== "llm" && !!res.det && !res.det.error
                        spacing: 10
                        PillButton {
                            enabled: !page.isInstalled(res.modelData.id, "")
                            text: page.isInstalled(res.modelData.id, "") ? "Installed" : "Download · " + Theme.bytes(res.det ? res.det.size : 0)
                            icon: page.isInstalled(res.modelData.id, "") ? "check" : "download"
                            onClicked: page.download({ repo: res.modelData.id })
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: res.det ? (res.det.files || []).length + " files" + (res.det.variant ? " · " + res.det.variant + " weights" : "")
                                            + (res.det.size > page.vram * 0.8 ? " · bigger than VRAM, will offload to RAM" : "") : ""
                            color: Theme.mOnSurfaceVariant
                            font.family: Theme.font
                            font.pixelSize: 12
                        }
                    }
                    PillButton {
                        text: "View on Hugging Face"
                        icon: "external-link"
                        filled: false
                        size: 32
                        onClicked: Qt.openUrlExternally("https://huggingface.co/" + res.modelData.id)
                    }
                }
            }
        }
    }

    function setKind(k) { kind = k }
}
