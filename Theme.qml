pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Noctalia palette + design tokens. A Noctalia user template (noctai.toml) renders the
// live palette to $XDG_STATE_HOME/noctai/theme.json; until that exists we borrow another
// app's copy, and finally fall back to stock Noctalia colors.
Singleton {
    id: theme

    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
    property int source: 0
    readonly property var sources: ["/noctai/theme.json", "/noctafiles/theme.json", "/noctacast/theme.json", "/ytmusic/theme.json"]

    FileView {
        path: theme.source < theme.sources.length ? theme.stateDir + theme.sources[theme.source] : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoadFailed: Qt.callLater(() => theme.source++)
        adapter: JsonAdapter {
            id: pal
            property string mode: "dark"
            property string mPrimary: "#fff59b"
            property string mOnPrimary: "#0e0e43"
            property string mSecondary: "#a9aefe"
            property string mTertiary: "#9BFECE"
            property string mSurface: "#070722"
            property string mSurfaceVariant: "#11112d"
            property string mOnSurface: "#f3edf7"
            property string mOnSurfaceVariant: "#7c80b4"
            property string mOutline: "#21215F"
            property string mError: "#fd4663"
        }
    }

    readonly property bool dark: pal.mode !== "light"
    readonly property color mPrimary: pal.mPrimary
    readonly property color mOnPrimary: pal.mOnPrimary
    readonly property color mSecondary: pal.mSecondary
    readonly property color mTertiary: pal.mTertiary
    readonly property color mSurface: pal.mSurface
    readonly property color mSurfaceVariant: pal.mSurfaceVariant
    readonly property color mOnSurface: pal.mOnSurface
    readonly property color mOnSurfaceVariant: pal.mOnSurfaceVariant
    readonly property color mOutline: pal.mOutline
    readonly property color mError: pal.mError

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1) }

    readonly property color hover: alpha(mOnSurface, 0.07)
    readonly property color selected: alpha(mPrimary, 0.20)
    readonly property color selectedBorder: alpha(mPrimary, 0.55)
    readonly property color card: mix(mSurface, mSurfaceVariant, 0.55)
    readonly property color field: mix(mSurface, mSurfaceVariant, 0.9)

    readonly property int radiusL: 22
    readonly property int radiusM: 14
    readonly property int radiusS: 10

    readonly property int fast: 130
    readonly property int normal: 240
    readonly property int slow: 380
    // Material 3 "emphasized decelerate"
    readonly property var emphasized: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]

    readonly property string font: "Noto Sans"
    readonly property string mono: "monospace"
    readonly property string iconFont: icons.name
    FontLoader { id: icons; source: "file:///usr/share/noctalia/assets/fonts/noctalia-tabler.ttf" }

    // Every Tabler glyph Noctalia ships, looked up by name.
    property var tabler: ({})
    FileView {
        path: "/usr/share/noctalia/assets/fonts/tabler.json"
        blockLoading: true
        printErrors: false
        onLoaded: { try { theme.tabler = JSON.parse(text()) } catch (e) {} }
    }
    function glyph(name) {
        const e = tabler[name] || tabler["question-mark"]
        return e ? String.fromCodePoint(parseInt(e.codepoint.slice(2), 16)) : ""
    }

    // The five generators, in nav order.
    readonly property var kinds: [
        { key: "llm", label: "Chat", title: "Chat", icon: "message-chatbot", noun: "language model", task: "LLM" },
        { key: "tti", label: "Image", title: "Text to Image", icon: "photo", noun: "image model", task: "Image" },
        { key: "ttv", label: "Video", title: "Text to Video", icon: "movie", noun: "video model", task: "Video" },
        { key: "tts", label: "Speech", title: "Text to Speech", icon: "microphone", noun: "voice model", task: "Speech" },
        { key: "tta", label: "Audio", title: "Text to Audio", icon: "music", noun: "audio / music model", task: "Audio" }
    ]
    function kind(key) { return kinds.find(k => k.key === key) || kinds[0] }

    function bytes(n) {
        if (!n) return "0 B"
        const u = ["B", "KB", "MB", "GB", "TB"]
        let i = 0
        while (n >= 1000 && i < u.length - 1) { n /= 1000; i++ }
        return (i >= 3 ? n.toFixed(n < 10 ? 2 : 1) : Math.round(n)) + " " + u[i]
    }
    function count(n) {
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
        if (n >= 1e3) return (n / 1e3).toFixed(1) + "k"
        return String(n || 0)
    }
}
