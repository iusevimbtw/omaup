import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var bar: null
  property var settings: ({})
  property string moduleName: "iusevimbtw.omaup"

  property var items: []
  property int itemsRevision: 0
  property string greenHex: ""
  property var pendingIds: []
  property string activeId: ""
  property int checkGeneration: 0
  property int activeGeneration: 0
  property bool hydrating: false
  property bool configFileReady: false
  property bool persistAfterMkdir: false

  readonly property string configDir: {
    var xdg = String(Quickshell.env("XDG_CONFIG_HOME") || "")
    var home = String(Quickshell.env("HOME") || "")
    var base = xdg !== "" ? xdg : (home + "/.config")
    return base + "/omaup"
  }
  readonly property string configPath: configDir + "/config.json"
  readonly property color themeGreen: greenHex !== "" ? greenHex : Color.accent
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property int targetCount: { itemsRevision; return Array.isArray(items) ? items.length : 0 }
  readonly property int downCount: { itemsRevision; return Model.countBy(items, "status", "down") }
  readonly property int upCount: { itemsRevision; return Model.countBy(items, "status", "up") }
  readonly property string heroMeta: { itemsRevision; return Model.heroMeta(items) }
  readonly property color overallColor: {
    itemsRevision
    if (downCount > 0) return Color.urgent
    if (upCount > 0) return themeGreen
    return Color.foreground
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
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
    applyTargets(Model.parseConfig(raw).targets)
    configFileReady = true
    migrateLegacyTargets()
  }

  function migrateLegacyTargets() {
    if (!configFileReady || items.length > 0) return
    var legacy = Model.parseTargets(settings ? settings.targets : [])
    if (legacy.length === 0) return
    applyTargets(legacy)
    persist()
    clearLegacyTargets()
  }

  function clearLegacyTargets() {
    if (!settings || !Array.isArray(settings.targets) || settings.targets.length === 0) return
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") return
    var entry = { id: moduleName }
    for (var key in settings) if (key !== "id" && key !== "targets") entry[key] = settings[key]
    bar.shell.updateEntryInline(moduleName, entry)
  }

  function persist() {
    if (hydrating) return
    persistAfterMkdir = true
    ensureDirProc.command = ["mkdir", "-p", root.configDir]
    if (!ensureDirProc.running) ensureDirProc.running = true
  }

  function writeConfig() {
    persistAfterMkdir = false
    configFile.setText(Model.serializeConfig(items))
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
    var ids = []
    for (var i = 0; i < items.length; i++) {
      if (items[i]) ids.push(items[i].id)
    }
    pendingIds = ids
    pump()
  }

  function pump() {
    if (checkProc.running) return
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
  }

  function finishCheck(codeText, exitCode) {
    var id = activeId
    var generation = activeGeneration
    activeId = ""
    if (id === "" || generation !== checkGeneration || findIndex(id) < 0) {
      Qt.callLater(pump)
      return
    }
    var result = Model.classifyHttp(codeText, exitCode)
    patchItem(id, {
      checking: false,
      status: result.status,
      httpCode: result.httpCode,
      error: result.error
    })
    Qt.callLater(pump)
  }

  function openTarget(item) {
    if (!item || !item.url) return
    Quickshell.execDetached(["omarchy-launch-browser", item.url])
  }

  function reloadTheme() {
    colorsFile.reload()
  }

  onSettingsChanged: migrateLegacyTargets()
  Component.onCompleted: {
    ensureDirProc.command = ["mkdir", "-p", root.configDir]
    ensureDirProc.running = true
    colorsFile.reload()
  }

  Process {
    id: ensureDirProc
    onExited: {
      if (root.persistAfterMkdir) root.writeConfig()
      else configFile.reload()
    }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadConfig(text())
    onLoadFailed: root.loadConfig("")
    onFileChanged: reload()
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

  Timer {
    interval: Math.max(5, root.refreshIntervalSec) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
