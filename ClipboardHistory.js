var maxHistoryFileBytes = 4 * 1024 * 1024
var maxHistoryEntries = 300
var maxEntryTextLength = 1024 * 1024
var maxAggregateTextLength = 4 * 1024 * 1024
var maxImagePathLength = 4096
var maxCapturedAtLength = 64
var allowedImageMimes = {
  "image/png": true,
  "image/jpeg": true,
  "image/webp": true,
  "image/gif": true,
  "image/bmp": true,
  "image/tiff": true
}

function utf8ByteLength(value) {
  var text = String(value === undefined || value === null ? "" : value)
  var bytes = 0

  for (var i = 0; i < text.length; i++) {
    var code = text.charCodeAt(i)
    if (code <= 0x7f) {
      bytes += 1
    } else if (code <= 0x7ff) {
      bytes += 2
    } else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
      var next = text.charCodeAt(i + 1)
      if (next >= 0xdc00 && next <= 0xdfff) {
        bytes += 4
        i += 1
      } else {
        bytes += 3
      }
    } else {
      bytes += 3
    }
  }

  return bytes
}

var colorNumberPattern = "[+-]?(?:\\d*\\.\\d+|\\d+)(?:e[+-]?\\d+)?"
var colorComponentPattern = new RegExp("^(" + colorNumberPattern + ")(%?)$", "i")
var colorHuePattern = new RegExp("^(" + colorNumberPattern + ")(deg|rad|grad|turn)?$", "i")

function colorComponent(token, scale, percentOnly) {
  var match = token.match(colorComponentPattern)
  if (!match || (percentOnly && !match[2])) return NaN
  var value = Number(match[1])
  var maximum = match[2] ? 100 : scale
  if (!isFinite(value) || value < 0 || value > maximum) return NaN
  return value / maximum
}

function parseColor(text) {
  var value = String(text || "").trim()
  var hex = value.match(/^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i)
    || value.match(/^([0-9a-f]{6}(?:[0-9a-f]{2})?)$/i)
  if (hex) {
    var digits = hex[1]
    if (digits.length <= 4) {
      var expanded = ""
      for (var i = 0; i < digits.length; i++) expanded += digits.charAt(i) + digits.charAt(i)
      digits = expanded
    }
    return {
      red: parseInt(digits.slice(0, 2), 16) / 255,
      green: parseInt(digits.slice(2, 4), 16) / 255,
      blue: parseInt(digits.slice(4, 6), 16) / 255,
      alpha: digits.length === 8 ? parseInt(digits.slice(6, 8), 16) / 255 : 1
    }
  }

  var call = value.match(/^(rgba?|hsla?)\(([^()]*)\)$/i)
  if (!call) return null
  var rgb = call[1].toLowerCase().indexOf("rgb") === 0
  var body = call[2].trim()
  var legacy = body.indexOf(",") >= 0
  var channels
  var alphaToken
  if (legacy) {
    if (body.indexOf("/") >= 0) return null
    channels = body.split(",")
    if (channels.length !== 3 && channels.length !== 4) return null
    for (var j = 0; j < channels.length; j++) channels[j] = channels[j].trim()
    if (channels.length === 4) alphaToken = channels.pop()
    if (rgb) {
      var percentages = channels[0].indexOf("%") >= 0
      if ((channels[1].indexOf("%") >= 0) !== percentages
          || (channels[2].indexOf("%") >= 0) !== percentages) return null
    }
  } else {
    var slash = body.split("/")
    if (slash.length > 2) return null
    channels = slash[0].trim().split(/\s+/)
    if (channels.length !== 3) return null
    if (slash.length === 2) alphaToken = slash[1].trim()
  }

  var alpha = alphaToken === undefined ? 1 : colorComponent(alphaToken, 1, false)
  if (isNaN(alpha)) return null
  if (rgb) {
    var red = colorComponent(channels[0], 255, false)
    var green = colorComponent(channels[1], 255, false)
    var blue = colorComponent(channels[2], 255, false)
    if (isNaN(red) || isNaN(green) || isNaN(blue)) return null
    return { red: red, green: green, blue: blue, alpha: alpha }
  }

  var hueMatch = channels[0].match(colorHuePattern)
  var saturation = colorComponent(channels[1], 100, true)
  var lightness = colorComponent(channels[2], 100, true)
  if (!hueMatch || isNaN(saturation) || isNaN(lightness)) return null
  var hue = Number(hueMatch[1])
  if (!isFinite(hue)) return null
  var unit = String(hueMatch[2] || "deg").toLowerCase()
  var period = unit === "turn" ? 1 : unit === "rad" ? Math.PI * 2 : unit === "grad" ? 400 : 360
  // Reduce before scaling so a finite, very large hue cannot overflow.
  hue = ((hue % period) + period) % period / period * 6
  var chroma = 2 * Math.min(lightness, 1 - lightness) * saturation
  var secondary = chroma * (1 - Math.abs(hue % 2 - 1))
  var offset = lightness - chroma / 2
  var sector = Math.floor(hue)
  return {
    red: offset + (sector === 0 || sector === 5 ? chroma : sector === 1 || sector === 4 ? secondary : 0),
    green: offset + (sector === 1 || sector === 2 ? chroma : sector === 0 || sector === 3 ? secondary : 0),
    blue: offset + (sector === 3 || sector === 4 ? chroma : sector === 2 || sector === 5 ? secondary : 0),
    alpha: alpha
  }
}

function colorHex(color) {
  var result = "#"
  var channels = [color.red, color.green, color.blue]
  if (color.alpha < 1) channels.push(color.alpha)
  for (var i = 0; i < channels.length; i++) {
    var byte = Math.round(channels[i] * 255).toString(16).toUpperCase()
    result += byte.length < 2 ? "0" + byte : byte
  }
  return result
}

function detectColor(text) {
  var color = parseColor(text)
  return color ? colorHex(color) : ""
}

function colorNumber(value) {
  return String(Number(value.toPrecision(6)))
}

function colorDetails(text) {
  var color = parseColor(text)
  if (!color) return null
  var maximum = Math.max(color.red, color.green, color.blue)
  var minimum = Math.min(color.red, color.green, color.blue)
  var delta = maximum - minimum
  var lightness = (maximum + minimum) / 2
  var saturation = delta === 0 ? 0 : delta / (lightness <= 0.5
    ? maximum + minimum : (1 - maximum) + (1 - minimum))
  var hue = 0
  if (delta !== 0) {
    if (maximum === color.red) hue = (color.green - color.blue) / delta
    else if (maximum === color.green) hue = (color.blue - color.red) / delta + 2
    else hue = (color.red - color.green) / delta + 4
    hue = ((hue * 60) + 360) % 360
  }
  var translucent = color.alpha < 1
  var alpha = translucent ? ", " + colorNumber(color.alpha) : ""
  color.hex = colorHex(color)
  color.rgb = (translucent ? "rgba(" : "rgb(")
    + colorNumber(color.red * 255) + ", " + colorNumber(color.green * 255) + ", "
    + colorNumber(color.blue * 255) + alpha + ")"
  color.hsl = (translucent ? "hsla(" : "hsl(")
    + colorNumber(hue) + ", " + colorNumber(saturation * 100) + "%, "
    + colorNumber(lightness * 100) + "%" + alpha + ")"
  return color
}

function oversizedTextResult(length, preserveOversized) {
  if (!preserveOversized)
    return { status: "oversized", entry: null, textLength: 0, containsOversized: true }

  return {
    status: "ok",
    entry: {
      type: "text",
      text: "",
      oversized: true,
      originalLength: length
    },
    textLength: 0,
    containsOversized: true
  }
}

function checkedEntry(value, preserveOversized, acceptPlaceholder) {
  var text
  if (typeof value === "string") {
    text = value
    if (text.length > maxEntryTextLength) return oversizedTextResult(text.length, preserveOversized)
    if (text.trim().length === 0)
      return { status: "invalid", entry: null, textLength: 0, containsOversized: false }
    return {
      status: "ok",
      entry: { type: "text", text: text, color: detectColor(text) },
      textLength: text.length,
      containsOversized: false
    }
  }

  if (!value || typeof value !== "object")
    return { status: "invalid", entry: null, textLength: 0, containsOversized: false }
  var type = typeof value.type === "string" ? value.type : (typeof value.kind === "string" ? value.kind : "")

  if (type === "text") {
    if (value.oversized === true) {
      if (!acceptPlaceholder)
        return { status: "invalid", entry: null, textLength: 0, containsOversized: false }
      var originalLength = Number(value.originalLength)
      if (!isFinite(originalLength)
          || Math.floor(originalLength) !== originalLength
          || originalLength <= maxEntryTextLength
          || originalLength > maxHistoryFileBytes)
        return { status: "invalid", entry: null, textLength: 0, containsOversized: false }
      return oversizedTextResult(originalLength, preserveOversized)
    }

    if (typeof value.text !== "string")
      return { status: "invalid", entry: null, textLength: 0, containsOversized: false }
    text = value.text
    if (text.length > maxEntryTextLength) return oversizedTextResult(text.length, preserveOversized)
    if (text.trim().length === 0)
      return { status: "invalid", entry: null, textLength: 0, containsOversized: false }
    return {
      status: "ok",
      entry: { type: "text", text: text, color: detectColor(text) },
      textLength: text.length,
      containsOversized: false
    }
  }

  if (type === "image") {
    if (typeof value.path !== "string")
      return { status: "invalid", entry: null, textLength: 0, containsOversized: false }
    var path = value.path
    if (!path || path.length > maxImagePathLength || path.charAt(0) !== "/" || /[\u0000\r\n]/.test(path))
      return { status: "invalid", entry: null, textLength: 0, containsOversized: false }

    var mime = value.mime === undefined || value.mime === null || value.mime === "" ? "image/png" : value.mime
    if (typeof mime !== "string" || !allowedImageMimes[mime])
      return { status: "invalid", entry: null, textLength: 0, containsOversized: false }

    var entry = { type: "image", path: path, mime: mime }
    if (value.capturedAt !== undefined && value.capturedAt !== null) {
      if (typeof value.capturedAt !== "string"
          || value.capturedAt.length > maxCapturedAtLength
          || /[\u0000\r\n]/.test(value.capturedAt))
        return { status: "invalid", entry: null, textLength: 0, containsOversized: false }
      entry.capturedAt = value.capturedAt
    }
    return { status: "ok", entry: entry, textLength: 0, containsOversized: false }
  }

  return { status: "invalid", entry: null, textLength: 0, containsOversized: false }
}

function normalizeEntry(value) {
  var result = checkedEntry(value, true, true)
  return result.status === "ok" ? result.entry : null
}

function entryKey(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "image:" + String(entry.path || "")
  return "text:" + String(entry.text || "")
}

function historyResult(status, entries, truncated, containsOversized) {
  return {
    status: status,
    entries: entries || [],
    truncated: !!truncated,
    containsOversized: !!containsOversized
  }
}

function normalizedEntryLimit(limit) {
  var max = limit === undefined || limit === null ? maxHistoryEntries : Number(limit)
  if (isNaN(max)) max = maxHistoryEntries
  return Math.min(maxHistoryEntries, Math.max(0, Math.floor(max)))
}

function validateHistory(history, limit, acceptPlaceholders) {
  if (!Array.isArray(history)) return historyResult("invalid", [])

  var max = normalizedEntryLimit(limit)
  var count = Math.min(history.length, max)
  var aggregateTextLength = 0
  var containsOversized = false
  var entries = []
  var canAcceptPlaceholders = acceptPlaceholders !== false

  for (var i = 0; i < count; i++) {
    var result = checkedEntry(history[i], true, canAcceptPlaceholders)
    if (result.status !== "ok") return historyResult(result.status, [])
    if (result.textLength > maxAggregateTextLength - aggregateTextLength)
      return historyResult("oversized", [])
    aggregateTextLength += result.textLength
    containsOversized = containsOversized || result.containsOversized
    entries.push(result.entry)
  }

  return historyResult("ok", entries, history.length > max, containsOversized)
}

function parseHistory(raw) {
  var source = String(raw || "[]")
  if (utf8ByteLength(source) > maxHistoryFileBytes) return historyResult("oversized", [])

  try {
    var parsed = JSON.parse(source)
    return validateHistory(parsed, maxHistoryEntries, false)
  } catch (e) {
    return historyResult("invalid", [])
  }
}

function addEntry(history, entry, limit) {
  var current = validateHistory(history, limit)
  if (current.status !== "ok") return current
  if (current.containsOversized)
    return historyResult("oversized", current.entries, current.truncated, true)

  var added = checkedEntry(entry, false, false)
  if (added.status !== "ok")
    return historyResult(added.status, current.entries, current.truncated)

  var max = normalizedEntryLimit(limit)
  if (max === 0) return historyResult("ok", [])

  var key = entryKey(added.entry)
  var next = [added.entry]
  var aggregateTextLength = added.textLength

  for (var i = 0; i < current.entries.length && next.length < max; i++) {
    var existing = checkedEntry(current.entries[i], false, true)
    if (existing.status !== "ok")
      return historyResult(existing.status, current.entries, current.truncated)
    if (entryKey(existing.entry) === key) continue
    if (existing.textLength > maxAggregateTextLength - aggregateTextLength)
      return historyResult("oversized", current.entries, current.truncated)
    aggregateTextLength += existing.textLength
    next.push(existing.entry)
  }

  return historyResult("ok", next, current.truncated || i < current.entries.length)
}

function serializeHistory(history, limit, trailingNewlines) {
  var validated = validateHistory(history, limit)
  if (validated.status !== "ok" || validated.containsOversized) {
    return {
      status: validated.status === "ok" ? "oversized" : validated.status,
      text: "",
      truncated: validated.truncated,
      containsOversized: validated.containsOversized
    }
  }

  var stored = []
  for (var i = 0; i < validated.entries.length; i++) {
    var entry = validated.entries[i]
    if (entry.type === "text") {
      stored.push({ type: "text", text: entry.text })
      continue
    }

    var image = { type: "image", path: entry.path, mime: entry.mime }
    if (entry.capturedAt !== undefined) image.capturedAt = entry.capturedAt
    stored.push(image)
  }

  var suffix = Number(trailingNewlines) === 2 ? "\n\n" : "\n"
  var text = JSON.stringify(stored, null, 2) + suffix
  if (utf8ByteLength(text) > maxHistoryFileBytes)
    return { status: "oversized", text: "", truncated: validated.truncated, containsOversized: false }

  return { status: "ok", text: text, truncated: validated.truncated, containsOversized: false }
}

function historiesEqual(left, right) {
  if (!Array.isArray(left) || !Array.isArray(right) || left.length !== right.length) return false

  for (var i = 0; i < left.length; i++) {
    var leftResult = checkedEntry(left[i], true, true)
    var rightResult = checkedEntry(right[i], true, true)
    if (leftResult.status !== "ok" || rightResult.status !== "ok") return false

    var leftEntry = leftResult.entry
    var rightEntry = rightResult.entry
    if (leftEntry.type !== rightEntry.type) return false
    if (leftEntry.type === "text") {
      if (!!leftEntry.oversized !== !!rightEntry.oversized) return false
      if (leftEntry.oversized) {
        if (leftEntry.originalLength !== rightEntry.originalLength) return false
      } else if (leftEntry.text !== rightEntry.text) {
        return false
      }
    } else if (leftEntry.path !== rightEntry.path
        || leftEntry.mime !== rightEntry.mime
        || String(leftEntry.capturedAt || "") !== String(rightEntry.capturedAt || "")) {
      return false
    }
  }

  return true
}

function historyWriteDisposition(result, expected, reportedSaved, failed) {
  if (!reportedSaved && !failed) return "pending"
  if (reportedSaved
      && !failed
      && result
      && result.status === "ok"
      && historiesEqual(result.entries, expected))
    return "confirmed"
  return "failed"
}

function removeEntryAt(history, index) {
  var values = Array.isArray(history) ? history : []
  var target = Number(index)
  if (isNaN(target) || target < 0 || target >= values.length) return values.slice()

  var next = values.slice()
  next.splice(target, 1)
  return next
}

function clearHistory() {
  return []
}

function searchableText(entry) {
  if (!entry || entry.oversized) return ""
  if (entry.type === "image") return "image screenshot " + String(entry.mime || "") + " " + String(entry.capturedAt || "")
  return String(entry.text || "") + " " + fileEntryText(entry) + " " + String(entry.color || "")
}

function decodeFileUri(uri) {
  var value = String(uri || "").trim()
  if (value.indexOf("file://") !== 0) return ""

  var path = value.substring(7)
  if (path.indexOf("localhost/") === 0) path = path.substring(9)
  if (path.charAt(0) !== "/") return ""

  try { return decodeURIComponent(path) } catch (e) { return path }
}

function filePaths(entry) {
  if (!entry || entry.type !== "text") return []

  var lines = String(entry.text || "").split(/\r?\n/)
  var paths = []
  for (var i = 0; i < lines.length; i++) {
    var path = decodeFileUri(lines[i])
    if (path) paths.push(path)
  }
  return paths
}

function fileName(path) {
  var parts = String(path || "").split("/")
  return parts.length > 0 ? parts[parts.length - 1] : String(path || "")
}

function isImagePath(path) {
  return /\.(png|jpe?g|webp|gif|bmp|tiff?)$/i.test(String(path || ""))
}

function fileEntryText(entry) {
  var paths = filePaths(entry)
  if (paths.length === 0) return ""
  if (paths.length === 1) return fileName(paths[0])
  return paths.length + " files"
}

function imagePreviewText(entry) {
  var timestamp = String(entry && entry.capturedAt || "")
  if (!timestamp) return "Image"

  var label = String(entry && entry.mime || "") === "image/png" ? "Screenshot" : "Image"
  return label + " from " + timestamp
}
function oversizedTextLabel(entry) {
  return "Oversized text (" + String(entry.originalLength || 0) + " characters) — paste or copy only"
}


function previewText(entry) {
  if (!entry) return ""
  if (entry.oversized) return oversizedTextLabel(entry)
  if (entry.type === "image") return imagePreviewText(entry)
  var fileText = fileEntryText(entry)
  if (fileText) return fileText
  return String(entry.text || "").replace(/\s+/g, " ")
}

function fullText(entry) {
  if (!entry) return ""
  if (entry.oversized) return oversizedTextLabel(entry)
  var paths = filePaths(entry)
  if (paths.length > 0) return paths.join("\n")
  return String(entry.text || "")
}

// Search and ordinary previews only need a bounded prefix. Expanded previews
// and the editor retrieve the selected entry lazily by history index.
var displayTextLimit = 8192

function cappedEntry(entry) {
  if (!entry || entry.type !== "text" || entry.text.length <= displayTextLimit) return entry

  var cut = entry.text.lastIndexOf("\n", displayTextLimit)
  return {
    type: "text",
    text: entry.text.slice(0, cut > 0 ? cut : displayTextLimit),
    color: entry.color || ""
  }
}

function linkDomain(text) {
  var source = String(text || "")
  if (source.length > displayTextLimit) return ""
  var value = source.trim()
  if (!value || /[\s\u0000-\u001f\u007f"'<>\\]/.test(value)) return ""

  // Match complete values, not the URL fragments the packaged opener can find
  // inside prose. Keep bare-domain recognition compatible with that helper.
  var url = value.match(/^https?:\/\/([^/?#]+)(?:[/?#].*)?$/)
  if (!url) {
    var bare = value.match(/^([a-z0-9][a-z0-9.-]+\.[a-z]{2,})(?:\/.*)?$/i)
    return bare ? bare[1].toLowerCase() : ""
  }

  var authority = url[1]
  var host = authority.slice(authority.lastIndexOf("@") + 1)
  var domain = host.charAt(0) === "["
    ? host.match(/^(\[[0-9a-f:.]+\])(?::[0-9]+)?$/i)
    : host.match(/^([^:\[\]]+)(?::[0-9]+)?$/)
  return domain ? domain[1].toLowerCase() : ""
}

function normalizedTypeFilter(value) {
  var filter = String(value || "all").toLowerCase()
  return filter === "text" || filter === "links" || filter === "images" || filter === "colors" ? filter : "all"
}

// Prepare one bounded snapshot per history change. Searching it must not recount
// complete payloads or derive metadata from the truncated preview.
function prepareRows(history) {
  var values = Array.isArray(history) ? history : []
  var count = Math.min(values.length, maxHistoryEntries)

  var rows = []

  for (var i = 0; i < count; i++) {
    var normalized = normalizeEntry(values[i])
    if (!normalized) continue
    var entry = cappedEntry(normalized)

    var paths = filePaths(entry)
    var isFile = paths.length > 0
    var allPaths = isFile && entry !== normalized ? filePaths(normalized) : paths
    var isImage = entry.type === "image"
    var isOversized = entry.type === "text" && entry.oversized === true
    var isImageFile = isFile && allPaths.length === 1 && isImagePath(paths[0])
    var color = entry.type === "text" && !isOversized ? String(entry.color || "") : ""
    var domain = !isImage && !isOversized && !isFile && !color ? linkDomain(normalized.text) : ""

    var previewPath = isImage ? String(entry.path || "") : (isImageFile ? paths[0] : "")
    var wordCount = null
    var lineCount = null
    if (!isImage && !isOversized && !isFile) {
      wordCount = 0
      lineCount = 1
      var words = /\S+/g
      var breaks = /\r\n|[\r\n\u2028\u2029]/g
      while (words.test(normalized.text)) wordCount++
      while (breaks.test(normalized.text)) lineCount++
    }
    var directory = ""
    for (var j = 0; j < allPaths.length; j++) {
      var parent = allPaths[j].slice(0, allPaths[j].lastIndexOf("/")) || "/"
      if (j === 0) directory = parent
      else if (parent !== directory) {
        directory = ""
        break
      }
    }
    rows.push({
      entryType: isOversized ? "oversized" : (color ? "color" : (isFile ? "file" : (domain ? "link" : entry.type))),
      fullText: isImage ? "" : fullText(entry),
      previewText: isFile ? (allPaths.length === 1 ? fileName(paths[0]) : allPaths.length + " files") : previewText(entry),
      previewImage: previewPath,
      color: color,
      colorDetails: color ? colorDetails(normalized.text) : null,
      path: isImage ? String(entry.path || "") : (isFile && allPaths.length === 1 ? paths[0] : ""),
      mime: isImage ? String(entry.mime || "image/png") : "text/plain",
      searchText: searchableText(entry).toLowerCase(),
      wordCount: wordCount,
      lineCount: lineCount,
      fileCount: allPaths.length,
      directory: directory.slice(0, displayTextLimit),
      linkDomain: domain,
      index: i
    })
  }

  return rows
}

function displayRows(preparedRows, query, limit, typeFilter) {
  var values = Array.isArray(preparedRows) ? preparedRows : []
  var needle = String(query || "").trim().toLowerCase()
  var filter = normalizedTypeFilter(typeFilter)
  var max = limit === undefined || limit === null ? 50 : Number(limit)
  if (isNaN(max)) max = 50
  max = Math.max(0, max)
  if (max === 0) return []

  var rows = []
  for (var i = 0; i < values.length; i++) {
    var row = values[i]
    if (needle && row.searchText.indexOf(needle) < 0) continue
    if (filter === "colors" && !row.color) continue
    if (filter === "links" && row.entryType !== "link") continue
    if (filter === "images" && !row.previewImage) continue
    if (filter === "text" && (row.previewImage || row.color || row.entryType === "link")) continue
    rows.push(row)
    if (rows.length >= max) break
  }
  return rows
}

function findTextIndex(history, text) {
  var values = Array.isArray(history) ? history : []
  var target = String(text || "")
  for (var i = 0; i < values.length; i++) {
    var entry = normalizeEntry(values[i])
    if (entry && entry.type === "text" && !entry.oversized && entry.text === target) return i
  }
  return -1
}

function entryText(history, index) {
  var values = Array.isArray(history) ? history : []
  var target = Number(index)
  if (isNaN(target) || target < 0 || target >= values.length) return ""
  var entry = normalizeEntry(values[target])
  return entry && entry.type === "text" && !entry.oversized ? String(entry.text || "") : ""
}

function textPreview(history, index, limit) {
  var text = entryText(history, index)
  var max = Number(limit)
  if (isNaN(max) || max <= 0 || text.length <= max)
    return { text: text, truncated: false, totalLength: text.length }

  return { text: text.slice(0, max), truncated: true, totalLength: text.length }
}

if (typeof module !== "undefined") {
  module.exports = {
    maxHistoryFileBytes: maxHistoryFileBytes,
    maxHistoryEntries: maxHistoryEntries,
    maxEntryTextLength: maxEntryTextLength,
    maxAggregateTextLength: maxAggregateTextLength,
    maxImagePathLength: maxImagePathLength,
    maxCapturedAtLength: maxCapturedAtLength,
    utf8ByteLength: utf8ByteLength,
    detectColor: detectColor,
    colorDetails: colorDetails,
    parseHistory: parseHistory,
    validateHistory: validateHistory,
    addEntry: addEntry,
    serializeHistory: serializeHistory,
    historiesEqual: historiesEqual,
    historyWriteDisposition: historyWriteDisposition,
    removeEntryAt: removeEntryAt,
    findTextIndex: findTextIndex,
    clearHistory: clearHistory,
    searchableText: searchableText,
    previewText: previewText,
    imagePreviewText: imagePreviewText,
    filePaths: filePaths,
    fileEntryText: fileEntryText,
    fullText: fullText,
    prepareRows: prepareRows,
    displayRows: displayRows,
    entryText: entryText,
    textPreview: textPreview
  }
}
