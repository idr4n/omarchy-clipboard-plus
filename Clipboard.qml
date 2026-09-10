import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool opened: false
  property string filterText: ""
  property string typeFilter: "all"
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool clearConfirmOpen: false
  property bool previewExpanded: false
  property bool editorOpen: false
  property string editorError: ""
  property string editorAcceptedText: ""
  property bool editorTextGuardActive: false
  property bool doubleHistoryWriteNewline: false
  property bool pendingEditedCopyOnly: false
  property bool pendingEditedAction: false
  property bool pendingEditedSave: false
  property bool historyWritePending: false
  property bool historyWriteReportedSaved: false
  property bool historyWriteFailed: false
  property var historyWriteExpected: null
  property var history: []
  readonly property var preparedHistory: ClipboardHistory.prepareRows(root.history)
  property string historyStatus: "loading"
  property bool historyContainsOversized: false
  property string historyError: ""
  property bool historyReadInFlight: false
  property bool historyReadPending: false
  property bool historyReadTimedOut: false

  property string expandedKind: ""
  property string expandedText: ""
  property string expandedImage: ""
  property var expandedColor: null
  property bool expandedTruncated: false
  property int expandedTotalLength: 0

  property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int headerHeight: Math.max(Style.space(38), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int footerHeight: Math.max(Style.space(28), Style.font.caption + Style.spacing.controlPaddingY)
  property int cardWidth: Math.min(Style.space(940), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(64), Style.font.title + Style.font.caption + Style.space(24))
  readonly property int historyLimit: ClipboardHistory.maxHistoryEntries
  property int displayLimit: 60

  readonly property var typeFilters: ["all", "text", "links", "images", "colors"]
  readonly property var filterIcons: ({ all: "", text: "󰈙", links: "󰌷", images: "󰋩", colors: "󰏘" })

  onTypeFilterChanged: Qt.callLater(root.ensureActiveFilterVisible)

  component ColorSwatch: Item {
    id: swatch
    property color value: "transparent"
    property real cornerRadius: root.cornerRadius
    readonly property color checkerLight: Qt.rgba(root.background.r, root.background.g, root.background.b, 1)
    readonly property color checkerDark: Qt.tint(checkerLight, Util.alpha(root.foreground, 0.25))

    Canvas {
      id: checker
      anchors.fill: parent
      visible: swatch.value.a < 1
      onVisibleChanged: if (visible) requestPaint()
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      Connections {
        target: swatch
        function onCheckerLightChanged() { checker.requestPaint() }
        function onCheckerDarkChanged() { checker.requestPaint() }
        function onCornerRadiusChanged() { checker.requestPaint() }
      }
      onPaint: {
        var context = getContext("2d")
        context.clearRect(0, 0, width, height)
        var radius = Math.min(swatch.cornerRadius, width / 2, height / 2)
        context.save()
        context.beginPath()
        context.moveTo(radius, 0)
        context.lineTo(width - radius, 0)
        context.quadraticCurveTo(width, 0, width, radius)
        context.lineTo(width, height - radius)
        context.quadraticCurveTo(width, height, width - radius, height)
        context.lineTo(radius, height)
        context.quadraticCurveTo(0, height, 0, height - radius)
        context.lineTo(0, radius)
        context.quadraticCurveTo(0, 0, radius, 0)
        context.closePath()
        context.clip()
        context.fillStyle = swatch.checkerLight
        context.fillRect(0, 0, width, height)
        context.fillStyle = swatch.checkerDark
        var cell = Math.max(2, Math.min(Style.space(10), Math.floor(Math.min(width, height) / 4)))
        for (var y = 0; y < height; y += cell) {
          for (var x = 0; x < width; x += cell) {
            if ((Math.floor(x / cell) + Math.floor(y / cell)) % 2)
              context.fillRect(x, y, cell, cell)
          }
        }
        context.restore()
      }
    }

    Rectangle {
      anchors.fill: parent
      radius: swatch.cornerRadius
      color: swatch.value
      border.width: Style.normalBorderWidth
      border.color: root.border
    }
  }

  component ColorPreview: Column {
    property var value: null
    property real swatchSize: Style.space(170)
    property real hexFontSize: Style.font.heading
    spacing: Style.space(12)

    ColorSwatch {
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.swatchSize
      height: width
      value: parent.value ? parent.value.swatchColor : "transparent"
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: parent.value ? parent.value.colorHex : ""
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: parent.hexFontSize
      font.bold: true
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: parent.value ? parent.value.colorRgb : ""
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: parent.value ? parent.value.colorHsl : ""
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  function open(payloadJson) {
    root.cancelEditedHistoryAction()
    root.opened = true
    root.filterText = ""
    root.typeFilter = "all"
    root.selectedIndex = 0
    root.cursorActive = true
    root.previewExpanded = false
    root.editorOpen = false
    root.editorError = ""
    root.editorAcceptedText = ""
    textEditor.text = ""
    root.disarmPointer()
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.cancelEditedHistoryAction()
    root.cancelClearHistory(false)
    root.previewExpanded = false
    root.editorOpen = false
    root.editorError = ""
    textEditor.text = ""
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function applyHistoryResult(result) {
    root.historyStatus = result.status
    root.historyContainsOversized = !!result.containsOversized
    root.history = result.entries
    if (result.status !== "ok") {
      root.cancelEditedHistoryAction()
      root.editorOpen = false
      root.editorError = ""
      root.editorAcceptedText = ""
      textEditor.text = ""
    } else if (!root.historyContainsOversized) {
      root.historyError = ""
    }
    if (root.opened) root.rebuildDisplay()
  }

  function resetHistoryWrite() {
    root.historyWritePending = false
    root.historyWriteReportedSaved = false
    root.historyWriteFailed = false
    root.historyWriteExpected = null
  }

  function resolveHistoryResult(result) {
    if (!root.historyWritePending) {
      root.applyHistoryResult(result)
      return
    }
    // Quickshell 0.3.1 may report saved after an atomic commit failure.
    // Only a bounded reread matching the expected history confirms the write.
    var disposition = ClipboardHistory.historyWriteDisposition(
      result,
      root.historyWriteExpected,
      root.historyWriteReportedSaved,
      root.historyWriteFailed
    )
    if (disposition === "pending") return

    var writeSucceeded = disposition === "confirmed"
    var shouldReport = root.pendingEditedAction
    root.resetHistoryWrite()

    if (writeSucceeded) {
      root.applyHistoryResult(result)
      root.completeEditedHistoryAction()
      return
    }

    root.pendingEditedSave = false
    root.pendingEditedAction = false
    root.pendingEditedCopyOnly = false
    root.applyHistoryResult(result)
    if (shouldReport && root.editorOpen)
      root.editorError = "Could not confirm the edited clipboard text on disk"
    else
      root.historyError = "Could not confirm the clipboard history update on disk"
  }

  function loadHistory(raw) {
    root.resolveHistoryResult(ClipboardHistory.parseHistory(raw))
  }

  function refuseHistory(status) {
    root.resolveHistoryResult({ status: status, entries: [] })
  }

  function emptyHistoryText() {
    if (root.historyStatus === "loading") return "Loading clipboard history…"
    if (root.historyStatus === "oversized") return "Clipboard history is too large"
    if (root.historyStatus === "unreadable") return "Clipboard history is unavailable"
    if (root.historyStatus === "invalid") return "Clipboard history is invalid"
    if (root.history.length === 0) return "Clipboard is empty"
    if (!root.filterText) return "No entries for this filter"
    return "No matches for “" + root.filterText + "”"
  }

  function scheduleHistoryReload() {
    root.historyReadPending = true
    historyReloadTimer.restart()
  }

  function startHistoryRead() {
    if (root.historyReadInFlight) return

    root.historyReadPending = false
    root.historyReadTimedOut = false
    root.historyReadInFlight = true
    historyReadProcess.command = [
      "head",
      "-c",
      String(ClipboardHistory.maxHistoryFileBytes + 1),
      "--",
      root.historyPath
    ]
    historyReadProcess.running = true
    historyReadWatchdog.restart()
  }

  function finishHistoryRead(exitCode) {
    if (!root.historyReadInFlight) return

    historyReadWatchdog.stop()
    root.historyReadInFlight = false
    if (root.historyReadPending) {
      historyReloadTimer.restart()
      return
    }

    if (root.historyReadTimedOut || exitCode !== 0) {
      root.refuseHistory("unreadable")
    } else if (historyReadOutput.data.byteLength > ClipboardHistory.maxHistoryFileBytes) {
      root.refuseHistory("oversized")
    } else {
      root.loadHistory(historyReadOutput.text)
    }
  }

  function saveHistory() {
    if (root.historyActionBlocked()) return false
    if (root.historyStatus !== "ok") {
      root.historyError = "Clipboard history is unavailable; reload before modifying it"
      return false
    }

    // With preload disabled, FileView compares against its own last write.
    // Alternate legal JSON whitespace so an external change can always be overwritten.
    var serialized = ClipboardHistory.serializeHistory(
      root.history,
      root.historyLimit,
      root.doubleHistoryWriteNewline ? 2 : 1
    )
    if (serialized.status !== "ok") {
      root.historyError = serialized.containsOversized
        ? "History with oversized entries can only be cleared or changed in the stock manager"
        : "Clipboard history exceeds its size limit"
      return false
    }

    root.doubleHistoryWriteNewline = !root.doubleHistoryWriteNewline
    root.historyError = ""
    root.historyContainsOversized = false
    historyFile.setText(serialized.text)
    root.historyWriteExpected = root.history
    root.historyWriteReportedSaved = false
    root.historyWriteFailed = false
    root.historyWritePending = true
    return true
  }

  function historyActionBlocked() {
    if (root.historyWritePending) {
      root.historyError = "Clipboard history update is still being confirmed"
      return true
    }
    if (root.historyReadPending || root.historyReadInFlight) {
      root.historyError = "Clipboard history reload is still in progress"
      return true
    }
    return false
  }

  function requestClearHistory() {
    if (root.historyActionBlocked()) return
    if (root.historyStatus !== "ok"
        && root.historyStatus !== "oversized"
        && root.historyStatus !== "invalid")
      return
    if (root.history.length === 0 && root.historyStatus === "ok") return
    clearConfirm.selectedIndex = 1
    root.clearConfirmOpen = true
  }

  function cancelClearHistory(refocus) {
    root.clearConfirmOpen = false
    root.disarmPointer()
    if (refocus === undefined || refocus)
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmClearHistory() {
    if (root.historyActionBlocked()) return
    root.history = ClipboardHistory.clearHistory()
    root.historyStatus = "ok"
    root.historyContainsOversized = false
    root.saveHistory()
    root.selectedIndex = 0
    root.cursorActive = false
    root.disarmPointer()
    root.clearConfirmOpen = false
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function removeDisplayIndex(index) {
    if (root.historyActionBlocked()) return
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)

    var previousHistory = root.history
    root.history = ClipboardHistory.removeEntryAt(root.history, row.historyIndex)
    if (!root.saveHistory()) {
      root.history = previousHistory
      return
    }

    if (displayModel.count <= 1) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= displayModel.count - 1) {
      root.selectedIndex = displayModel.count - 2
    }

    root.disarmPointer()
    root.rebuildDisplay()
  }

  function rowSubtitle(row) {
    if (row.entryType === "oversized") return "Text · Too large to preview"
    if (row.entryType === "image") return "Image · " + row.mime
    if (row.entryType === "link") return "Link · " + row.linkDomain
    if (row.entryType === "file") {
      var label = row.previewImage ? "Image file" : (row.fileCount === 1 ? "File" : row.fileCount + " files")
      return label + (row.directory ? " · " + row.directory : "")
    }
    return (row.entryType === "color" ? "Color" : "Text")
      + " · " + row.wordCount + (row.wordCount === 1 ? " word" : " words")
      + " · " + row.lineCount + (row.lineCount === 1 ? " line" : " lines")
  }

  function rebuildDisplay() {
    var rows = ClipboardHistory.displayRows(root.preparedHistory, root.filterText, root.displayLimit, root.typeFilter)

    displayModel.clear()
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      var color = row.colorDetails
      displayModel.append({
        entryType: row.entryType,
        fullText: row.fullText,
        previewText: row.previewText,
        subtitle: root.rowSubtitle(row),
        previewImage: row.previewImage ? Util.fileUrl(row.previewImage) : "",
        swatchColor: color ? Qt.rgba(color.red, color.green, color.blue, color.alpha) : Qt.rgba(0, 0, 0, 0),
        colorHex: color ? color.hex : "",
        colorRgb: color ? color.rgb : "",
        colorHsl: color ? color.hsl : "",
        path: row.path,
        mime: row.mime,
        historyIndex: row.index
      })
    }

    if (displayModel.count === 0) root.selectedIndex = 0
    else if (root.selectedIndex >= displayModel.count) root.selectedIndex = displayModel.count - 1
    else if (root.selectedIndex < 0) root.selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function selectedRow() {
    if (displayModel.count === 0 || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return null
    return displayModel.get(root.selectedIndex)
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!root.cursorActive) {
      root.cursorActive = true
      root.selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function setTypeFilter(nextFilter) {
    if (root.typeFilters.indexOf(nextFilter) < 0) return
    root.typeFilter = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function ensureActiveFilterVisible() {
    var button = filterRepeater.itemAt(root.typeFilters.indexOf(root.typeFilter))
    if (!button) return
    var maxX = Math.max(0, filterBar.contentWidth - filterBar.width)
    var nextX = Math.min(filterBar.contentX, maxX)
    if (button.x < nextX) nextX = button.x
    else if (button.x + button.width > nextX + filterBar.width)
      nextX = button.x + button.width - filterBar.width
    filterBar.contentX = Math.max(0, Math.min(nextX, maxX))
  }

  function cycleTypeFilter(delta) {
    var index = root.typeFilters.indexOf(root.typeFilter)
    root.setTypeFilter(root.typeFilters[(index + delta + root.typeFilters.length) % root.typeFilters.length])
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.applySelected(displayModel.get(index))
  }

  function copyIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.copySelected(displayModel.get(index))
  }

  function openIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.openSelected(displayModel.get(index))
  }

  function applySelected(row) {
    if (root.historyActionBlocked()) return
    if (!row) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", row.mime, row.path])
    } else {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--shift-insert", "--history-index", String(row.historyIndex)])
    }
  }

  function copySelected(row) {
    if (root.historyActionBlocked()) return
    if (!row) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", "--copy-only", row.mime, row.path])
    } else {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(row.historyIndex)])
    }
  }

  function openSelected(row) {
    if (root.historyActionBlocked()) return
    if (!row) return
    root.opened = false
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-open", "--history-index", String(row.historyIndex)])
  }

  function openExpandedPreview() {
    var row = root.selectedRow()
    if (!row) return
    if (row.entryType === "oversized") {
      root.historyError = "Oversized clipboard text cannot be previewed"
      return
    }

    root.expandedKind = row.colorHex ? "color" : (row.previewImage ? "image" : "text")
    root.expandedImage = row.previewImage || ""
    root.expandedColor = row.colorHex ? {
      swatchColor: row.swatchColor,
      colorHex: row.colorHex,
      colorRgb: row.colorRgb,
      colorHsl: row.colorHsl
    } : null
    root.expandedText = ""
    root.expandedTruncated = false
    root.expandedTotalLength = 0

    if (root.expandedKind === "text") {
      var preview = ClipboardHistory.textPreview(root.history, row.historyIndex, 65536)
      root.expandedText = preview.text
      root.expandedTruncated = preview.truncated
      root.expandedTotalLength = preview.totalLength
    }

    root.previewExpanded = true
    expandedTextScroll.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function closeExpandedPreview() {
    root.previewExpanded = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function startEditor() {
    var row = root.selectedRow()
    if (!row || row.entryType === "image") return
    if (row.entryType === "oversized") {
      root.historyError = "Oversized clipboard text cannot be edited"
      return
    }

    var text = ClipboardHistory.entryText(root.history, row.historyIndex)
    root.previewExpanded = false
    root.editorError = ""
    root.editorAcceptedText = text
    root.editorOpen = true
    textEditor.text = text
    editorScroll.contentY = 0
    Qt.callLater(function() {
      textEditor.forceActiveFocus()
      textEditor.cursorPosition = textEditor.length
    })
  }

  function cancelEditedHistoryAction() {
    root.pendingEditedAction = false
    root.pendingEditedCopyOnly = false
  }

  function closeEditor() {
    root.cancelEditedHistoryAction()
    root.editorOpen = false
    root.editorError = ""
    root.editorAcceptedText = ""
    textEditor.text = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function finishEditing(copyOnly) {
    if (root.historyActionBlocked()) {
      root.editorError = root.historyError
      return
    }
    if (root.historyStatus !== "ok") {
      root.editorError = "Clipboard history is unavailable; press Ctrl+R before saving"
      return
    }

    var text = textEditor.text
    if (text.trim().length === 0) {
      root.editorError = "Clipboard text cannot be blank"
      return
    }
    if (text.length > ClipboardHistory.maxEntryTextLength) {
      root.editorError = "Clipboard text exceeds the 1 MiB limit"
      return
    }
    if (root.pendingEditedSave) {
      root.editorError = "Clipboard operation already in progress"
      return
    }

    var existingIndex = ClipboardHistory.findTextIndex(root.history, text)
    if (existingIndex === 0) {
      var row = { entryType: "text", historyIndex: 0 }
      root.editorOpen = false
      root.editorError = ""
      root.editorAcceptedText = ""
      textEditor.text = ""
      if (copyOnly) root.copySelected(row)
      else root.applySelected(row)
      return
    }

    var added = ClipboardHistory.addEntry(
      root.history,
      { type: "text", text: text },
      root.historyLimit
    )
    if (added.status !== "ok") {
      root.editorError = added.containsOversized
        ? "History with oversized entries can only be cleared or changed in the stock manager"
        : (added.status === "oversized"
          ? "Clipboard history exceeds its size limit"
          : "Clipboard history is invalid")
      return
    }

    var previousHistory = root.history
    root.history = added.entries
    root.editorError = ""
    if (!root.saveHistory()) {
      root.history = previousHistory
      root.rebuildDisplay()
      root.editorError = root.historyError || "Could not save edited clipboard text"
      return
    }

    root.pendingEditedCopyOnly = copyOnly
    root.pendingEditedAction = true
    root.pendingEditedSave = true
  }

  function completeEditedHistoryAction() {
    if (!root.pendingEditedSave) return

    var shouldInvoke = root.pendingEditedAction
    var copyOnly = root.pendingEditedCopyOnly
    root.pendingEditedSave = false
    root.pendingEditedAction = false
    root.pendingEditedCopyOnly = false
    if (!shouldInvoke) return

    var command = [root.omarchyPath + "/bin/omarchy-clipboard-paste-text"]
    if (copyOnly) command.push("--copy-only")
    command.push("--history-index", "0")

    root.editorOpen = false
    root.editorError = ""
    textEditor.text = ""
    root.opened = false
    Quickshell.execDetached(command)
  }

  Component.onCompleted: root.scheduleHistoryReload()

  ListModel { id: displayModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    preload: false
    atomicWrites: true
    printErrors: false
    onFileChanged: root.scheduleHistoryReload()
    onSaved: {
      if (root.historyWritePending) root.historyWriteReportedSaved = true
      root.scheduleHistoryReload()
    }
    onSaveFailed: {
      if (root.historyWritePending) root.historyWriteFailed = true
      root.scheduleHistoryReload()
    }
  }

  Process {
    id: historyReadProcess
    command: []
    stdout: StdioCollector {
      id: historyReadOutput
      waitForEnd: true
    }
    onExited: function(exitCode, exitStatus) { root.finishHistoryRead(exitCode) }
  }

  Timer {
    id: historyReloadTimer
    interval: 75
    repeat: false
    onTriggered: root.startHistoryRead()
  }

  Timer {
    id: historyReadWatchdog
    interval: 5000
    repeat: false
    onTriggered: {
      if (!root.historyReadInFlight) return
      root.historyReadTimedOut = true
      if (historyReadProcess.running) historyReadProcess.signal(9)
      else root.finishHistoryRead(-1)
    }
  }


  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.clearConfirmOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.clearConfirmOpen) {
            if (clearConfirm.handleKey(event)) event.accepted = true
            return
          }

          var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
          var shift = (event.modifiers & Qt.ShiftModifier) !== 0

          if (root.previewExpanded) {
            if (event.key === Qt.Key_Escape || (ctrl && event.key === Qt.Key_Space)) {
              root.closeExpandedPreview()
              event.accepted = true
            } else if (ctrl && event.key === Qt.Key_E && root.expandedKind === "text") {
              root.startEditor()
              event.accepted = true
            } else if (event.key === Qt.Key_PageUp) {
              expandedTextScroll.contentY = Math.max(0, expandedTextScroll.contentY - expandedTextScroll.height * 0.8)
              event.accepted = true
            } else if (event.key === Qt.Key_PageDown) {
              expandedTextScroll.contentY = Math.min(Math.max(0, expandedTextScroll.contentHeight - expandedTextScroll.height), expandedTextScroll.contentY + expandedTextScroll.height * 0.8)
              event.accepted = true
            }
            return
          }

          if (root.editorOpen) return

          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.close()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_J) {
            root.select(1)
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_K) {
            root.select(-1)
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_Space) {
            root.openExpandedPreview()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_E) {
            root.startEditor()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_R) {
            root.scheduleHistoryReload()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_1) {
            root.setTypeFilter("all")
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_2) {
            root.setTypeFilter("text")
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_3) {
            root.setTypeFilter("images")
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_4) {
            root.setTypeFilter("colors")
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_T) {
            root.cycleTypeFilter(shift ? -1 : 1)
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            if (shift) root.requestClearHistory()
            else root.removeDisplayIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectAbsolute(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectAbsolute(displayModel.count - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive && (event.modifiers & Qt.AltModifier)) root.openIndex(root.selectedIndex)
            else if (root.cursorActive && shift) root.copyIndex(root.selectedIndex)
            else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: clearConfirm
          anchors.fill: parent
          opened: root.clearConfirmOpen
          z: 10
          message: "Delete entire clipboard history?"
          confirmText: "Delete"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelClearHistory()
          onConfirmed: root.confirmClearHistory()
        }
      }

      Column {
        id: normalView
        visible: !root.previewExpanded && !root.editorOpen
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Text {
          width: parent.width
          height: root.headerHeight
          text: root.filterText || "Search clipboard…"
          textFormat: Text.PlainText
          color: root.foreground
          opacity: root.filterText ? 1 : 0.58
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          elide: Text.ElideRight
          verticalAlignment: Text.AlignVCenter
        }

        Flickable {
          id: filterBar
          width: parent.width
          height: filterPills.implicitHeight
          contentWidth: filterPills.implicitWidth
          contentHeight: height
          flickableDirection: Flickable.HorizontalFlick
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentWidth > width
          clip: true
          onWidthChanged: Qt.callLater(root.ensureActiveFilterVisible)
          onContentWidthChanged: Qt.callLater(root.ensureActiveFilterVisible)

          Row {
            id: filterPills
            spacing: Style.space(6)

            Repeater {
              id: filterRepeater
              model: root.typeFilters

              Button {
                required property string modelData
                height: Math.max(Style.space(24), implicitHeight)
                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                iconText: root.filterIcons[modelData]
                selected: root.typeFilter === modelData
                foreground: root.foreground
                accent: root.selectedText
                background: Util.alpha(root.foreground, 0.055)
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                iconSize: Style.font.caption
                horizontalPadding: Style.space(10)
                verticalPadding: Style.space(2)
                radius: height / 2
                onClicked: root.setTypeFilter(modelData)
              }
            }
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - filterBar.height - root.footerHeight - root.contentSpacing * 3

          Row {
            anchors.fill: parent
            spacing: 0

            Item {
              id: resultsPane
              width: parent.width / 2
              height: parent.height
              clip: true

              ListView {
                id: resultList
                anchors.fill: parent
                anchors.rightMargin: root.contentMargin
                model: displayModel
                clip: true
                spacing: Style.space(4)
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                  id: row
                  required property int index
                  required property string entryType
                  required property string previewText
                  required property string subtitle
                  required property string fullText
                  required property string previewImage
                  required property color swatchColor
                  required property string colorHex

                  readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
                  readonly property color contentColor: hasCursor ? root.selectedText : root.foreground

                  width: ListView.view.width
                  height: root.rowHeight
                  radius: root.cornerRadius
                  color: hasCursor ? root.selectedBackground : "transparent"

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(12)
                    anchors.topMargin: Style.space(8)
                    anchors.bottomMargin: Style.space(8)
                    spacing: Style.space(10)

                    Rectangle {
                      id: typeFrame
                      anchors.verticalCenter: parent.verticalCenter
                      width: Math.min(parent.height, Style.space(42))
                      height: width
                      radius: Math.max(Style.space(5), root.cornerRadius)
                      color: thumbnail.status === Image.Ready ? "transparent" : Util.alpha(row.contentColor, 0.055)
                      border.width: thumbnail.status === Image.Ready ? 0 : Style.normalBorderWidth
                      border.color: Util.alpha(row.contentColor, 0.12)

                      OpticalGlyph {
                        anchors.fill: parent
                        visible: row.colorHex.length === 0 && thumbnail.status !== Image.Ready
                        text: row.previewImage ? "󰋩" : (row.entryType === "link" ? "󰌷" : (row.entryType === "file" ? "󰉋" : "󰈙"))
                        fontFamily: root.fontFamily
                        fontSize: Style.space(21)
                        color: row.contentColor
                        opacity: 0.8
                      }

                      Item {
                        id: thumbnailMask
                        anchors.fill: parent
                        visible: false
                        layer.enabled: thumbnail.status === Image.Ready

                        Rectangle {
                          anchors.centerIn: parent
                          width: thumbnail.paintedWidth
                          height: thumbnail.paintedHeight
                          radius: typeFrame.radius
                          color: "white"
                          antialiasing: true
                        }
                      }

                      Image {
                        id: thumbnail
                        anchors.fill: parent
                        visible: status === Image.Ready
                        source: row.colorHex.length === 0 ? row.previewImage : ""
                        sourceSize.width: Math.max(1, width)
                        sourceSize.height: Math.max(1, height)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        layer.enabled: status === Image.Ready
                        layer.smooth: true
                        layer.effect: MultiEffect {
                          maskEnabled: true
                          maskSource: thumbnailMask
                          maskThresholdMin: 0.3
                          maskSpreadAtMin: 0.3
                        }
                      }

                      ColorSwatch {
                        anchors.centerIn: parent
                        visible: row.colorHex.length > 0
                        width: Math.max(1, parent.width - Style.space(16))
                        height: width
                        cornerRadius: Style.space(4)
                        value: row.swatchColor
                      }
                    }

                    Column {
                      anchors.verticalCenter: parent.verticalCenter
                      width: Math.max(0, parent.width - typeFrame.width - parent.spacing)
                      spacing: Style.space(3)

                      Text {
                        width: parent.width
                        text: row.previewText
                        color: row.contentColor
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        textFormat: Text.PlainText
                      }

                      Text {
                        width: parent.width
                        text: row.subtitle
                        color: row.contentColor
                        opacity: 0.65
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        wrapMode: Text.NoWrap
                        textFormat: Text.PlainText
                      }
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: function(mouse) { root.selectFromPointer(row.index, row, mouse) }
                    onClicked: {
                      root.cursorActive = true
                      root.selectedIndex = row.index
                      root.activateIndex(row.index)
                    }
                  }
                }
              }
            }

            Item {
              id: previewPane
              width: parent.width - resultsPane.width
              height: parent.height
              clip: true

              property var activeRow: displayModel.count > 0 && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count ? displayModel.get(root.selectedIndex) : null

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Style.normalBorderWidth
                color: Util.alpha(root.border, 0.28)
              }

              Flickable {
                id: compactTextScroll
                visible: previewPane.activeRow && !previewPane.activeRow.previewImage && !previewPane.activeRow.colorHex
                anchors.fill: parent
                anchors.leftMargin: root.contentMargin
                clip: true
                contentWidth: width
                contentHeight: Math.max(height, compactPreviewText.implicitHeight)
                boundsBehavior: Flickable.StopAtBounds

                Text {
                  id: compactPreviewText
                  width: compactTextScroll.width
                  text: previewPane.activeRow ? previewPane.activeRow.fullText : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  wrapMode: Text.WrapAnywhere
                  textFormat: Text.PlainText
                }
              }

              Image {
                visible: previewPane.activeRow && previewPane.activeRow.previewImage
                anchors.fill: parent
                anchors.leftMargin: root.contentMargin
                source: previewPane.activeRow ? previewPane.activeRow.previewImage : ""
                sourceSize.width: Math.max(1, root.cardWidth)
                sourceSize.height: Math.max(1, root.cardHeight)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
              }

              ColorPreview {
                visible: previewPane.activeRow && previewPane.activeRow.colorHex.length > 0
                anchors.centerIn: parent
                value: previewPane.activeRow
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              text: "󰅌"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              text: root.emptyHistoryText()
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
          }
        }

        Text {
          width: parent.width
          height: root.footerHeight
          text: root.historyError || "Ctrl+J/K move  ·  Ctrl+Space expand  ·  Ctrl+E edit  ·  Ctrl+1–4 filter  ·  Enter paste  ·  Shift+Enter copy"
          textFormat: Text.PlainText
          color: root.foreground
          opacity: root.historyError ? 0.9 : 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          verticalAlignment: Text.AlignVCenter
        }
      }

      Item {
        id: expandedView
        visible: root.previewExpanded
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Text {
          id: expandedTitle
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: root.headerHeight
          text: root.expandedKind === "image" ? "Image preview" : root.expandedKind === "color" ? "Color preview" : "Text preview"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: expandedTitle.verticalCenter
          text: "Ctrl+Space or Esc to return"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Image {
          visible: root.expandedKind === "image"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: expandedTitle.bottom
          anchors.bottom: parent.bottom
          source: root.expandedImage
          sourceSize.width: Math.max(1, root.cardWidth)
          sourceSize.height: Math.max(1, root.cardHeight)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
        }

        ColorPreview {
          visible: root.expandedKind === "color"
          anchors.centerIn: parent
          value: root.expandedColor
          swatchSize: Math.min(Style.space(320), expandedView.width * 0.55)
          hexFontSize: Style.font.display
        }

        Flickable {
          id: expandedTextScroll
          visible: root.expandedKind === "text"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: expandedTitle.bottom
          anchors.bottom: expandedTruncation.top
          clip: true
          contentWidth: width
          contentHeight: Math.max(height, expandedTextItem.implicitHeight)
          boundsBehavior: Flickable.StopAtBounds

          Text {
            id: expandedTextItem
            width: expandedTextScroll.width
            text: root.expandedText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            wrapMode: Text.WrapAnywhere
            textFormat: Text.PlainText
          }
        }

        Text {
          id: expandedTruncation
          visible: root.expandedKind === "text" && root.expandedTruncated
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: visible ? root.footerHeight : 0
          text: "Preview capped at 64 KiB; Ctrl+E opens the complete text"
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          verticalAlignment: Text.AlignVCenter
        }
      }

      Item {
        id: editorView
        visible: root.editorOpen
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Text {
          id: editorTitle
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: root.headerHeight
          text: "Edit clipboard text"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: editorTitle.verticalCenter
          text: "Ctrl+Enter paste  ·  Ctrl+Shift+Enter or Ctrl+S copy  ·  Esc cancel"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: editorTitle.bottom
          anchors.bottom: editorErrorText.top
          color: Util.alpha(root.foreground, 0.035)
          radius: root.cornerRadius
          border.width: Style.normalBorderWidth
          border.color: Util.alpha(root.border, 0.5)

          Flickable {
            id: editorScroll
            anchors.fill: parent
            anchors.margins: Style.space(14)
            clip: true
            contentWidth: width
            contentHeight: Math.max(height, textEditor.implicitHeight)
            boundsBehavior: Flickable.StopAtBounds

            TextEdit {
              id: textEditor
              width: editorScroll.width
              height: Math.max(editorScroll.height, implicitHeight)
              color: root.foreground
              selectionColor: root.selectedBackground
              selectedTextColor: root.selectedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              wrapMode: TextEdit.WrapAnywhere
              textFormat: TextEdit.PlainText
              selectByMouse: true

              onTextChanged: {
                if (root.editorTextGuardActive) return
                if (text.length <= ClipboardHistory.maxEntryTextLength) {
                  root.editorAcceptedText = text
                  if (root.editorError === "Clipboard text exceeds the 1 MiB limit")
                    root.editorError = ""
                  return
                }

                root.editorTextGuardActive = true
                text = root.editorAcceptedText
                root.editorTextGuardActive = false
                root.editorError = "Clipboard text exceeds the 1 MiB limit"
              }

              onCursorRectangleChanged: {
                if (cursorRectangle.y < editorScroll.contentY)
                  editorScroll.contentY = cursorRectangle.y
                else if (cursorRectangle.y + cursorRectangle.height > editorScroll.contentY + editorScroll.height)
                  editorScroll.contentY = cursorRectangle.y + cursorRectangle.height - editorScroll.height
              }

              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function(event) {
                var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                var shift = (event.modifiers & Qt.ShiftModifier) !== 0
                if (event.key === Qt.Key_Escape) {
                  root.closeEditor()
                  event.accepted = true
                } else if (ctrl && shift && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                  root.finishEditing(true)
                  event.accepted = true
                } else if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                  root.finishEditing(false)
                  event.accepted = true
                } else if (ctrl && event.key === Qt.Key_S) {
                  root.finishEditing(true)
                  event.accepted = true
                }
              }
            }
          }
        }

        Text {
          id: editorErrorText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: root.editorError ? root.footerHeight : 0
          text: root.editorError
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          verticalAlignment: Text.AlignVCenter
        }
      }
    }
  }
}
