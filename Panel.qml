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

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var omaup: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property var sites: omaup && omaup.items ? omaup.items : []
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

  function ensureCursor() {
    if (!Array.isArray(sites) || sites.length === 0) {
      focusSection = "add"
      siteIndex = 0
      return
    }
    if (focusSection !== "sites" && focusSection !== "add") focusSection = "sites"
    if (siteIndex >= sites.length) siteIndex = sites.length - 1
    if (siteIndex < 0) siteIndex = 0
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
      scrollCursorIntoView()
      return
    }
    if (dy < 0 && sites.length > 0) {
      focusSection = "sites"
      siteIndex = sites.length - 1
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
    if (focusSection === "sites" && siteColumn && siteIndex >= 0 && siteIndex < siteColumn.children.length)
      scrollItemIntoView(siteColumn.children[siteIndex])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    adding = false
    addError = ""
    nameField.text = ""
    urlField.text = ""
    if (omaup && omaup.reloadTheme) omaup.reloadTheme()
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  } else {
    adding = false
    addError = ""
  }
  onSiteIndexChanged: scrollCursorIntoView()

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
        interactive: contentHeight > height
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

            PanelSectionHeader {
              text: "SITES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: siteColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.sites
                SiteRow {
                  required property var modelData
                  required property int index
                  width: siteColumn.width
                  site: modelData
                  rowIndex: index
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
          }
        }
      }
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

    hasCursor: root.sitesHasCursor && root.siteIndex === rowIndex
    foreground: root.foreground
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
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton
      onEntered: root.setSiteCursor(siteRow.rowIndex)
      onClicked: if (omaup) omaup.openTarget(siteRow.site)
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
