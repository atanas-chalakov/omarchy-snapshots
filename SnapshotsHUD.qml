import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool closingFromHost: false
  property bool useMockData: false

  readonly property string homeDir: Quickshell.env("HOME") || "/home/ac"
  readonly property string pluginPath: manifest && manifest.__sourceDir 
    ? manifest.__sourceDir 
    : (homeDir + "/.config/omarchy/plugins/ac.snapshots")
  readonly property string coreScript: pluginPath + "/bin/omarchy-snapshots-core"

  // State data
  property var statusData: ({})
  property var snapshotsList: []
  property var filteredSnapshots: []
  property int selectedIndex: 0
  readonly property var selectedSnapshot: (selectedIndex >= 0 && selectedIndex < filteredSnapshots.length)
    ? filteredSnapshots[selectedIndex]
    : null
  property string currentFilter: "all" // "all", "update", "manual", "pinned"
  property string searchQuery: ""
  property bool isRefreshing: false
  property string statusNotification: ""

  // Active Modals
  property bool showCreateModal: false
  property string newSnapshotDesc: ""
  property bool newSnapshotImportant: false

  property bool showDiffModal: false
  property var activeDiffData: null
  property int activeDiffSnapshotId: 0
  property string diffFilterQuery: ""

  property bool showRestoreModal: false
  property var activeRestoreSnapshot: null

  property bool showDeleteModal: false
  property var activeDeleteSnapshot: null

  function notify(msg) {
    statusNotification = msg
    notifyTimer.restart()
  }

  Timer {
    id: notifyTimer
    interval: 3500
    repeat: false
    onTriggered: root.statusNotification = ""
  }

  function refresh() {
    if (statusProcess.running) return
    isRefreshing = true
    var args = [coreScript, "status"]
    if (useMockData) args.push("--mock")
    statusProcess.command = args
    statusProcess.running = true
  }

  function applyFilter() {
    var list = root.snapshotsList || []
    var query = root.searchQuery.trim().toLowerCase()
    var filter = root.currentFilter

    var result = []
    for (var i = 0; i < list.length; i++) {
      var item = list[i]
      var desc = (item.description || "").toLowerCase()
      var type = (item.type || "").toLowerCase()
      var isPinned = item.important === true

      // Filter category
      if (filter === "pinned" && !isPinned) continue
      if (filter === "update" && desc.indexOf("update") === -1) continue
      if (filter === "manual" && (desc.indexOf("update") !== -1 || type === "timeline")) continue

      // Search query
      if (query.length > 0) {
        if (desc.indexOf(query) === -1 && String(item.id).indexOf(query) === -1 && (item.relativeAge || "").toLowerCase().indexOf(query) === -1) {
          continue
        }
      }

      result.push(item)
    }
    root.filteredSnapshots = result
    if (result.length === 0) {
      root.selectedIndex = -1
    } else if (root.selectedIndex < 0 || root.selectedIndex >= result.length) {
      root.selectedIndex = 0
    }
  }

  function selectNext() {
    if (filteredSnapshots.length === 0) return
    if (selectedIndex < filteredSnapshots.length - 1) {
      selectedIndex++
    } else {
      selectedIndex = 0
    }
    timelineView.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectPrev() {
    if (filteredSnapshots.length === 0) return
    if (selectedIndex > 0) {
      selectedIndex--
    } else {
      selectedIndex = filteredSnapshots.length - 1
    }
    timelineView.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function cycleFilter(step) {
    var filters = ["all", "update", "manual", "pinned"]
    var idx = filters.indexOf(currentFilter)
    if (idx === -1) idx = 0
    var next = (idx + step + filters.length) % filters.length
    currentFilter = filters[next]
  }

  onCurrentFilterChanged: applyFilter()
  onSearchQueryChanged: applyFilter()
  onSnapshotsListChanged: applyFilter()

  function openCreateModal(initialDesc) {
    newSnapshotDesc = initialDesc || ""
    newSnapshotImportant = false
    showCreateModal = true
    Qt.callLater(function() {
      if (typeof createDescInput !== "undefined") {
        createDescInput.forceActiveFocus()
      }
    })
  }

  function submitCreateSnapshot() {
    var desc = newSnapshotDesc.trim()
    if (!desc) {
      desc = "Manual checkpoint " + Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm")
    }
    showCreateModal = false
    notify("Creating checkpoint '" + desc + "'...")

    var args = [coreScript, "create", "--desc", desc]
    if (newSnapshotImportant) args.push("--important")
    if (useMockData) args.push("--mock")

    if (actionProcess.running) actionProcess.running = false
    actionProcess.command = args
    actionProcess.running = true
  }

  function togglePin(snapId, currentImportant) {
    var action = currentImportant ? "unpin" : "pin"
    notify((currentImportant ? "Unpinning" : "Pinning") + " snapshot #" + snapId + "...")
    var args = [coreScript, action, "--id", String(snapId)]
    if (useMockData) args.push("--mock")
    if (actionProcess.running) actionProcess.running = false
    actionProcess.command = args
    actionProcess.running = true
  }

  function inspectDiff(snapId) {
    activeDiffSnapshotId = snapId
    activeDiffData = null
    diffFilterQuery = ""
    showDiffModal = true
    notify("Calculating changes for #" + snapId + "...")

    var args = [coreScript, "diff", "--id", String(snapId)]
    if (useMockData) args.push("--mock")
    diffProcess.command = args
    diffProcess.running = true
  }

  function browseSnapshot(snapId) {
    var path = "/.snapshots/" + snapId + "/snapshot"
    notify("Opening " + path + " in file browser...")
    browseProcess.command = ["xdg-open", path]
    browseProcess.running = true
  }

  function confirmRestore(snapshot) {
    activeRestoreSnapshot = snapshot
    showRestoreModal = true
  }

  function executeRestore() {
    if (!activeRestoreSnapshot) return
    var id = activeRestoreSnapshot.id
    showRestoreModal = false
    if (keyCatcher) keyCatcher.forceActiveFocus()
    notify("Launching recovery for snapshot #" + id + "...")
    var args = [coreScript, "restore", "--id", String(id)]
    if (useMockData) args.push("--mock")

    if (actionProcess.running) actionProcess.running = false
    actionProcess.command = args
    actionProcess.running = true
  }

  function confirmDelete(snapshot) {
    activeDeleteSnapshot = snapshot
    showDeleteModal = true
  }

  function executeDelete() {
    if (!activeDeleteSnapshot) return
    var id = activeDeleteSnapshot.id
    showDeleteModal = false
    if (keyCatcher) keyCatcher.forceActiveFocus()
    notify("Pruning snapshot #" + id + "...")
    var args = [coreScript, "delete", "--id", String(id)]
    if (useMockData) args.push("--mock")
    actionProcess.command = args
    actionProcess.running = true
  }

  function authorizeAccess() {
    notify("Requesting authorization for passwordless access...")
    authProcess.command = [coreScript, "authorize"]
    authProcess.running = true
  }

  function open(payloadJson) {
    closingFromHost = false
    window.visible = true
    if (windowFocusProcess.running) windowFocusProcess.running = false
    windowFocusProcess.running = true
    if (payloadJson) {
      try {
        var parsed = JSON.parse(String(payloadJson))
        if (parsed.mock === true) root.useMockData = true
        if (parsed.action === "create") root.openCreateModal(parsed.desc || "")
        if (parsed.action === "diff") {
          Qt.callLater(function() { root.inspectDiff(parsed.id || 19) })
        }
        if (parsed.action === "restore") {
          Qt.callLater(function() {
            root.confirmRestore({
              id: parsed.id || 19,
              date: "2026-10-07 17:05:53",
              description: "Pre-Update (omarchy 4.0.2)"
            })
          })
        }
      } catch(e) {}
    }
    refresh()
    Qt.callLater(function() {
      if (windowFocusProcess.running) windowFocusProcess.running = false
      windowFocusProcess.running = true
      if (keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide((root.manifest && root.manifest.id) || "ac.snapshots")
    } else {
      close()
    }
  }

  // Processes
  Process {
    id: statusProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.isRefreshing = false
        try {
          var res = JSON.parse(text)
          root.statusData = res
          var snaps = []
          if (res.configs && res.configs.length > 0) {
            for (var c = 0; c < res.configs.length; c++) {
              if (res.configs[c].snapshots) {
                snaps = snaps.concat(res.configs[c].snapshots)
              }
            }
          }
          root.snapshotsList = snaps
        } catch(e) {
          console.warn("[omarchy-snapshots] Failed to parse status JSON:", e)
        }
      }
    }
  }

  Process {
    id: actionProcess
    property string stderrOutput: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var res = JSON.parse(text)
          if (res.ok) {
            root.notify(res.message || "Action completed.")
            root.refresh()
          } else {
            root.notify("Error: " + (res.error || "Action failed."))
          }
        } catch(e) {
          if (text && text.trim().length > 0) {
            root.notify(text.trim())
            root.refresh()
          }
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        actionProcess.stderrOutput = text.trim()
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && actionProcess.stderrOutput.length > 0) {
        root.notify("Error: " + actionProcess.stderrOutput)
      }
    }
  }

  Process {
    id: diffProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var res = JSON.parse(text)
          if (res.ok) {
            root.activeDiffData = res
          } else {
            root.notify("Diff failed: " + (res.error || "Unknown error"))
          }
        } catch(e) {}
      }
    }
  }

  Process {
    id: browseProcess
  }

  Process {
    id: restoreProcess
  }

  Process {
    id: authProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var res = JSON.parse(text)
          if (res.ok) {
            root.notify("Permissions granted! Refreshing...")
            root.refresh()
          } else {
            root.notify("Authorization failed: " + (res.error || "Denied"))
          }
        } catch(e) {}
      }
    }
  }

  Process {
    id: windowFocusProcess
    command: ["hyprctl", "dispatch", "hl.dsp.focus({ window = \"title:Snapshots & Recovery\" })"]
  }

  Component.onCompleted: {
    refresh()
    Qt.callLater(function() {
      if (keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  // Floating Window Container
  FloatingWindow {
    id: window
    title: "Snapshots & Recovery"
    color: Color.background
    visible: false
    implicitWidth: 880
    implicitHeight: 640
    minimumSize: Qt.size(620, 480)
    maximumSize: Qt.size(1400, 960)

    onVisibleChanged: {
      if (visible) {
        if (windowFocusProcess.running) windowFocusProcess.running = false
        windowFocusProcess.running = true
        Qt.callLater(function() {
          if (keyCatcher) keyCatcher.forceActiveFocus()
        })
      } else {
        if (!root.closingFromHost && root.shell && typeof root.shell.hide === "function") {
          root.shell.hide((root.manifest && root.manifest.id) || "ac.snapshots")
        }
      }
    }

    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true

      readonly property var mainContainer: keyCatcher

      // Secondary navigation key handler forwarded from keyCatcher
      Item {
        id: navKeyHandler
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Home) {
            if (root.filteredSnapshots.length > 0) {
              root.selectedIndex = 0
              timelineView.positionViewAtIndex(0, ListView.Contain)
            }
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            if (root.filteredSnapshots.length > 0) {
              root.selectedIndex = root.filteredSnapshots.length - 1
              timelineView.positionViewAtIndex(root.selectedIndex, ListView.Contain)
            }
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            if (root.filteredSnapshots.length > 0) {
              root.selectedIndex = Math.min(root.filteredSnapshots.length - 1, root.selectedIndex + 5)
              timelineView.positionViewAtIndex(root.selectedIndex, ListView.Contain)
            }
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            if (root.filteredSnapshots.length > 0) {
              root.selectedIndex = Math.max(0, root.selectedIndex - 5)
              timelineView.positionViewAtIndex(root.selectedIndex, ListView.Contain)
            }
            event.accepted = true
          } else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
            root.selectNext()
            event.accepted = true
          } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
            root.selectPrev()
            event.accepted = true
          } else if (event.key === Qt.Key_C) {
            root.openCreateModal()
            event.accepted = true
          } else if (event.key === Qt.Key_D) {
            if (root.selectedSnapshot) root.inspectDiff(root.selectedSnapshot.id)
            event.accepted = true
          } else if (event.key === Qt.Key_B) {
            if (root.selectedSnapshot) root.browseSnapshot(root.selectedSnapshot.id)
            event.accepted = true
          } else if (event.key === Qt.Key_P) {
            if (root.selectedSnapshot) root.togglePin(root.selectedSnapshot.id, root.selectedSnapshot.important)
            event.accepted = true
          } else if (event.key === Qt.Key_R) {
            if (root.showRestoreModal) root.executeRestore()
            else if (root.selectedSnapshot) root.confirmRestore(root.selectedSnapshot)
            event.accepted = true
          } else if (event.key === Qt.Key_X) {
            if (root.showDeleteModal) root.executeDelete()
            else if (root.selectedSnapshot) root.confirmDelete(root.selectedSnapshot)
            event.accepted = true
          } else if (event.key === Qt.Key_F || event.key === Qt.Key_Slash) {
            searchInput.forceActiveFocus()
            searchInput.selectAll()
            event.accepted = true
          } else if (event.key === Qt.Key_G) {
            root.refresh()
            event.accepted = true
          } else if (event.key === Qt.Key_1) {
            root.currentFilter = "all"
            event.accepted = true
          } else if (event.key === Qt.Key_2) {
            root.currentFilter = "update"
            event.accepted = true
          } else if (event.key === Qt.Key_3) {
            root.currentFilter = "manual"
            event.accepted = true
          } else if (event.key === Qt.Key_4) {
            root.currentFilter = "pinned"
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.showRestoreModal) {
              root.executeRestore()
            } else if (root.showDeleteModal) {
              root.executeDelete()
            } else if (root.selectedSnapshot) {
              root.inspectDiff(root.selectedSnapshot.id)
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
            if (root.showDiffModal) {
              root.showDiffModal = false
              keyCatcher.forceActiveFocus()
            } else if (root.showCreateModal) {
              root.showCreateModal = false
              keyCatcher.forceActiveFocus()
            } else if (root.showRestoreModal) {
              root.showRestoreModal = false
              keyCatcher.forceActiveFocus()
            } else if (root.showDeleteModal) {
              root.showDeleteModal = false
              keyCatcher.forceActiveFocus()
            } else {
              root.dismiss()
            }
            event.accepted = true
          }
        }
      }

      // Drop-in standard Omarchy panel key catcher with BeforeItem priority
      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.forwardTo: [navKeyHandler]
        blocked: (searchInput && searchInput.activeFocus)
          || (typeof createDescInput !== "undefined" && createDescInput.activeFocus)
          || (typeof diffFilterInput !== "undefined" && diffFilterInput.activeFocus)

        onMoveRequested: function(dx, dy) {
          if (dy > 0) root.selectNext()
          else if (dy < 0) root.selectPrev()
          else if (dx > 0) root.cycleFilter(1)
          else if (dx < 0) root.cycleFilter(-1)
        }

        onActivateRequested: function() {
          if (root.showRestoreModal) {
            root.executeRestore()
          } else if (root.showDeleteModal) {
            root.executeDelete()
          } else if (root.selectedSnapshot) {
            root.inspectDiff(root.selectedSnapshot.id)
          }
        }

        onCloseRequested: function() {
          if (root.showDiffModal) {
            root.showDiffModal = false
            keyCatcher.forceActiveFocus()
          } else if (root.showCreateModal) {
            root.showCreateModal = false
            keyCatcher.forceActiveFocus()
          } else if (root.showRestoreModal) {
            root.showRestoreModal = false
            keyCatcher.forceActiveFocus()
          } else if (root.showDeleteModal) {
            root.showDeleteModal = false
            keyCatcher.forceActiveFocus()
          } else if (searchInput && searchInput.text.length > 0) {
            searchInput.text = ""
            keyCatcher.forceActiveFocus()
          } else {
            root.dismiss()
          }
        }

        onDeleteRequested: function() {
          if (root.showDeleteModal) {
            root.executeDelete()
          } else if (root.selectedSnapshot) {
            root.confirmDelete(root.selectedSnapshot)
          }
        }

        onTextKey: function(key, modifiers) {
          var k = String(key || "").toLowerCase()
          if (k === "c" || k === "n") {
            root.openCreateModal()
          } else if (k === "d") {
            if (root.selectedSnapshot) root.inspectDiff(root.selectedSnapshot.id)
          } else if (k === "b") {
            if (root.selectedSnapshot) root.browseSnapshot(root.selectedSnapshot.id)
          } else if (k === "p") {
            if (root.selectedSnapshot) root.togglePin(root.selectedSnapshot.id, root.selectedSnapshot.important)
          } else if (k === "r") {
            if (root.showRestoreModal) root.executeRestore()
            else if (root.selectedSnapshot) root.confirmRestore(root.selectedSnapshot)
          } else if (k === "f" || key === "/") {
            searchInput.forceActiveFocus()
            searchInput.selectAll()
          } else if (k === "g") {
            root.refresh()
          } else if (k === "q") {
            if (root.showDiffModal) {
              root.showDiffModal = false
              keyCatcher.forceActiveFocus()
            } else if (root.showCreateModal) {
              root.showCreateModal = false
              keyCatcher.forceActiveFocus()
            } else if (root.showRestoreModal) {
              root.showRestoreModal = false
              keyCatcher.forceActiveFocus()
            } else if (root.showDeleteModal) {
              root.showDeleteModal = false
              keyCatcher.forceActiveFocus()
            } else {
              root.dismiss()
            }
          } else if (key === "1") {
            root.currentFilter = "all"
          } else if (key === "2") {
            root.currentFilter = "update"
          } else if (key === "3") {
            root.currentFilter = "manual"
          } else if (key === "4") {
            root.currentFilter = "pinned"
          }
        }
      }

      // Background click returns active keyboard focus to keyCatcher
      MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: keyCatcher.forceActiveFocus()
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        // Header Section
        RowLayout {
          Layout.fillWidth: true
          spacing: 14

          Rectangle {
            width: 44
            height: 44
            radius: 12
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
            border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.3)
            border.width: 1

            Text {
              anchors.centerIn: parent
              text: "󰆼"
              font.pixelSize: 22
              color: Color.accent
            }
          }

          ColumnLayout {
            spacing: 2
            Layout.fillWidth: true

            RowLayout {
              spacing: 8
              Text {
                text: "Snapshots & Recovery"
                font.pixelSize: 18
                font.weight: Font.Bold
                color: Color.foreground
              }

              // Health Status Pill
              Rectangle {
                property var health: (root.statusData && root.statusData.health) || ({})
                property string status: health.status || "warning"
                implicitHeight: 22
                implicitWidth: healthLabel.implicitWidth + 16
                radius: 11
                color: status === "healthy" ? Qt.rgba(0.06, 0.72, 0.51, 0.18) : (status === "error" ? Qt.rgba(0.94, 0.27, 0.27, 0.2) : Qt.rgba(0.96, 0.62, 0.04, 0.2))
                border.color: status === "healthy" ? "#10B981" : (status === "error" ? "#EF4444" : "#F59E0B")
                border.width: 1

                RowLayout {
                  anchors.centerIn: parent
                  spacing: 4
                  Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: parent.parent.border.color
                  }
                  Text {
                    id: healthLabel
                    text: (root.statusData && root.statusData.health && root.statusData.health.label) || "Checking..."
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: Color.foreground
                  }
                }
              }
            }

            Text {
              text: (root.statusData && root.statusData.health && root.statusData.health.reason) || "Checking Btrfs subvolumes and bootloader synchronization..."
              font.pixelSize: 12
              color: Color.muted
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          // Top Action Buttons
          RowLayout {
            spacing: 8

            // Mock toggle chip (useful for testing or demonstration)
            Rectangle {
              implicitHeight: 34
              implicitWidth: mockToggleText.implicitWidth + 20
              radius: 8
              color: root.useMockData ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
              border.color: root.useMockData ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
              border.width: 1

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.useMockData = !root.useMockData
                  root.refresh()
                }
              }

              Text {
                id: mockToggleText
                anchors.centerIn: parent
                text: root.useMockData ? "Demo Data: ON" : "Demo Data: OFF"
                font.pixelSize: 11
                color: root.useMockData ? Color.accent : Color.muted
              }
            }

            // Refresh Button
            Rectangle {
              implicitHeight: 34
              implicitWidth: refreshBtnLayout.implicitWidth + 18
              radius: 8
              color: refreshMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
              border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
              border.width: 1

              MouseArea {
                id: refreshMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.refresh()
                  keyCatcher.forceActiveFocus()
                }
              }

              RowLayout {
                id: refreshBtnLayout
                anchors.centerIn: parent
                spacing: 6
                Text {
                  text: "󰑐"
                  font.pixelSize: 13
                  color: root.isRefreshing ? Color.accent : Color.foreground
                  rotation: root.isRefreshing ? 180 : 0
                  Behavior on rotation { NumberAnimation { duration: 400 } }
                }
                Rectangle {
                  implicitHeight: 16
                  implicitWidth: keyRefTxt.implicitWidth + 6
                  radius: 3
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                  Text {
                    id: keyRefTxt
                    anchors.centerIn: parent
                    text: "G"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: Color.muted
                  }
                }
              }
            }

            // New Checkpoint Button
            Rectangle {
              implicitHeight: 34
              implicitWidth: createBtnLayout.implicitWidth + 22
              radius: 8
              color: createMouse.containsMouse ? Qt.darker(Color.accent, 1.1) : Color.accent

              MouseArea {
                id: createMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.openCreateModal()
                  keyCatcher.forceActiveFocus()
                }
              }

              RowLayout {
                id: createBtnLayout
                anchors.centerIn: parent
                spacing: 6
                Text {
                  text: "󰐕"
                  font.pixelSize: 14
                  color: Color.background
                }
                Text {
                  text: "New Checkpoint"
                  font.pixelSize: 12
                  font.weight: Font.DemiBold
                  color: Color.background
                }
                Rectangle {
                  implicitHeight: 16
                  implicitWidth: keyNewTxt.implicitWidth + 6
                  radius: 3
                  color: Qt.rgba(0, 0, 0, 0.25)
                  Text {
                    id: keyNewTxt
                    anchors.centerIn: parent
                    text: "C"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: Color.background
                  }
                }
              }
            }

            // Close Window Button
            Rectangle {
              implicitHeight: 34
              implicitWidth: closeBtnLayout.implicitWidth + 16
              radius: 8
              color: closeMouse.containsMouse ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.2) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
              border.color: closeMouse.containsMouse ? Color.urgent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
              border.width: 1

              MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dismiss()
              }

              RowLayout {
                id: closeBtnLayout
                anchors.centerIn: parent
                spacing: 5
                Text {
                  text: "󰅖"
                  font.pixelSize: 13
                  color: closeMouse.containsMouse ? Color.urgent : Color.muted
                }
                Rectangle {
                  implicitHeight: 16
                  implicitWidth: keyEscTxt.implicitWidth + 6
                  radius: 3
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                  Text {
                    id: keyEscTxt
                    anchors.centerIn: parent
                    text: "Esc"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: Color.muted
                  }
                }
              }
            }
          }
        }

        // Notification Banner
        Rectangle {
          visible: root.statusNotification.length > 0
          Layout.fillWidth: true
          implicitHeight: 32
          radius: 8
          color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
          border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.3)
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8
            Text {
              text: "󰋼"
              font.pixelSize: 13
              color: Color.accent
            }
            Text {
              text: root.statusNotification
              font.pixelSize: 12
              color: Color.foreground
              Layout.fillWidth: true
              elide: Text.ElideRight
            }
          }
        }

        // Authorization Needed Card
        Rectangle {
          visible: (root.statusData && root.statusData.needsPermission === true) && !root.useMockData
          Layout.fillWidth: true
          implicitHeight: authLayout.implicitHeight + 20
          radius: 10
          color: Qt.rgba(0.96, 0.62, 0.04, 0.12)
          border.color: Qt.rgba(0.96, 0.62, 0.04, 0.35)
          border.width: 1

          RowLayout {
            id: authLayout
            anchors.fill: parent
            anchors.margins: 10
            spacing: 12

            Text {
              text: "󰌋"
              font.pixelSize: 22
              color: "#F59E0B"
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 2
              Text {
                text: "Desktop Permission Required"
                font.pixelSize: 13
                font.weight: Font.Bold
                color: Color.foreground
              }
              Text {
                text: "Grant one-time access to manage Snapper recovery points passwordlessly from your desktop."
                font.pixelSize: 11
                color: Color.muted
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
              }
            }

            Rectangle {
              implicitHeight: 30
              implicitWidth: authBtnText.implicitWidth + 20
              radius: 6
              color: "#F59E0B"

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.authorizeAccess()
              }

              Text {
                id: authBtnText
                anchors.centerIn: parent
                text: "Authorize Access"
                font.pixelSize: 11
                font.weight: Font.Bold
                color: "#181825"
              }
            }
          }
        }

        // Storage & Telemetry Bar
        Rectangle {
          Layout.fillWidth: true
          implicitHeight: 46
          radius: 10
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.03)
          border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 16

            // Storage telemetry
            RowLayout {
              spacing: 8
              Text {
                text: "󰋊"
                font.pixelSize: 14
                color: Color.muted
              }
              Text {
                property var storage: (root.statusData && root.statusData.storage) || ({})
                text: "Storage: " + (storage.fsAvailHuman || "0 B") + " free of " + (storage.fsSizeHuman || "0 B")
                font.pixelSize: 12
                color: Color.foreground
              }
            }

            // Usage meter bar
            Rectangle {
              Layout.fillWidth: true
              height: 6
              radius: 3
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)

              Rectangle {
                property int pct: (root.statusData && root.statusData.storage && root.statusData.storage.usedPercent) || 0
                width: parent.width * Math.min(1.0, (pct / 100.0))
                height: parent.height
                radius: 3
                color: pct > 85 ? Color.urgent : (pct > 70 ? "#F59E0B" : Color.accent)
              }
            }

            // Bootloader Sync Status
            RowLayout {
              spacing: 6
              property bool syncActive: (root.statusData && root.statusData.health && root.statusData.health.limineSyncActive) === true
              Text {
                text: parent.syncActive ? "󰌢" : "󰌣"
                font.pixelSize: 14
                color: parent.syncActive ? "#10B981" : "#EF4444"
              }
              Text {
                text: parent.syncActive ? "Limine Boot Sync Active" : "Boot Sync Offline"
                font.pixelSize: 11
                color: parent.syncActive ? Color.muted : "#EF4444"
              }
            }
          }
        }

        // Filter and Search Toolbar
        RowLayout {
          Layout.fillWidth: true
          spacing: 10

          // Filter chips
          RowLayout {
            spacing: 6
            Repeater {
              model: [
                { id: "all", label: "All Points (" + root.snapshotsList.length + ")", key: "1" },
                { id: "update", label: "Pre-Update", key: "2" },
                { id: "manual", label: "Manual", key: "3" },
                { id: "pinned", label: "Pinned 📌", key: "4" }
              ]

              Rectangle {
                property bool selected: root.currentFilter === modelData.id
                implicitHeight: 28
                implicitWidth: chipRowLayout.implicitWidth + 20
                radius: 14
                color: selected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
                border.color: selected ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                border.width: 1

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.currentFilter = modelData.id
                    keyCatcher.forceActiveFocus()
                  }
                }

                RowLayout {
                  id: chipRowLayout
                  anchors.centerIn: parent
                  spacing: 6

                  Text {
                    id: chipText
                    text: modelData.label
                    font.pixelSize: 11
                    font.weight: selected ? Font.Bold : Font.Normal
                    color: selected ? Color.accent : Color.muted
                  }

                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: chipKeyText.implicitWidth + 6
                    radius: 3
                    color: selected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                    Text {
                      id: chipKeyText
                      anchors.centerIn: parent
                      text: modelData.key
                      font.pixelSize: 9
                      font.weight: Font.Bold
                      color: selected ? Color.accent : Color.muted
                    }
                  }
                }
              }
            }
          }

          Item { Layout.fillWidth: true }

          // Search Field
          Rectangle {
            implicitHeight: 28
            implicitWidth: 190
            radius: 14
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
            border.color: searchInput.activeFocus ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
            border.width: 1

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              spacing: 6

              Text {
                text: ""
                font.pixelSize: 11
                color: Color.muted
              }

              TextInput {
                id: searchInput
                Layout.fillWidth: true
                font.pixelSize: 11
                color: Color.foreground
                clip: true
                onTextChanged: root.searchQuery = text
                Keys.onEscapePressed: {
                  searchInput.text = ""
                  keyCatcher.forceActiveFocus()
                }
                Keys.onDownPressed: {
                  keyCatcher.forceActiveFocus()
                  if (root.filteredSnapshots.length > 0) root.selectedIndex = 0
                }
                Keys.onReturnPressed: {
                  keyCatcher.forceActiveFocus()
                  if (root.filteredSnapshots.length > 0) root.selectedIndex = 0
                }

                Text {
                  anchors.fill: parent
                  text: "Search points..."
                  font.pixelSize: 11
                  color: Color.muted
                  visible: !parent.text && !parent.activeFocus
                }
              }

              // Key hint [/] when input is inactive and empty
              Rectangle {
                visible: searchInput.text.length === 0 && !searchInput.activeFocus
                implicitHeight: 16
                implicitWidth: searchKeyBadge.implicitWidth + 6
                radius: 3
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                Text {
                  id: searchKeyBadge
                  anchors.centerIn: parent
                  text: "/"
                  font.pixelSize: 9
                  font.weight: Font.Bold
                  color: Color.muted
                }
              }

              Text {
                visible: searchInput.text.length > 0
                text: "󰅖"
                font.pixelSize: 11
                color: Color.muted
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    searchInput.text = ""
                    keyCatcher.forceActiveFocus()
                  }
                }
              }
            }
          }
        }

        // Snapshots Timeline List
        ListView {
          id: timelineView
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: 8
          model: root.filteredSnapshots
          ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
          }

            // Empty state placeholder
            Item {
              visible: root.filteredSnapshots.length === 0
              anchors.centerIn: parent
              width: parent.width
              height: 200

              ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: "󰆼"
                  font.pixelSize: 36
                  color: Color.muted
                }
                Text {
                  Layout.alignment: Qt.AlignHCenter
                  text: root.snapshotsList.length === 0 ? "No snapshots found on system." : "No snapshots match current filter."
                  font.pixelSize: 13
                  color: Color.muted
                }
              }
            }

            // Snapshot Item Card
            delegate: Rectangle {
              readonly property bool isSelected: index === root.selectedIndex
              width: timelineView.width
              implicitHeight: cardLayout.implicitHeight + 20
              radius: 10
              color: isSelected
                ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
                : (cardMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.02))
              border.color: isSelected
                ? Color.accent
                : (modelData.important ? Qt.rgba(0.96, 0.62, 0.04, 0.4) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08))
              border.width: isSelected ? 2 : 1

              MouseArea {
                id: cardMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.selectedIndex = index
                  keyCatcher.forceActiveFocus()
                }
                onDoubleClicked: root.inspectDiff(modelData.id)
              }

              RowLayout {
                id: cardLayout
                anchors.fill: parent
                anchors.margins: 12
                spacing: 14

                // Snapshot ID Badge
                Rectangle {
                  width: 44
                  height: 44
                  radius: 8
                  color: modelData.important ? Qt.rgba(0.96, 0.62, 0.04, 0.15) : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.1)
                  border.color: modelData.important ? "#F59E0B" : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25)
                  border.width: 1

                  ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0
                    Text {
                      Layout.alignment: Qt.AlignHCenter
                      text: "#" + modelData.id
                      font.pixelSize: 13
                      font.weight: Font.Bold
                      color: modelData.important ? "#F59E0B" : Color.accent
                    }
                    Text {
                      Layout.alignment: Qt.AlignHCenter
                      text: modelData.cleanup === "none" ? "keep" : "auto"
                      font.pixelSize: 9
                      color: Color.muted
                    }
                  }
                }

                // Information details
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 4

                  RowLayout {
                    spacing: 8
                    Text {
                      text: modelData.description || ("Snapshot #" + modelData.id)
                      font.pixelSize: 13
                      font.weight: Font.DemiBold
                      color: Color.foreground
                    }

                    // Pinned Chip
                    Rectangle {
                      visible: modelData.important === true
                      implicitHeight: 18
                      implicitWidth: 54
                      radius: 9
                      color: Qt.rgba(0.96, 0.62, 0.04, 0.2)
                      RowLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        Text { text: "📌"; font.pixelSize: 9 }
                        Text { text: "Pinned"; font.pixelSize: 9; font.weight: Font.Bold; color: "#F59E0B" }
                      }
                    }

                    // Bootable Chip
                    Rectangle {
                      implicitHeight: 18
                      implicitWidth: 60
                      radius: 9
                      color: Qt.rgba(0.06, 0.72, 0.51, 0.15)
                      RowLayout {
                        anchors.centerIn: parent
                        spacing: 2
                        Text { text: "󰌢"; font.pixelSize: 9; color: "#10B981" }
                        Text { text: "Bootable"; font.pixelSize: 9; color: "#10B981" }
                      }
                    }
                  }

                  RowLayout {
                    spacing: 12
                    Text {
                      text: "󰅐 " + (modelData.relativeAge || "")
                      font.pixelSize: 11
                      color: Color.muted
                    }
                    Text {
                      text: " " + (modelData.date || "")
                      font.pixelSize: 11
                      color: Color.muted
                    }
                  }
                }

                // Row Action Buttons
                RowLayout {
                  spacing: 6

                  // Diff Changes Button
                  Rectangle {
                    implicitHeight: 28
                    implicitWidth: diffBtnLayout.implicitWidth + 14
                    radius: 6
                    color: diffHover.containsMouse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2) : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.08)
                    border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.3)
                    border.width: 1

                    MouseArea {
                      id: diffHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.selectedIndex = index
                        root.inspectDiff(modelData.id)
                        keyCatcher.forceActiveFocus()
                      }
                    }

                    RowLayout {
                      id: diffBtnLayout
                      anchors.centerIn: parent
                      spacing: 5
                      Text { text: "󰙅"; font.pixelSize: 11; color: Color.accent }
                      Text { text: "Diff"; font.pixelSize: 11; font.weight: Font.Medium; color: Color.accent }
                      Rectangle {
                        implicitHeight: 15
                        implicitWidth: diffKeyTxt.implicitWidth + 6
                        radius: 3
                        color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25)
                        Text {
                          id: diffKeyTxt
                          anchors.centerIn: parent
                          text: "D"
                          font.pixelSize: 8
                          font.weight: Font.Bold
                          color: Color.accent
                        }
                      }
                    }
                  }

                  // Browse Files Button
                  Rectangle {
                    implicitHeight: 28
                    implicitWidth: browseBtnLayout.implicitWidth + 14
                    radius: 6
                    color: browseHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
                    border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                    border.width: 1

                    MouseArea {
                      id: browseHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.selectedIndex = index
                        root.browseSnapshot(modelData.id)
                        keyCatcher.forceActiveFocus()
                      }
                    }

                    RowLayout {
                      id: browseBtnLayout
                      anchors.centerIn: parent
                      spacing: 5
                      Text { text: "󰝰"; font.pixelSize: 11; color: Color.muted }
                      Text { text: "Browse"; font.pixelSize: 11; font.weight: Font.Medium; color: Color.foreground }
                      Rectangle {
                        implicitHeight: 15
                        implicitWidth: browseKeyTxt.implicitWidth + 6
                        radius: 3
                        color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                        Text {
                          id: browseKeyTxt
                          anchors.centerIn: parent
                          text: "B"
                          font.pixelSize: 8
                          font.weight: Font.Bold
                          color: Color.muted
                        }
                      }
                    }
                  }

                  // Pin / Unpin Button
                  Rectangle {
                    implicitHeight: 28
                    implicitWidth: pinBtnLayout.implicitWidth + 12
                    radius: 6
                    color: pinHover.containsMouse ? Qt.rgba(0.96, 0.62, 0.04, 0.2) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
                    border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                    border.width: 1

                    MouseArea {
                      id: pinHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.selectedIndex = index
                        root.togglePin(modelData.id, modelData.important)
                        keyCatcher.forceActiveFocus()
                      }
                    }

                    RowLayout {
                      id: pinBtnLayout
                      anchors.centerIn: parent
                      spacing: 4
                      Text {
                        text: modelData.important ? "📌" : "󰤱"
                        font.pixelSize: 11
                        color: modelData.important ? "#F59E0B" : Color.muted
                      }
                      Rectangle {
                        implicitHeight: 15
                        implicitWidth: pinKeyTxt.implicitWidth + 6
                        radius: 3
                        color: Qt.rgba(0.96, 0.62, 0.04, 0.2)
                        Text {
                          id: pinKeyTxt
                          anchors.centerIn: parent
                          text: "P"
                          font.pixelSize: 8
                          font.weight: Font.Bold
                          color: modelData.important ? "#F59E0B" : Color.muted
                        }
                      }
                    }
                  }

                  // Restore Button
                  Rectangle {
                    implicitHeight: 28
                    implicitWidth: restoreBtnLayout.implicitWidth + 14
                    radius: 6
                    color: restoreHover.containsMouse ? Qt.rgba(0.06, 0.72, 0.51, 0.2) : Qt.rgba(0.06, 0.72, 0.51, 0.08)
                    border.color: Qt.rgba(0.06, 0.72, 0.51, 0.3)
                    border.width: 1

                    MouseArea {
                      id: restoreHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.selectedIndex = index
                        root.confirmRestore(modelData)
                        keyCatcher.forceActiveFocus()
                      }
                    }

                    RowLayout {
                      id: restoreBtnLayout
                      anchors.centerIn: parent
                      spacing: 5
                      Text { text: "󰁯"; font.pixelSize: 11; color: "#10B981" }
                      Text { text: "Restore"; font.pixelSize: 11; font.weight: Font.Medium; color: "#10B981" }
                      Rectangle {
                        implicitHeight: 15
                        implicitWidth: resKeyTxt.implicitWidth + 6
                        radius: 3
                        color: Qt.rgba(0.06, 0.72, 0.51, 0.25)
                        Text {
                          id: resKeyTxt
                          anchors.centerIn: parent
                          text: "R"
                          font.pixelSize: 8
                          font.weight: Font.Bold
                          color: "#10B981"
                        }
                      }
                    }
                  }

                  // Delete Button
                  Rectangle {
                    implicitHeight: 28
                    implicitWidth: delBtnLayout.implicitWidth + 12
                    radius: 6
                    color: delHover.containsMouse ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.2) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
                    border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                    border.width: 1

                    MouseArea {
                      id: delHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.selectedIndex = index
                        root.confirmDelete(modelData)
                        keyCatcher.forceActiveFocus()
                      }
                    }

                    RowLayout {
                      id: delBtnLayout
                      anchors.centerIn: parent
                      spacing: 4
                      Text {
                        text: "󰆴"
                        font.pixelSize: 11
                        color: delHover.containsMouse ? Color.urgent : Color.muted
                      }
                      Rectangle {
                        implicitHeight: 15
                        implicitWidth: delKeyTxt.implicitWidth + 6
                        radius: 3
                        color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.2)
                        Text {
                          id: delKeyTxt
                          anchors.centerIn: parent
                          text: "X"
                          font.pixelSize: 8
                          font.weight: Font.Bold
                          color: Color.urgent
                        }
                      }
                    }
                  }
                }
              }
            }
          }

        // Keyboard Shortcuts Footer Hint Bar
        Rectangle {
          Layout.fillWidth: true
          implicitHeight: 34
          radius: 8
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.03)
          border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            // Hint: Select
            Rectangle {
              implicitHeight: 24
              implicitWidth: h1Layout.implicitWidth + 10
              radius: 4
              color: h1Mouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent"
              MouseArea {
                id: h1Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.selectNext(); keyCatcher.forceActiveFocus() }
              }
              RowLayout {
                id: h1Layout
                anchors.centerIn: parent
                spacing: 4
                Rectangle {
                  implicitHeight: 17
                  implicitWidth: keyTxt1.implicitWidth + 6
                  radius: 3
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                  Text { id: keyTxt1; anchors.centerIn: parent; text: "J/K"; font.pixelSize: 9; font.weight: Font.Bold; color: Color.foreground }
                }
                Text { text: "Select"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: New
            Rectangle {
              implicitHeight: 24
              implicitWidth: h2Layout.implicitWidth + 10
              radius: 4
              color: h2Mouse.containsMouse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12) : "transparent"
              MouseArea {
                id: h2Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.openCreateModal(); keyCatcher.forceActiveFocus() }
              }
              RowLayout {
                id: h2Layout
                anchors.centerIn: parent
                spacing: 4
                Rectangle {
                  implicitHeight: 17
                  implicitWidth: keyTxt2.implicitWidth + 6
                  radius: 3
                  color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2)
                  Text { id: keyTxt2; anchors.centerIn: parent; text: "C"; font.pixelSize: 9; font.weight: Font.Bold; color: Color.accent }
                }
                Text { text: "New"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: Diff
            Rectangle {
              implicitHeight: 24
              implicitWidth: h3Layout.implicitWidth + 10
              radius: 4
              color: h3Mouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent"
              MouseArea {
                id: h3Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.selectedSnapshot) root.inspectDiff(root.selectedSnapshot.id)
                  keyCatcher.forceActiveFocus()
                }
              }
              RowLayout {
                id: h3Layout
                anchors.centerIn: parent
                spacing: 4
                Rectangle {
                  implicitHeight: 17
                  implicitWidth: keyTxt3.implicitWidth + 6
                  radius: 3
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                  Text { id: keyTxt3; anchors.centerIn: parent; text: "D / ↵"; font.pixelSize: 9; font.weight: Font.Bold; color: Color.foreground }
                }
                Text { text: "Diff"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: Browse
            Rectangle {
              implicitHeight: 24
              implicitWidth: h4Layout.implicitWidth + 10
              radius: 4
              color: h4Mouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent"
              MouseArea {
                id: h4Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.selectedSnapshot) root.browseSnapshot(root.selectedSnapshot.id)
                  keyCatcher.forceActiveFocus()
                }
              }
              RowLayout {
                id: h4Layout
                anchors.centerIn: parent
                spacing: 4
                Rectangle {
                  implicitHeight: 17
                  implicitWidth: keyTxt4.implicitWidth + 6
                  radius: 3
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                  Text { id: keyTxt4; anchors.centerIn: parent; text: "B"; font.pixelSize: 9; font.weight: Font.Bold; color: Color.foreground }
                }
                Text { text: "Browse"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: Pin
            Rectangle {
              implicitHeight: 24
              implicitWidth: h5Layout.implicitWidth + 10
              radius: 4
              color: h5Mouse.containsMouse ? Qt.rgba(0.96, 0.62, 0.04, 0.12) : "transparent"
              MouseArea {
                id: h5Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.selectedSnapshot) root.togglePin(root.selectedSnapshot.id, root.selectedSnapshot.important)
                  keyCatcher.forceActiveFocus()
                }
              }
              RowLayout {
                id: h5Layout
                anchors.centerIn: parent
                spacing: 4
                Rectangle {
                  implicitHeight: 17
                  implicitWidth: keyTxt5.implicitWidth + 6
                  radius: 3
                  color: Qt.rgba(0.96, 0.62, 0.04, 0.2)
                  Text { id: keyTxt5; anchors.centerIn: parent; text: "P"; font.pixelSize: 9; font.weight: Font.Bold; color: "#F59E0B" }
                }
                Text { text: "Pin"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: Restore
            Rectangle {
              implicitHeight: 24
              implicitWidth: h6Layout.implicitWidth + 10
              radius: 4
              color: h6Mouse.containsMouse ? Qt.rgba(0.06, 0.72, 0.51, 0.12) : "transparent"
              MouseArea {
                id: h6Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.showRestoreModal) root.executeRestore()
                  else if (root.selectedSnapshot) root.confirmRestore(root.selectedSnapshot)
                  keyCatcher.forceActiveFocus()
                }
              }
              RowLayout {
                id: h6Layout
                anchors.centerIn: parent
                spacing: 4
                Rectangle {
                  implicitHeight: 17
                  implicitWidth: keyTxt6.implicitWidth + 6
                  radius: 3
                  color: Qt.rgba(0.06, 0.72, 0.51, 0.2)
                  Text { id: keyTxt6; anchors.centerIn: parent; text: "R"; font.pixelSize: 9; font.weight: Font.Bold; color: "#10B981" }
                }
                Text { text: "Restore"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: Delete
            Rectangle {
              implicitHeight: 24
              implicitWidth: h7Layout.implicitWidth + 10
              radius: 4
              color: h7Mouse.containsMouse ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.12) : "transparent"
              MouseArea {
                id: h7Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.showDeleteModal) root.executeDelete()
                  else if (root.selectedSnapshot) root.confirmDelete(root.selectedSnapshot)
                  keyCatcher.forceActiveFocus()
                }
              }
              RowLayout {
                id: h7Layout
                anchors.centerIn: parent
                spacing: 4
                Rectangle {
                  implicitHeight: 17
                  implicitWidth: keyTxt7.implicitWidth + 6
                  radius: 3
                  color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.2)
                  Text { id: keyTxt7; anchors.centerIn: parent; text: "X"; font.pixelSize: 9; font.weight: Font.Bold; color: Color.urgent }
                }
                Text { text: "Delete"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: Filter
            Rectangle {
              implicitHeight: 24
              implicitWidth: h8Layout.implicitWidth + 10
              radius: 4
              color: h8Mouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent"
              MouseArea {
                id: h8Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.cycleFilter(1); keyCatcher.forceActiveFocus() }
              }
              RowLayout {
                id: h8Layout
                anchors.centerIn: parent
                spacing: 4
                Rectangle {
                  implicitHeight: 17
                  implicitWidth: keyTxt8.implicitWidth + 6
                  radius: 3
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                  Text { id: keyTxt8; anchors.centerIn: parent; text: "1-4 / F"; font.pixelSize: 9; font.weight: Font.Bold; color: Color.foreground }
                }
                Text { text: "Filter"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: Search
            Rectangle {
              implicitHeight: 24
              implicitWidth: hSearchLayout.implicitWidth + 10
              radius: 4
              color: hSearchMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent"
              MouseArea {
                id: hSearchMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  searchInput.forceActiveFocus()
                  searchInput.selectAll()
                }
              }
              RowLayout {
                id: hSearchLayout
                anchors.centerIn: parent
                spacing: 4
                Rectangle {
                  implicitHeight: 17
                  implicitWidth: keyTxtSearch.implicitWidth + 6
                  radius: 3
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                  Text { id: keyTxtSearch; anchors.centerIn: parent; text: "/"; font.pixelSize: 9; font.weight: Font.Bold; color: Color.foreground }
                }
                Text { text: "Search"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: Refresh
            Rectangle {
              implicitHeight: 24
              implicitWidth: h9Layout.implicitWidth + 10
              radius: 4
              color: h9Mouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent"
              MouseArea {
                id: h9Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.refresh(); keyCatcher.forceActiveFocus() }
              }
              RowLayout {
                id: h9Layout
                anchors.centerIn: parent
                spacing: 4
                Rectangle {
                  implicitHeight: 17
                  implicitWidth: keyTxt9.implicitWidth + 6
                  radius: 3
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                  Text { id: keyTxt9; anchors.centerIn: parent; text: "G"; font.pixelSize: 9; font.weight: Font.Bold; color: Color.foreground }
                }
                Text { text: "Refresh"; font.pixelSize: 10; color: Color.muted }
              }
            }

            Item { Layout.fillWidth: true }

            // Hint: Close
            Rectangle {
              implicitHeight: 24
              implicitWidth: h10Layout.implicitWidth + 10
              radius: 4
              color: h10Mouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent"
              MouseArea {
                id: h10Mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dismiss()
              }
              RowLayout {
                id: h10Layout
                anchors.centerIn: parent
                spacing: 4
                Rectangle {
                  implicitHeight: 17
                  implicitWidth: keyTxt10.implicitWidth + 6
                  radius: 3
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                  Text { id: keyTxt10; anchors.centerIn: parent; text: "Esc / Q"; font.pixelSize: 9; font.weight: Font.Bold; color: Color.foreground }
                }
                Text { text: "Close"; font.pixelSize: 10; color: Color.muted }
              }
            }
          }
        }
      }

      // ==========================================
      // MODAL 1: CREATE SNAPSHOT DIALOG
      // ==========================================
      Rectangle {
        visible: root.showCreateModal
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.65)

        MouseArea {
          anchors.fill: parent
          onClicked: root.showCreateModal = false
        }

        Rectangle {
          anchors.centerIn: parent
          width: 480
          implicitHeight: createModalCol.implicitHeight + 36
          radius: 12
          color: Color.background
          border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.4)
          border.width: 1

          MouseArea { anchors.fill: parent }

          ColumnLayout {
            id: createModalCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            RowLayout {
              Layout.fillWidth: true
              Text {
                text: "Create Recovery Checkpoint"
                font.pixelSize: 16
                font.weight: Font.Bold
                color: Color.foreground
              }
              Item { Layout.fillWidth: true }
              Text {
                text: "󰅖"
                font.pixelSize: 14
                color: Color.muted
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showCreateModal = false
                }
              }
            }

            Text {
              text: "Creates an atomic Btrfs snapshot of the root filesystem that can be booted into if anything goes wrong."
              font.pixelSize: 12
              color: Color.muted
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            // Quick preset chips
            RowLayout {
              spacing: 6
              Repeater {
                model: [
                  "Before Update",
                  "Config Tweak",
                  "Driver Test",
                  "Clean State"
                ]
                Rectangle {
                  implicitHeight: 24
                  implicitWidth: chipPresetText.implicitWidth + 14
                  radius: 12
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
                  border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
                  border.width: 1

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      createDescInput.text = modelData
                      root.newSnapshotDesc = modelData
                      createDescInput.forceActiveFocus()
                    }
                  }

                  Text {
                    id: chipPresetText
                    anchors.centerIn: parent
                    text: modelData
                    font.pixelSize: 10
                    color: Color.muted
                  }
                }
              }
            }

            // Description Input Field
            Rectangle {
              Layout.fillWidth: true
              implicitHeight: 38
              radius: 8
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
              border.color: createDescInput.activeFocus ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)
              border.width: 1

              TextInput {
                id: createDescInput
                anchors.fill: parent
                anchors.margins: 10
                font.pixelSize: 12
                color: Color.foreground
                text: root.newSnapshotDesc
                onTextChanged: root.newSnapshotDesc = text
                focus: root.showCreateModal
                onAccepted: {
                  root.submitCreateSnapshot()
                  keyCatcher.forceActiveFocus()
                }
                Keys.onReturnPressed: {
                  root.submitCreateSnapshot()
                  keyCatcher.forceActiveFocus()
                }
                Keys.onEnterPressed: {
                  root.submitCreateSnapshot()
                  keyCatcher.forceActiveFocus()
                }
                Keys.onEscapePressed: {
                  root.showCreateModal = false
                  keyCatcher.forceActiveFocus()
                }

                Text {
                  anchors.fill: parent
                  text: "Enter checkpoint label (e.g., Before Hyprland tweak)..."
                  font.pixelSize: 12
                  color: Color.muted
                  visible: !parent.text && !parent.activeFocus
                }
              }
            }

            // Pin / Protect Checkbox
            RowLayout {
              spacing: 8
              Rectangle {
                width: 18
                height: 18
                radius: 4
                color: root.newSnapshotImportant ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)
                border.color: root.newSnapshotImportant ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2)
                border.width: 1

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.newSnapshotImportant = !root.newSnapshotImportant
                }

                Text {
                  visible: root.newSnapshotImportant
                  anchors.centerIn: parent
                  text: "✓"
                  font.pixelSize: 11
                  font.weight: Font.Bold
                  color: Color.background
                }
              }

              Text {
                text: "Pin checkpoint (protect permanently from automatic retention pruning)"
                font.pixelSize: 11
                color: Color.foreground
              }
            }

            // Action Buttons
            RowLayout {
              Layout.fillWidth: true
              spacing: 10
              Item { Layout.fillWidth: true }

              Rectangle {
                implicitHeight: 34
                implicitWidth: 80
                radius: 6
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showCreateModal = false
                }
                Text {
                  anchors.centerIn: parent
                  text: "Cancel"
                  font.pixelSize: 12
                  color: Color.muted
                }
              }

              Rectangle {
                implicitHeight: 34
                implicitWidth: 140
                radius: 6
                color: Color.accent
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.submitCreateSnapshot()
                }
                Text {
                  anchors.centerIn: parent
                  text: "Create Checkpoint"
                  font.pixelSize: 12
                  font.weight: Font.Bold
                  color: Color.background
                }
              }
            }
          }
        }
      }

      // ==========================================
      // MODAL 2: DIFF INSPECTOR MODAL
      // ==========================================
      Rectangle {
        visible: root.showDiffModal
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.7)

        MouseArea {
          anchors.fill: parent
          onClicked: root.showDiffModal = false
        }

        Rectangle {
          id: diffModalCard
          anchors.centerIn: parent
          width: 720
          height: 520
          radius: 12
          color: Color.background
          border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.4)
          border.width: 1
          focus: root.showDiffModal

          Keys.onEscapePressed: {
            root.showDiffModal = false
            keyCatcher.forceActiveFocus()
          }

          MouseArea { anchors.fill: parent }

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            RowLayout {
              Layout.fillWidth: true
              Text {
                text: "Changes in Snapshot #" + root.activeDiffSnapshotId + " vs Current System"
                font.pixelSize: 16
                font.weight: Font.Bold
                color: Color.foreground
              }
              Item { Layout.fillWidth: true }
              Text {
                text: "󰅖"
                font.pixelSize: 14
                color: Color.muted
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showDiffModal = false
                }
              }
            }

            // Summary row
            RowLayout {
              spacing: 12
              property var summary: (root.activeDiffData && root.activeDiffData.summary) || ({})
              Rectangle {
                implicitHeight: 24
                implicitWidth: addSummaryText.implicitWidth + 16
                radius: 12
                color: Qt.rgba(0.06, 0.72, 0.51, 0.15)
                Text {
                  id: addSummaryText
                  anchors.centerIn: parent
                  text: "+" + (parent.parent.summary.added || 0) + " Added"
                  font.pixelSize: 11
                  color: "#10B981"
                }
              }
              Rectangle {
                implicitHeight: 24
                implicitWidth: modSummaryText.implicitWidth + 16
                radius: 12
                color: Qt.rgba(0.96, 0.62, 0.04, 0.15)
                Text {
                  id: modSummaryText
                  anchors.centerIn: parent
                  text: "~" + (parent.parent.summary.modified || 0) + " Modified"
                  font.pixelSize: 11
                  color: "#F59E0B"
                }
              }
              Rectangle {
                implicitHeight: 24
                implicitWidth: delSummaryText.implicitWidth + 16
                radius: 12
                color: Qt.rgba(0.94, 0.27, 0.27, 0.15)
                Text {
                  id: delSummaryText
                  anchors.centerIn: parent
                  text: "-" + (parent.parent.summary.deleted || 0) + " Deleted"
                  font.pixelSize: 11
                  color: "#EF4444"
                }
              }
            }

            // Search filter
            Rectangle {
              Layout.fillWidth: true
              implicitHeight: 32
              radius: 6
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
              border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
              border.width: 1

              TextInput {
                id: diffFilterInput
                anchors.fill: parent
                anchors.margins: 8
                font.pixelSize: 11
                color: Color.foreground
                onTextChanged: root.diffFilterQuery = text.trim().toLowerCase()
                Keys.onEscapePressed: {
                  if (text.length > 0) text = ""
                  else root.showDiffModal = false
                  keyCatcher.forceActiveFocus()
                }

                Text {
                  anchors.fill: parent
                  text: "Filter changed files (e.g. /etc or .conf)..."
                  font.pixelSize: 11
                  color: Color.muted
                  visible: !parent.text
                }
              }
            }

            // Diff files list
            ScrollView {
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true

              ListView {
                width: parent.width
                spacing: 4
                model: {
                  var raw = (root.activeDiffData && root.activeDiffData.files) || []
                  if (!root.diffFilterQuery) return raw
                  var filtered = []
                  for (var i = 0; i < raw.length; i++) {
                    if (raw[i].path.toLowerCase().indexOf(root.diffFilterQuery) !== -1) {
                      filtered.push(raw[i])
                    }
                  }
                  return filtered
                }

                delegate: Rectangle {
                  width: parent.width
                  implicitHeight: 28
                  radius: 4
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.02)

                  RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 8

                    Rectangle {
                      width: 16
                      height: 16
                      radius: 3
                      color: modelData.status === "added" ? Qt.rgba(0.06, 0.72, 0.51, 0.2) : (modelData.status === "deleted" ? Qt.rgba(0.94, 0.27, 0.27, 0.2) : Qt.rgba(0.96, 0.62, 0.04, 0.2))
                      Text {
                        anchors.centerIn: parent
                        text: modelData.status === "added" ? "+" : (modelData.status === "deleted" ? "-" : "~")
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: modelData.status === "added" ? "#10B981" : (modelData.status === "deleted" ? "#EF4444" : "#F59E0B")
                      }
                    }

                    Text {
                      text: modelData.path
                      font.pixelSize: 11
                      font.family: Style.font.monospace
                      color: Color.foreground
                      Layout.fillWidth: true
                      elide: Text.ElideMiddle
                    }
                  }
                }
              }
            }
          }
        }
      }

      // ==========================================
      // MODAL 3: RESTORE CONFIRMATION DIALOG
      // ==========================================
      Rectangle {
        visible: root.showRestoreModal
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.7)

        MouseArea {
          anchors.fill: parent
          onClicked: root.showRestoreModal = false
        }

        Rectangle {
          id: restoreModalCard
          anchors.centerIn: parent
          width: 500
          implicitHeight: restoreCol.implicitHeight + 40
          radius: 12
          color: Color.background
          border.color: "#10B981"
          border.width: 1
          focus: root.showRestoreModal

          Keys.onEscapePressed: {
            root.showRestoreModal = false
            keyCatcher.forceActiveFocus()
          }
          Keys.onReturnPressed: root.executeRestore()
          Keys.onEnterPressed: root.executeRestore()

          MouseArea { anchors.fill: parent }

          ColumnLayout {
            id: restoreCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            RowLayout {
              spacing: 10
              Text { text: "󰁯"; font.pixelSize: 22; color: "#10B981" }
              Text {
                text: "Restore System to Snapshot #" + (root.activeRestoreSnapshot ? root.activeRestoreSnapshot.id : "")
                font.pixelSize: 16
                font.weight: Font.Bold
                color: Color.foreground
              }
            }

            Text {
              text: "This will invoke Limine & Snapper rollback to restore the root filesystem to the state recorded at " + (root.activeRestoreSnapshot ? root.activeRestoreSnapshot.date : "") + " (" + (root.activeRestoreSnapshot ? root.activeRestoreSnapshot.description : "") + ").\n\nAll package and root system changes made since this snapshot will be reverted upon reboot."
              font.pixelSize: 12
              color: Color.muted
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 10
              Item { Layout.fillWidth: true }

              Rectangle {
                implicitHeight: 34
                implicitWidth: 80
                radius: 6
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showRestoreModal = false
                }
                Text {
                  anchors.centerIn: parent
                  text: "Cancel"
                  font.pixelSize: 12
                  color: Color.muted
                }
              }

              Rectangle {
                implicitHeight: 34
                implicitWidth: 150
                radius: 6
                color: "#10B981"
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.executeRestore()
                }
                Text {
                  anchors.centerIn: parent
                  text: "Proceed to Restore"
                  font.pixelSize: 12
                  font.weight: Font.Bold
                  color: "#181825"
                }
              }
            }
          }
        }
      }

      // ==========================================
      // MODAL 4: DELETE CONFIRMATION DIALOG
      // ==========================================
      Rectangle {
        visible: root.showDeleteModal
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.7)

        MouseArea {
          anchors.fill: parent
          onClicked: root.showDeleteModal = false
        }

        Rectangle {
          id: deleteModalCard
          anchors.centerIn: parent
          width: 440
          implicitHeight: deleteCol.implicitHeight + 40
          radius: 12
          color: Color.background
          border.color: Color.urgent
          border.width: 1
          focus: root.showDeleteModal

          Keys.onEscapePressed: {
            root.showDeleteModal = false
            keyCatcher.forceActiveFocus()
          }
          Keys.onReturnPressed: root.executeDelete()
          Keys.onEnterPressed: root.executeDelete()

          MouseArea { anchors.fill: parent }

          ColumnLayout {
            id: deleteCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            RowLayout {
              spacing: 10
              Text { text: "󰆴"; font.pixelSize: 22; color: Color.urgent }
              Text {
                text: "Delete Snapshot #" + (root.activeDeleteSnapshot ? root.activeDeleteSnapshot.id : "")
                font.pixelSize: 16
                font.weight: Font.Bold
                color: Color.foreground
              }
            }

            Text {
              text: "Are you sure you want to permanently delete snapshot #" + (root.activeDeleteSnapshot ? root.activeDeleteSnapshot.id : "") + " (" + (root.activeDeleteSnapshot ? root.activeDeleteSnapshot.description : "") + ")?\nThis recovery point and its boot entry will be permanently removed."
              font.pixelSize: 12
              color: Color.muted
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 10
              Item { Layout.fillWidth: true }

              Rectangle {
                implicitHeight: 34
                implicitWidth: 80
                radius: 6
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showDeleteModal = false
                }
                Text {
                  anchors.centerIn: parent
                  text: "Cancel"
                  font.pixelSize: 12
                  color: Color.muted
                }
              }

              Rectangle {
                implicitHeight: 34
                implicitWidth: 120
                radius: 6
                color: Color.urgent
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.executeDelete()
                }
                Text {
                  anchors.centerIn: parent
                  text: "Delete"
                  font.pixelSize: 12
                  font.weight: Font.Bold
                  color: Color.background
                }
              }
            }
          }
        }
      }
    }
  }
}
