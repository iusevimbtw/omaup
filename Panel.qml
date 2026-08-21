import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "iusevimbtw.omaup"
  ipcTarget: "iusevimbtw.omaup"
  manageIpc: false

  property string focusSection: "add"
  property int siteIndex: 0
  property bool cursorActive: false
  property bool adding: false
  property string addError: ""
  property bool draggingSite: false
  property int dragSourceIndex: -1
  property int dragInsertBefore: -1
  property string dragSourceId: ""
  property string focusedSiteId: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var omaup: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property var downSites: {
    if (!omaup) return []
    omaup.itemsRevision
    return Model.downSites(omaup.items)
  }
  readonly property var onlineSites: {
    if (!omaup) return []
    omaup.itemsRevision
    return Model.onlineSites(omaup.items)
  }
  readonly property var sites: {
    downSites
    onlineSites
    return Model.displaySites(omaup ? omaup.items : [])
  }
  readonly property color barIconColor: {
    if (!omaup) return barForeground
    if (omaup.downCount > 0) return urgent
    if (omaup.upCount > 0) return omaup.themeGreen
    return barForeground
  }
  readonly property color heroIconColor: {
    if (!omaup) return foreground
    if (omaup.downCount > 0) return urgent
    if (omaup.upCount > 0) return omaup.themeGreen
    return foreground
  }
  readonly property bool sitesHasCursor: cursorActive && focusSection === "sites"
  readonly property bool addHasCursor: cursorActive && focusSection === "add"
  readonly property bool editingAdd: adding && (nameField.activeFocus || urlField.activeFocus)

  function siteIdAt(index) {
    if (!Array.isArray(sites) || index < 0 || index >= sites.length || !sites[index]) return ""
    return String(sites[index].id || "")
  }

  function indexOfSiteId(id) {
    var needle = String(id || "")
    if (needle === "" || !Array.isArray(sites)) return -1
    for (var i = 0; i < sites.length; i++) {
      if (sites[i] && String(sites[i].id || "") === needle) return i
    }
    return -1
  }

  function syncCursorToFocusedSite() {
    if (focusSection !== "sites") return
    var index = indexOfSiteId(focusedSiteId)
    if (index >= 0) siteIndex = index
    else ensureCursor()
  }

  function ensureCursor() {
    if (!Array.isArray(sites) || sites.length === 0) {
      focusSection = "add"
      siteIndex = 0
      focusedSiteId = ""
      return
    }
    if (focusSection !== "sites" && focusSection !== "add") focusSection = "sites"
    var focused = indexOfSiteId(focusedSiteId)
    if (focusSection === "sites" && focused >= 0) siteIndex = focused
    if (siteIndex >= sites.length) siteIndex = sites.length - 1
    if (siteIndex < 0) siteIndex = 0
    if (focusSection === "sites") focusedSiteId = siteIdAt(siteIndex)
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    if (focusSection === "sites") {
      if (dy > 0 && siteIndex >= sites.length - 1) {
        focusSection = "add"
        return
      }
      siteIndex = Math.max(0, Math.min(sites.length - 1, siteIndex + dy))
      focusedSiteId = siteIdAt(siteIndex)
      scrollCursorIntoView()
      return
    }
    if (dy < 0 && sites.length > 0) {
      focusSection = "sites"
      siteIndex = sites.length - 1
      focusedSiteId = siteIdAt(siteIndex)
      scrollCursorIntoView()
    }
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "add") {
      startAdding()
      return
    }
    openSelected()
  }

  function openSelected() {
    if (!omaup || !Array.isArray(sites) || sites.length === 0) return
    omaup.openTarget(sites[Math.max(0, Math.min(siteIndex, sites.length - 1))])
  }

  function deleteSelected() {
    if (!omaup || focusSection !== "sites" || !Array.isArray(sites) || sites.length === 0) return
    omaup.removeTarget(sites[Math.max(0, Math.min(siteIndex, sites.length - 1))].id)
    ensureCursor()
  }

  function setSiteCursor(index) {
    cursorActive = true
    focusSection = "sites"
    siteIndex = index
    focusedSiteId = siteIdAt(index)
    scrollCursorIntoView()
  }

  function setAddCursor() {
    cursorActive = true
    focusSection = "add"
  }

  function startAdding() {
    adding = true
    addError = ""
    setAddCursor()
    Qt.callLater(function() {
      nameField.forceActiveFocus()
      nameField.selectAll()
    })
  }

  function stopAdding() {
    adding = false
    addError = ""
    nameField.text = ""
    urlField.text = ""
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function submitAdd() {
    if (!omaup) {
      addError = "Service not ready"
      return
    }
    var error = omaup.addTarget(nameField.text, urlField.text)
    if (error !== "") {
      addError = error
      return
    }
    stopAdding()
    if (sites.length > 0) {
      focusSection = "sites"
      siteIndex = sites.length - 1
      focusedSiteId = siteIdAt(siteIndex)
      scrollCursorIntoView()
    }
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection !== "sites") return
    var rows = siteRowItems()
    if (siteIndex >= 0 && siteIndex < rows.length) scrollItemIntoView(rows[siteIndex])
  }

  function siteRowItems() {
    var rows = []
    if (!siteColumn) return rows
    for (var i = 0; i < siteColumn.children.length; i++) {
      var child = siteColumn.children[i]
      if (child && child.site !== undefined) rows.push(child)
    }
    return rows
  }

  function siteInsertBeforeAtY(y) {
    var rows = siteRowItems()
    if (rows.length === 0) return 0
    for (var i = 0; i < rows.length; i++) {
      if (y < rows[i].y + rows[i].height / 2) return i
    }
    return rows.length
  }

  readonly property real dropMarkerThickness: Math.max(2, Style.spacing.xs)
  readonly property real dropMarkerY: {
    draggingSite
    dragInsertBefore
    var rows = siteRowItems()
    if (rows.length === 0 || dragInsertBefore < 0) return 0
    var half = dropMarkerThickness / 2
    if (dragInsertBefore <= 0) return rows[0].y - half
    if (dragInsertBefore >= rows.length) {
      var last = rows[rows.length - 1]
      return last.y + last.height - half
    }
    return rows[dragInsertBefore].y - siteColumn.spacing / 2 - half
  }

  function beginSiteDrag(index) {
    draggingSite = true
    dragSourceIndex = index
    dragInsertBefore = index
    dragSourceId = siteIdAt(index)
    cursorActive = true
    focusSection = "sites"
    siteIndex = index
    focusedSiteId = dragSourceId
  }

  function updateSiteDrag(yInColumn) {
    dragInsertBefore = siteInsertBeforeAtY(yInColumn)
    if (panelFlick && siteColumn) {
      var y = yInColumn + siteColumn.mapToItem(panelFlick.contentItem, 0, 0).y
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var margin = Style.space(24)
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (y < viewTop + margin) panelFlick.contentY = Math.max(0, panelFlick.contentY - Style.space(8))
      else if (y > viewBottom - margin) panelFlick.contentY = Math.min(maxY, panelFlick.contentY + Style.space(8))
    }
  }

  function endSiteDrag() {
    var id = dragSourceId
    var insertBefore = dragInsertBefore
    var displayed = sites
    var from = indexOfSiteId(id)
    draggingSite = false
    dragSourceIndex = -1
    dragInsertBefore = -1
    dragSourceId = ""
    if (!omaup || typeof omaup.moveTarget !== "function") return
    if (id === "" || from < 0 || insertBefore < 0) return
    if (insertBefore === from || insertBefore === from + 1) return
    var beforeId = insertBefore < displayed.length ? siteIdAt(insertBefore) : ""
    omaup.moveTarget(id, beforeId)
    focusedSiteId = id
    syncCursorToFocusedSite()
    ensureCursor()
  }

  function cancelSiteDrag() {
    draggingSite = false
    dragSourceIndex = -1
    dragInsertBefore = -1
    dragSourceId = ""
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    adding = false
    addError = ""
    nameField.text = ""
    urlField.text = ""
    cancelSiteDrag()
    if (omaup && omaup.reloadTheme) omaup.reloadTheme()
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  } else {
    adding = false
    addError = ""
    cancelSiteDrag()
  }
  onSiteIndexChanged: scrollCursorIntoView()
  onSitesChanged: if (!draggingSite) syncCursorToFocusedSite()

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { if (root.omaup) root.omaup.refresh(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    foreground: root.barIconColor
    tooltipText: omaup ? omaup.heroMeta : "Omaup"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) { if (omaup) omaup.refresh() }
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingAdd
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.adding ? root.stopAdding() : root.close()
      onDeleteRequested: root.deleteSelected()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") { if (omaup) omaup.refresh() }
        else if (t === "a" || t === "A") root.startAdding()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height && !root.draggingSite
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Omaup"
            meta: omaup ? omaup.heroMeta : "Waiting for checks"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: ""
                color: root.heroIconColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: siteColumn.implicitHeight
              height: siteColumn.implicitHeight

              Column {
                id: siteColumn
                width: parent.width
                spacing: Style.space(6)

                SectionRule {
                  visible: root.downSites.length > 0
                  width: parent.width
                  text: "OFFLINE"
                }

                Repeater {
                  model: root.downSites
                  SiteRow {
                    required property var modelData
                    required property int index
                    width: siteColumn.width
                    site: modelData
                    rowIndex: index
                  }
                }

                SectionRule {
                  width: parent.width
                  text: "ONLINE"
                }

                Repeater {
                  model: root.onlineSites
                  SiteRow {
                    required property var modelData
                    required property int index
                    width: siteColumn.width
                    site: modelData
                    rowIndex: root.downSites.length + index
                  }
                }

              CursorSurface {
                id: addRow
                visible: !root.adding
                width: parent.width
                implicitHeight: addRowContent.implicitHeight + Style.spacing.rowPaddingX
                hasCursor: root.addHasCursor
                foreground: root.foreground

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.setAddCursor()
                  onClicked: root.startAdding()
                }

                RowLayout {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(8)

                  Rectangle {
                    width: Style.space(8)
                    height: Style.space(8)
                    radius: width / 2
                    color: root.dim
                    Layout.alignment: Qt.AlignVCenter
                  }

                  ColumnLayout {
                    id: addRowContent
                    Layout.fillWidth: true
                    spacing: Style.space(1)

                    Text {
                      Layout.fillWidth: true
                      text: "Add"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    Text {
                      Layout.fillWidth: true
                      text: "Watch a new URL"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  PanelActionButton {
                    iconText: "󰐕"
                    tooltipText: "Add site"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: root.startAdding()
                  }
                }
              }

              CursorSurface {
                id: addFormSurface
                visible: root.adding
                width: parent.width
                implicitHeight: addForm.implicitHeight + Style.spacing.rowPaddingX
                hasCursor: root.addHasCursor && !root.editingAdd
                foreground: root.foreground

                Column {
                  id: addForm
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(8)

                  TextField {
                    id: nameField
                    width: parent.width
                    placeholderText: "Name"
                    foreground: root.foreground
                    font.family: root.fontFamily
                    onActiveFocusChanged: if (activeFocus) root.setAddCursor()
                    Keys.onPressed: function(event) {
                      if (event.key === Qt.Key_Escape) {
                        root.stopAdding()
                        event.accepted = true
                      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        urlField.forceActiveFocus()
                        event.accepted = true
                      }
                    }
                  }

                  TextField {
                    id: urlField
                    width: parent.width
                    placeholderText: "https://example.com"
                    foreground: root.foreground
                    font.family: root.fontFamily
                    onActiveFocusChanged: if (activeFocus) root.setAddCursor()
                    Keys.onPressed: function(event) {
                      if (event.key === Qt.Key_Escape) {
                        root.stopAdding()
                        event.accepted = true
                      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.submitAdd()
                        event.accepted = true
                      }
                    }
                  }

                  Text {
                    visible: root.addError !== ""
                    width: parent.width
                    text: root.addError
                    color: root.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }
                }
              }
            }

            Rectangle {
              visible: root.draggingSite && root.dragInsertBefore >= 0
              x: 0
              y: root.dropMarkerY
              z: 20
              width: parent.width
              height: root.dropMarkerThickness
              radius: height / 2
              color: Color.accent
            }
          }
        }
      }
    }
  }
}

  component SectionRule: Item {
    id: rule
    property string text: ""
    property color foreground: root.foreground
    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(label.implicitHeight, line.height)

    PanelSectionHeader {
      id: label
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: rule.text
      foreground: rule.foreground
      fontFamily: root.fontFamily
    }

    Rectangle {
      id: line
      anchors.left: label.right
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.verticalCenter: label.verticalCenter
      anchors.verticalCenterOffset: Math.round(label.topPadding / 2)
      height: 1
      color: Qt.rgba(rule.foreground.r, rule.foreground.g, rule.foreground.b, 0.12)
    }
  }

  component SiteRow: CursorSurface {
    id: siteRow
    property var site: null
    property int rowIndex: 0
    readonly property color statusColor: {
      if (!site) return root.dim
      if (site.status === "down") return root.urgent
      if (site.status === "up") return omaup ? omaup.themeGreen : root.dim
      return root.dim
    }

    hasCursor: root.sitesHasCursor && root.siteIndex === rowIndex && !root.draggingSite
    foreground: root.foreground
    opacity: root.draggingSite && siteRow.site && String(siteRow.site.id || "") === root.dragSourceId ? 0.45 : 1
    z: sitePointer.dragging ? 10 : 0
    implicitHeight: siteContent.implicitHeight + Style.spacing.rowPaddingX
    readonly property real nameNaturalWidth: Math.ceil(nameMetrics.advanceWidth)
    readonly property real pairNaturalWidth: nameNaturalWidth + Style.space(8) + statusLabel.implicitWidth
    readonly property real pairBudget: {
      var inner = siteContent.width
      if (inner <= 0) return pairNaturalWidth
      return Math.max(0, inner - statusDot.width - removeBtn.implicitWidth - siteContent.spacing * 3)
    }

    TextMetrics {
      id: nameMetrics
      font: nameLabel.font
      text: nameLabel.text
    }

    MouseArea {
      id: sitePointer
      property bool dragging: false
      property bool suppressClick: false
      property real pressedX: 0
      property real pressedY: 0
      readonly property real dragThreshold: Style.space(4)

      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton
      preventStealing: dragging
      cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
      onEntered: if (!root.draggingSite) root.setSiteCursor(siteRow.rowIndex)
      onPressed: function(mouse) {
        dragging = false
        suppressClick = false
        pressedX = mouse.x
        pressedY = mouse.y
        root.setSiteCursor(siteRow.rowIndex)
      }
      onPositionChanged: function(mouse) {
        if (!(mouse.buttons & Qt.LeftButton) || !omaup) return
        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (!dragging && distance >= dragThreshold) {
          dragging = true
          root.beginSiteDrag(siteRow.rowIndex)
        }
        if (dragging) {
          var point = siteRow.mapToItem(siteColumn, mouse.x, mouse.y)
          root.updateSiteDrag(point.y)
        }
      }
      onReleased: function() {
        var wasDragging = dragging
        dragging = false
        if (wasDragging) {
          suppressClick = true
          root.endSiteDrag()
        }
      }
      onCanceled: {
        dragging = false
        suppressClick = false
        root.cancelSiteDrag()
      }
      onClicked: {
        if (suppressClick) return
        if (omaup) omaup.openTarget(siteRow.site)
      }
    }

    RowLayout {
      id: siteContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Rectangle {
        id: statusDot
        width: Style.space(8)
        height: Style.space(8)
        radius: width / 2
        color: siteRow.statusColor
        Layout.alignment: Qt.AlignVCenter
      }

      Item {
        id: nameStatus
        Layout.fillWidth: false
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: Math.min(siteRow.pairNaturalWidth, siteRow.pairBudget)
        Layout.maximumWidth: Math.min(siteRow.pairNaturalWidth, siteRow.pairBudget)
        Layout.minimumWidth: Math.min(siteRow.pairNaturalWidth, siteRow.pairBudget)
        implicitHeight: nameLabel.implicitHeight

        Text {
          id: nameLabel
          width: Math.min(siteRow.nameNaturalWidth, Math.max(0, parent.width - statusLabel.implicitWidth - Style.space(8)))
          text: siteRow.site ? String(siteRow.site.name || "Site") : "Site"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          id: statusLabel
          anchors.left: nameLabel.right
          anchors.leftMargin: Style.space(8)
          anchors.baseline: nameLabel.baseline
          text: Model.caption(siteRow.site)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Item {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        Layout.minimumWidth: 0
      }

      PanelActionButton {
        id: removeBtn
        iconText: "󰆴"
        tooltipText: "Remove"
        foreground: root.foreground
        hoverColor: root.urgent
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: {
          if (omaup && siteRow.site) omaup.removeTarget(siteRow.site.id)
        }
      }
    }
  }
}
