pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Talks to server.py over localhost, starting it when it isn't already running,
// and keeps a polled snapshot of downloads, jobs and GPU state.
Singleton {
    id: api

    readonly property string base: "http://127.0.0.1:" + (Quickshell.env("NOCTAI_PORT") || "47821")
    readonly property string home: Quickshell.env("NOCTAI_HOME") || Quickshell.shellDir
    property bool online: false
    property bool starting: false
    property string logTail: ""
    property var gpu: null
    property string loaded: ""
    property bool busy: false
    property string ollama: ""
    property bool hfToken: false
    property string outputs: ""
    property var downloads: []
    property var jobs: []
    property var local: ({ llm: [], tti: [], ttv: [], tts: [], tta: [] })
    property var outputsRev: ({ tti: 0, ttv: 0, tts: 0, tta: 0 })
    readonly property int activeDownloads: downloads.filter(d => !["done", "error", "cancelled"].includes(d.status)).length
    readonly property bool active: activeDownloads > 0 || jobs.some(j => j.status === "queued" || j.status === "loading" || j.status === "running")

    signal toast(string text, bool error)

    function request(method, path, body, cb) {
        const x = new XMLHttpRequest()
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE) return
            let d = null
            try { d = JSON.parse(x.responseText) } catch (e) {}
            if (x.status === 0) d = { error: "Backend not reachable" }
            else if (d === null) d = { error: "Bad response (" + x.status + ")" }
            if (cb) cb(d)
        }
        x.open(method, base + path)
        if (body !== undefined) {
            x.setRequestHeader("Content-Type", "application/json")
            x.send(JSON.stringify(body))
        } else x.send()
        return x
    }
    function get(path, cb) { return request("GET", path, undefined, cb) }
    function post(path, body, cb) { return request("POST", path, body || {}, cb) }
    function q(s) { return encodeURIComponent(s) }

    // Streams newline-delimited JSON; returns the XHR so the caller can abort().
    function stream(path, body, onEvent, onDone) {
        const x = new XMLHttpRequest()
        let seen = 0, buf = ""
        function pump() {
            const t = x.responseText
            if (!t || t.length <= seen) return
            buf += t.slice(seen)
            seen = t.length
            let i
            while ((i = buf.indexOf("\n")) >= 0) {
                const line = buf.slice(0, i)
                buf = buf.slice(i + 1)
                if (line.trim()) { try { onEvent(JSON.parse(line)) } catch (e) {} }
            }
        }
        x.onreadystatechange = () => {
            if (x.readyState === XMLHttpRequest.LOADING) pump()
            else if (x.readyState === XMLHttpRequest.DONE) { pump(); onDone(x.status) }
        }
        x.open("POST", base + path)
        x.setRequestHeader("Content-Type", "application/json")
        x.send(JSON.stringify(body))
        return x
    }

    function refreshLocal(kind) {
        const ks = kind ? [kind] : ["llm", "tti", "ttv", "tts", "tta"]
        for (const k of ks) get("/local?kind=" + k, d => {
            if (!Array.isArray(d)) return
            const l = Object.assign({}, local)
            l[k] = d
            local = l
        })
    }
    function bumpOutputs(kind) {
        const o = Object.assign({}, outputsRev)
        o[kind] = (o[kind] || 0) + 1
        outputsRev = o
    }
    function openPath(p) { Quickshell.execDetached(["xdg-open", p]) }

    // ---------------------------------------------------------- polling
    property var lastState: ({})
    function poll() {
        get("/status", d => {
            if (d.error) {
                if (online) toast("Lost connection to the backend", true)
                online = false
                if (!backend.running && !starting) startBackend()
                return
            }
            if (!online) { online = true; starting = false; refreshLocal() }
            gpu = d.gpu; loaded = d.loaded || ""; busy = d.busy; ollama = d.ollama || ""
            hfToken = d.hfToken; outputs = d.outputs
            const prev = lastState, next = {}
            for (const dl of d.downloads) {
                next[dl.id] = dl.status
                if (prev[dl.id] && prev[dl.id] !== dl.status) {
                    if (dl.status === "done") { toast("Downloaded " + dl.label, false); refreshLocal(dl.kind) }
                    else if (dl.status === "error") toast("Download failed: " + dl.error, true)
                }
            }
            for (const j of d.jobs) {
                next[j.id] = j.status
                if (prev[j.id] && prev[j.id] !== j.status) {
                    if (j.status === "done") bumpOutputs(j.kind)
                    else if (j.status === "error") toast(j.error, true)
                }
            }
            lastState = next
            downloads = d.downloads
            jobs = d.jobs
        })
    }
    Timer {
        interval: api.active ? 600 : 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: api.poll()
    }

    function startBackend() {
        starting = true
        backend.running = true
    }
    Process {
        id: backend
        command: [Quickshell.env("NOCTAI_PYTHON") || (api.home + "/venv/bin/python"), Quickshell.shellDir + "/server.py"]
        stderr: SplitParser {
            onRead: line => {
                const t = (api.logTail + "\n" + line).split("\n")
                api.logTail = t.slice(-40).join("\n")
            }
        }
        onExited: code => { api.starting = false; if (code !== 0) api.online = false }
    }
}
