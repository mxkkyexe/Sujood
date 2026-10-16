pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

QtObject {
    id: root
    readonly property string backend: Qt.resolvedUrl("backend.py").toString().replace("file://", "")
    property var prefs: ({})
    property var data: null
    property string error: ""
    property bool ready: false
    property bool busy: worker.running
    property double now: Date.now()
    readonly property var day: Model.today(data, now)
    readonly property var status: Model.state(data, now, prefs.showSunrise === true)
    readonly property string label: Model.label(status, now)
    property int revision: 0
    property int activeRevision: 0
    property bool queued: false
    property bool forceQueued: false
    property string action: "load"
    property string lastAlert: ""
    readonly property double startedAt: Date.now()
    property double lastSync: 0
    property var searchResults: []
    property string searchError: ""
    property string searchQuery: ""
    property string activeQuery: ""
    property bool searching: searcher.running

    function update(key, value, changesCalculation) {
        var next = JSON.parse(JSON.stringify(prefs))
        next[key] = value
        prefs = next
        revision++
        if (changesCalculation) data = null
        saveDelay.restart()
    }
    function sync(force) {
        if (!ready || worker.running) {
            queued = true
            forceQueued = forceQueued || !!force
            return
        }
        action = "sync"
        activeRevision = revision
        lastSync = Date.now()
        worker.payload = JSON.stringify({settings:prefs, force:!!force})
        worker.command = ["python3", backend, "sync", "--stdin"]
        worker.running = true
    }
    function search(text) {
        searchQuery = text.trim()
        searchResults = []
        searchError = ""
        if (searchQuery.length >= 2) searchDelay.restart()
        else searchDelay.stop()
    }
    function runSearch() {
        if (searcher.running || searchQuery.length < 2) return
        activeQuery = searchQuery
        searcher.payload = JSON.stringify({query:activeQuery})
        searcher.command = ["python3", backend, "search", "--stdin"]
        searcher.running = true
    }
    function tick() {
        now = Date.now()
        var prayer = status.prayer
        if (ready && prefs.alerts && status.phase === "arrival" && prayer.name !== "Sunrise" && prayer.at >= startedAt) {
            var key = prayer.date+":"+prayer.name
            if (lastAlert !== key && !alerter.running) {
                lastAlert = key
                alerter.payload = JSON.stringify(prayer)
                alerter.command = ["python3", backend, "alert", "--stdin"]
                alerter.running = true
            }
        }
        // Local cached reads are cheap; retry unavailable network data every five minutes.
        if (ready && !worker.running && now-lastSync >= (error ? 300000 : 60000)) sync(false)
    }
    Component.onCompleted: {
        worker.command = ["python3", backend, "load"]
        worker.running = true
    }
    property Process worker: Process {
        id: worker
        property string payload: ""
        stdinEnabled: true
        onStarted: {
            if (payload !== "") write(payload + "\n")
            payload = ""
        }
        stdout: StdioCollector {
            onStreamFinished: {
                var result = Model.parse(text, {error:"Could not read prayer data"})
                if (root.activeRevision === root.revision) {
                    if (result.settings) root.prefs = result.settings
                    root.data = result.data || null
                    root.error = result.error || ""
                }
            }
        }
        onExited: function(code) {
            if (code !== 0 && !root.error) root.error = "Could not load prayer data"
            if (root.action === "load") {
                root.ready = true
                root.queued = true
            }
            if (root.queued) {
                var force = root.forceQueued
                root.queued = false
                root.forceQueued = false
                Qt.callLater(function() { root.sync(force) })
            }
        }
    }
    property Timer clock: Timer { interval: 1000; running: true; repeat: true; onTriggered: root.tick() }
    property Timer saveDelay: Timer { interval: 250; onTriggered: root.sync(false) }
    property Timer searchDelay: Timer { interval: 300; onTriggered: root.runSearch() }
    property Process alerter: Process {
        id: alerter
        property string payload: ""
        stdinEnabled: true
        onStarted: { write(payload + "\n"); payload = "" }
    }
    property Process searcher: Process {
        id: searcher
        property string payload: ""
        stdinEnabled: true
        onStarted: { write(payload + "\n"); payload = "" }
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.activeQuery !== root.searchQuery) return
                var result = Model.parse(text, {error:"City search failed"})
                root.searchResults = result.results || []
                root.searchError = result.error || (root.searchResults.length ? "" : "No matching cities")
            }
        }
        onExited: if (root.activeQuery !== root.searchQuery) Qt.callLater(root.runSearch)
    }
}
