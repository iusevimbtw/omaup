function parseConfig(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { targets: [] }
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return { targets: [] }
    return { targets: parseTargets(parsed.targets) }
  } catch (e) {
    return { targets: [] }
  }
}

function serializeConfig(items) {
  return JSON.stringify({ targets: persistable(items) }, null, 2) + "\n"
}

function parseTargets(raw) {
  if (!Array.isArray(raw)) return []
  var result = []
  var seen = {}
  for (var i = 0; i < raw.length; i++) {
    var item = normalizeStored(raw[i])
    if (!item || seen[item.id]) continue
    seen[item.id] = true
    result.push(item)
  }
  return result
}

function normalizeStored(raw) {
  if (!raw || typeof raw !== "object") return null
  var url = normalizeUrl(raw.url)
  if (url === "") return null
  var id = String(raw.id || "").trim()
  if (id === "") id = newId()
  var name = String(raw.name || "").trim()
  if (name === "") name = defaultName(url)
  return { id: id, name: name, url: url }
}

function normalizeTarget(name, url) {
  var normalized = normalizeUrl(url)
  if (normalized === "") return { ok: false, error: "Enter a valid http(s) URL" }
  var label = String(name || "").trim()
  if (label === "") label = defaultName(normalized)
  return { ok: true, id: newId(), name: label, url: normalized }
}

function normalizeUrl(raw) {
  var value = String(raw || "").trim()
  if (value === "") return ""
  if (value.indexOf("://") === -1) value = "https://" + value
  if (!/^https?:\/\//i.test(value)) return ""
  if (/\s/.test(value)) return ""
  var rest = value.replace(/^https?:\/\//i, "")
  if (rest === "" || rest.charAt(0) === "/" || rest.charAt(0) === ".") return ""
  return value
}

function defaultName(url) {
  var host = String(url || "").replace(/^https?:\/\//i, "").replace(/\/.*$/, "").replace(/:\d+$/, "")
  return host || "Site"
}

function newId() {
  return "t" + Date.now().toString(36) + "-" + Math.floor(Math.random() * 1e9).toString(36)
}

function blankItem(target) {
  return {
    id: target.id,
    name: target.name,
    url: target.url,
    status: "unknown",
    checking: false,
    httpCode: 0,
    error: ""
  }
}

function mergeItem(stored, previous) {
  var item = blankItem(stored)
  if (!previous) return item
  item.status = previous.status || "unknown"
  item.checking = previous.checking === true
  item.httpCode = Number(previous.httpCode || 0)
  item.error = String(previous.error || "")
  return item
}

function persistable(items) {
  var result = []
  if (!Array.isArray(items)) return result
  for (var i = 0; i < items.length; i++) {
    var item = items[i]
    if (!item) continue
    result.push({ id: item.id, name: item.name, url: item.url })
  }
  return result
}

function parseGreen(raw) {
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*green\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (match) return match[1]
  }
  return ""
}

function classifyHttp(codeText, exitCode) {
  var code = parseInt(String(codeText || "").trim(), 10)
  if (!isFinite(code)) code = 0
  if (code >= 200 && code < 300) {
    return { status: "up", httpCode: code, error: "" }
  }
  if (code > 0) {
    return { status: "down", httpCode: code, error: String(code) }
  }
  if (Number(exitCode) === 28) {
    return { status: "down", httpCode: 0, error: "Timeout" }
  }
  return { status: "down", httpCode: 0, error: "Unreachable" }
}

function caption(item) {
  if (!item) return ""
  if (item.checking && item.status === "unknown") return "Checking…"
  if (item.error) return item.error
  if (item.httpCode) return String(item.httpCode)
  if (item.checking) return "Checking…"
  return "Waiting…"
}

function downSites(items) {
  var down = []
  if (!Array.isArray(items)) return down
  for (var i = 0; i < items.length; i++) {
    if (items[i] && items[i].status === "down") down.push(items[i])
  }
  return down
}

function onlineSites(items) {
  var rest = []
  if (!Array.isArray(items)) return rest
  for (var i = 0; i < items.length; i++) {
    if (items[i] && items[i].status !== "down") rest.push(items[i])
  }
  return rest
}

function displaySites(items) {
  return downSites(items).concat(onlineSites(items))
}

function inStatusGroup(item, down) {
  if (!item) return false
  return down ? item.status === "down" : item.status !== "down"
}

function moveInDisplayGroup(items, id, beforeId) {
  if (!Array.isArray(items)) return null
  var needle = String(id || "")
  if (needle === "") return null
  var from = -1
  for (var i = 0; i < items.length; i++) {
    if (items[i] && String(items[i].id || "") === needle) {
      from = i
      break
    }
  }
  if (from < 0) return null
  var down = items[from].status === "down"
  var group = []
  for (var j = 0; j < items.length; j++) {
    if (inStatusGroup(items[j], down)) group.push(items[j])
  }
  var moved = null
  var rest = []
  for (var g = 0; g < group.length; g++) {
    if (String(group[g].id || "") === needle) moved = group[g]
    else rest.push(group[g])
  }
  if (!moved) return null
  var before = String(beforeId || "")
  var insertAt = rest.length
  if (before !== "") {
    for (var r = 0; r < rest.length; r++) {
      if (String(rest[r].id || "") === before) {
        insertAt = r
        break
      }
    }
  }
  rest.splice(insertAt, 0, moved)
  var same = group.length === rest.length
  if (same) {
    for (var k = 0; k < group.length; k++) {
      if (String(group[k].id || "") !== String(rest[k].id || "")) {
        same = false
        break
      }
    }
  }
  if (same) return null
  var next = []
  var used = 0
  for (var n = 0; n < items.length; n++) {
    if (inStatusGroup(items[n], down)) next.push(rest[used++])
    else next.push(items[n])
  }
  return next
}

function countBy(items, key, value) {
  var n = 0
  if (!Array.isArray(items)) return 0
  for (var i = 0; i < items.length; i++) {
    if (items[i] && items[i][key] === value) n++
  }
  return n
}

function heroMeta(items) {
  var down = countBy(items, "status", "down")
  if (down === 1) return "1 down"
  if (down > 1) return down + " down"
  if (Array.isArray(items) && items.length === 0) return "No sites yet"
  if (countBy(items, "status", "up") > 0) return "All systems good"
  return "Waiting for checks"
}

function nmConnectivity(raw) {
  var key = String(raw || "").trim().toLowerCase()
  if (key === "none" || key === "full" || key === "limited" || key === "portal" || key === "unknown") return key
  return ""
}

function isOfflineNmState(key) {
  return key === "none" || key === "limited" || key === "portal"
}

function isLocalConnectivityFailure(codeText, exitCode) {
  var code = parseInt(String(codeText || "").trim(), 10)
  if (isFinite(code) && code > 0) return false
  var exit = Number(exitCode)
  return exit === 6 || exit === 7
}
