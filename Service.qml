import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property string moduleName: "iusevimbtw.omaup"

  property var items: []
  property int itemsRevision: 0
  property string greenHex: ""
  property var pendingIds: []
  property string activeId: ""
  property int checkGeneration: 0
  property int activeGeneration: 0
  property bool hydrating: false
  property bool configReady: false
  property bool writingConfig: false
  property string lastWrittenConfig: ""
  property bool offline: false
  property bool connectivityPending: false
  property bool checkAfterProbe: false
  property bool connectivityForceCheck: false
  property string connectivityStep: ""
  property var passSnapshot: null
  property int passChecks: 0
  property int passLocalFails: 0

  readonly property string configDir: {
    var xdg = String(Quickshell.env("XDG_CONFIG_HOME") || "")
    var home = String(Quickshell.env("HOME") || "")
    var base = xdg !== "" ? xdg : (home + "/.config")
    return base + "/omaup"
  }
  readonly property string configPath: configDir + "/config.json"
  readonly property color themeGreen: greenHex !== "" ? greenHex : Color.accent
  readonly property int refreshIntervalSec: intervalFromShell(shell ? shell.shellConfig : null, 30, 5, 3600)
  readonly property int targetCount: { itemsRevision; return Array.isArray(items) ? items.length : 0 }
  readonly property int downCount: { itemsRevision; return Model.countBy(items, "status", "down") }
  readonly property int upCount: { itemsRevision; return Model.countBy(items, "status", "up") }
  readonly property string heroMeta: {
    itemsRevision
    if (offline) return "No internet"
    return Model.heroMeta(items)
  }
  readonly property color overallColor: {
    itemsRevision
    if (downCount > 0) return Color.urgent
    if (upCount > 0) return themeGreen
    return Color.foreground
  }

  function intervalFromShell(config, fallback, min, max) {
    var raw = fallback
    if (config && config.bar && config.bar.layout) {
      var sections = ["left", "center", "right"]
      for (var s = 0; s < sections.length; s++) {
        var arr = config.bar.layout[sections[s]]
        if (!Array.isArray(arr)) continue
        for (var i = 0; i < arr.length; i++) {
          if (arr[i] && String(arr[i].id || "") === moduleName && arr[i].refreshIntervalSec !== undefined) {
            raw = arr[i].refreshIntervalSec
          }
        }
      }
    }
    var n = parseInt(String(raw), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function setItems(next) {
    items = next
    itemsRevision++
  }

  function findIndex(id) {
    for (var i = 0; i < items.length; i++) {
      if (items[i] && items[i].id === id) return i
    }
    return -1
  }

  function findByUrl(url) {
    var needle = String(url || "")
    for (var i = 0; i < items.length; i++) {
      if (items[i] && items[i].url === needle) return items[i]
    }
    return null
  }

  function patchItem(id, fields) {
    var index = findIndex(id)
    if (index < 0) return
    var next = items.slice()
    var item = {}
    var current = items[index]
    for (var key in current) item[key] = current[key]
    for (var field in fields) item[field] = fields[field]
    next[index] = item
    setItems(next)
  }

  function applyTargets(configured) {
    var previous = {}
    for (var i = 0; i < items.length; i++) {
      if (items[i]) previous[items[i].id] = items[i]
    }
    var next = []
    var newIds = []
    for (var j = 0; j < configured.length; j++) {
      var stored = configured[j]
      var merged = Model.mergeItem(stored, previous[stored.id])
      next.push(merged)
      if (!previous[stored.id]) newIds.push(stored.id)
    }
    hydrating = true
    setItems(next)
    hydrating = false
    if (newIds.length > 0) enqueue(newIds)
  }

  function loadConfig(raw) {
    if (writingConfig) return
    var parsed = Model.parseConfig(raw)
    if (!parsed.apply || (parsed.targets.length === 0 && items.length > 0 && !parsed.emptyList)) {
      if (!configReady) configReady = true
      return
    }
    applyTargets(parsed.targets)
    configReady = true
    lastWrittenConfig = Model.serializeConfig(items)
  }

  function persist() {
    if (hydrating || !configReady) return
    persistTimer.restart()
  }

  function flushConfig() {
    if (hydrating || !configReady) return
    var text = Model.serializeConfig(items)
    if (text === lastWrittenConfig) return
    writingConfig = true
    lastWrittenConfig = text
    configFile.setText(text)
  }

  function addTarget(name, url) {
    var parsed = Model.normalizeTarget(name, url)
    if (!parsed.ok) return parsed.error
    if (findByUrl(parsed.url)) return "Already tracking this URL"
    setItems(items.concat([Model.blankItem(parsed)]))
    persist()
    enqueue([parsed.id])
    return ""
  }

  function updateTarget(id, name, url) {
    var index = findIndex(id)
    if (index < 0) return "Site not found"
    var parsed = Model.normalizeTarget(name, url)
    if (!parsed.ok) return parsed.error
    var duplicate = findByUrl(parsed.url)
    if (duplicate && duplicate.id !== id) return "Already tracking this URL"
    var current = items[index]
    var urlChanged = current.url !== parsed.url
    var nameChanged = current.name !== parsed.name
    if (!urlChanged && !nameChanged) return ""
    var fields = { name: parsed.name, url: parsed.url }
    if (urlChanged) {
      fields.status = "unknown"
      fields.checking = false
      fields.httpCode = 0
      fields.error = ""
    }
    patchItem(id, fields)
    persist()
    if (urlChanged) enqueue([id])
    return ""
  }

  function removeTarget(id) {
    var next = []
    for (var i = 0; i < items.length; i++) {
      if (items[i] && items[i].id !== id) next.push(items[i])
    }
    if (next.length === items.length) return
    if (activeId === id) {
      activeId = ""
      checkGeneration++
    }
    var queued = []
    for (var q = 0; q < pendingIds.length; q++) {
      if (pendingIds[q] !== id) queued.push(pendingIds[q])
    }
    pendingIds = queued
    setItems(next)
    persist()
  }

  function moveTarget(id, beforeId) {
    var next = Model.moveInDisplayGroup(items, id, beforeId)
    if (!next) return
    setItems(next)
    persist()
  }

  function enqueue(ids) {
    var queued = pendingIds.slice()
    for (var i = 0; i < ids.length; i++) {
      if (queued.indexOf(ids[i]) === -1) queued.push(ids[i])
    }
    pendingIds = queued
    pump()
  }

  function refresh() {
    checkGeneration++
    pendingIds = []
    checkAfterProbe = true
    probeConnectivity(true)
  }

  function probeConnectivity(forceCheck) {
    if (connectivityProc.running) {
      connectivityPending = true
      if (forceCheck) {
        checkAfterProbe = true
        connectivityForceCheck = true
      }
      return
    }
    connectivityPending = false
    connectivityForceCheck = forceCheck === true
    connectivityStep = "nmcli"
    connectivityProc.command = connectivityForceCheck
      ? ["nmcli", "networking", "connectivity", "check"]
      : ["nmcli", "-t", "-f", "CONNECTIVITY", "g"]
    connectivityProc.running = true
  }

  function finishConnectivity(text, exitCode) {
    if (connectivityPending) {
      var force = connectivityForceCheck
      probeConnectivity(force)
      return
    }
    var trimmed = String(text || "").trim()
    if (connectivityStep === "nmcli") {
      var key = Model.nmConnectivity(trimmed)
      if (exitCode === 0 && key !== "") {
        applyConnectivityState(Model.isOfflineNmState(key))
        return
      }
      connectivityStep = "ip4"
      connectivityProc.command = ["ip", "route", "show", "default"]
      connectivityProc.running = true
      return
    }
    if (connectivityStep === "ip4") {
      if (trimmed !== "") {
        applyConnectivityState(false)
        return
      }
      connectivityStep = "ip6"
      connectivityProc.command = ["ip", "-6", "route", "show", "default"]
      connectivityProc.running = true
      return
    }
    applyConnectivityState(trimmed === "")
  }

  function applyConnectivityState(isOffline) {
    var wantCheck = checkAfterProbe
    checkAfterProbe = false
    if (isOffline) {
      if (!offline) checkGeneration++
      offline = true
      pendingIds = []
      activeId = ""
      passSnapshot = null
      clearChecking()
      return
    }
    var wasOffline = offline
    offline = false
    if (wantCheck || wasOffline) startCheckPass()
  }

  function startCheckPass() {
    passSnapshot = snapshotStatuses()
    passChecks = 0
    passLocalFails = 0
    var ids = []
    for (var i = 0; i < items.length; i++) {
      if (items[i]) ids.push(items[i].id)
    }
    pendingIds = ids
    pump()
  }

  function snapshotStatuses() {
    var snap = []
    for (var i = 0; i < items.length; i++) {
      var item = items[i]
      if (!item) continue
      snap.push({
        id: item.id,
        status: item.status,
        httpCode: item.httpCode,
        error: item.error
      })
    }
    return snap
  }

  function restoreStatuses(snap) {
    if (!snap || snap.length === 0) return
    var byId = {}
    for (var s = 0; s < snap.length; s++) byId[String(snap[s].id)] = snap[s]
    var next = []
    var changed = false
    for (var i = 0; i < items.length; i++) {
      var item = items[i]
      if (!item) {
        next.push(item)
        continue
      }
      var prev = byId[String(item.id)]
      if (!prev) {
        next.push(item)
        continue
      }
      var copy = {}
      for (var key in item) copy[key] = item[key]
      copy.status = prev.status
      copy.httpCode = prev.httpCode
      copy.error = prev.error
      copy.checking = false
      next.push(copy)
      changed = true
    }
    if (changed) setItems(next)
  }

  function concludePass() {
    if (!passSnapshot) return
    var snap = passSnapshot
    passSnapshot = null
    if (passChecks > 0 && passChecks === passLocalFails) {
      restoreStatuses(snap)
      applyConnectivityState(true)
    }
  }

  function clearChecking() {
    var next = []
    var changed = false
    for (var i = 0; i < items.length; i++) {
      var item = items[i]
      if (item && item.checking) {
        var copy = {}
        for (var key in item) copy[key] = item[key]
        copy.checking = false
        next.push(copy)
        changed = true
      } else {
        next.push(item)
      }
    }
    if (changed) setItems(next)
  }

  function pump() {
    if (offline || checkProc.running) return
    while (pendingIds.length > 0) {
      var id = pendingIds.shift()
      var index = findIndex(id)
      if (index < 0) continue
      activeId = id
      activeGeneration = checkGeneration
      var url = items[index].url
      patchItem(id, { checking: true })
      checkProc.command = [
        "curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}",
        "-L", "--max-time", "8", "-A", "omaup/1.0", url
      ]
      checkProc.running = true
      return
    }
    activeId = ""
    concludePass()
  }

  function finishCheck(codeText, exitCode) {
    var id = activeId
    var generation = activeGeneration
    activeId = ""
    var index = findIndex(id)
    if (id === "" || generation !== checkGeneration || index < 0 || offline) {
      Qt.callLater(pump)
      return
    }
    var previous = items[index] ? String(items[index].status || "") : ""
    var result = Model.classifyHttp(codeText, exitCode)
    var localFail = Model.isLocalConnectivityFailure(codeText, exitCode)
    patchItem(id, {
      checking: false,
      status: result.status,
      httpCode: result.httpCode,
      error: result.error
    })
    passChecks++
    if (localFail) passLocalFails++
    else notifyFlip(items[index], previous, result)
    Qt.callLater(pump)
  }

  function notifyFlip(item, previous, result) {
    if (!item || !result) return
    if (previous !== "up" && previous !== "down") return
    if (result.status !== "up" && result.status !== "down") return
    if (previous === result.status) return
    Quickshell.execDetached([
      "omarchy-notification-send",
      "-u", result.status === "down" ? "critical" : "low",
      "-g", "",
      "--app-name", "Omaup",
      item.name,
      result.status === "down" ? (result.error || "Down") : "Back up"
    ])
  }

  function openTarget(item) {
    if (!item || !item.url) return
    Quickshell.execDetached(["omarchy-launch-browser", item.url])
  }

  function reloadTheme() {
    colorsFile.reload()
  }

  Component.onCompleted: {
    colorsFile.reload()
  }

  Timer {
    id: persistTimer
    interval: 200
    repeat: false
    onTriggered: root.flushConfig()
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    blockLoading: true
    printErrors: false
    onLoaded: root.loadConfig(text())
    onLoadFailed: root.loadConfig("")
    onSaved: root.writingConfig = false
    onSaveFailed: root.writingConfig = false
    onFileChanged: if (!root.writingConfig) reload()
  }

  FileView {
    id: colorsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.greenHex = Model.parseGreen(text())
    onLoadFailed: root.greenHex = ""
    onFileChanged: reload()
  }

  Process {
    id: checkProc
    stdout: StdioCollector {
      id: checkOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.finishCheck(checkOut.text, exitCode)
    }
  }

  Process {
    id: connectivityProc
    stdout: StdioCollector {
      id: connectivityOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.finishConnectivity(connectivityOut.text, exitCode)
    }
  }

  Timer {
    interval: Math.max(5, root.refreshIntervalSec) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.probeConnectivity(false)
  }
}
