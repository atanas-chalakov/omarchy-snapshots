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

  Component.onCompleted: {
    refresh()
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

    Item {
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: {
        if (root.showDiffModal) root.showDiffModal = false
        else if (root.showCreateModal) root.showCreateModal = false
        else if (root.showRestoreModal) root.showRestoreModal = false
        else if (root.showDeleteModal) root.showDeleteModal = false
        else root.dismiss()
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
              implicitWidth: 34
              radius: 8
              color: refreshMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
              border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
              border.width: 1

              MouseArea {
                id: refreshMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refresh()
              }

              Text {
                anchors.centerIn: parent
                text: "󰑐"
                font.pixelSize: 14
                color: root.isRefreshing ? Color.accent : Color.foreground
                rotation: root.isRefreshing ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 400 } }
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
                onClicked: root.openCreateModal()
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
              }
            }

            // Close Window Button
            Rectangle {
              implicitHeight: 34
              implicitWidth: 34
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

              Text {
                anchors.centerIn: parent
                text: "󰅖"
                font.pixelSize: 14
                color: closeMouse.containsMouse ? Color.urgent : Color.muted
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
                { id: "all", label: "All Points (" + root.snapshotsList.length + ")" },
                { id: "update", label: "Pre-Update" },
                { id: "manual", label: "Manual" },
                { id: "pinned", label: "Pinned 📌" }
              ]

              Rectangle {
                property bool selected: root.currentFilter === modelData.id
                implicitHeight: 28
                implicitWidth: chipText.implicitWidth + 20
                radius: 14
                color: selected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
                border.color: selected ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                border.width: 1

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.currentFilter = modelData.id
                }

                Text {
                  id: chipText
                  anchors.centerIn: parent
                  text: modelData.label
                  font.pixelSize: 11
                  font.weight: selected ? Font.Bold : Font.Normal
                  color: selected ? Color.accent : Color.muted
                }
              }
            }
          }

          Item { Layout.fillWidth: true }

          // Search Field
          Rectangle {
            implicitHeight: 28
            implicitWidth: 180
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

                Text {
                  anchors.fill: parent
                  text: "Search points..."
                  font.pixelSize: 11
                  color: Color.muted
                  visible: !parent.text && !parent.activeFocus
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
                  onClicked: searchInput.text = ""
                }
              }
            }
          }
        }

        // Snapshots Timeline List
        ScrollView {
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true

          ListView {
            id: timelineView
            width: parent.width
            spacing: 8
            model: root.filteredSnapshots

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
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "󰆼"
                  font.pixelSize: 36
                  color: Color.muted
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.snapshotsList.length === 0 ? "No snapshots found on system." : "No snapshots match current filter."
                  font.pixelSize: 13
                  color: Color.muted
                }
              }
            }

            // Snapshot Item Card
            delegate: Rectangle {
              width: timelineView.width
              implicitHeight: cardLayout.implicitHeight + 20
              radius: 10
              color: cardMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.02)
              border.color: modelData.important ? Qt.rgba(0.96, 0.62, 0.04, 0.4) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
              border.width: 1

              MouseArea {
                id: cardMouse
                anchors.fill: parent
                hoverEnabled: true
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
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: "#" + modelData.id
                      font.pixelSize: 13
                      font.weight: Font.Bold
                      color: modelData.important ? "#F59E0B" : Color.accent
                    }
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
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
                    implicitWidth: diffBtnLayout.implicitWidth + 16
                    radius: 6
                    color: diffHover.containsMouse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2) : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.08)
                    border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.3)
                    border.width: 1

                    MouseArea {
                      id: diffHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.inspectDiff(modelData.id)
                    }

                    RowLayout {
                      id: diffBtnLayout
                      anchors.centerIn: parent
                      spacing: 4
                      Text { text: "󰙅"; font.pixelSize: 11; color: Color.accent }
                      Text { text: "Diff"; font.pixelSize: 11; font.weight: Font.Medium; color: Color.accent }
                    }
                  }

                  // Browse Files Button
                  Rectangle {
                    implicitHeight: 28
                    implicitWidth: browseBtnLayout.implicitWidth + 16
                    radius: 6
                    color: browseHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
                    border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                    border.width: 1

                    MouseArea {
                      id: browseHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.browseSnapshot(modelData.id)
                    }

                    RowLayout {
                      id: browseBtnLayout
                      anchors.centerIn: parent
                      spacing: 4
                      Text { text: "󰝰"; font.pixelSize: 11; color: Color.muted }
                      Text { text: "Browse"; font.pixelSize: 11; font.weight: Font.Medium; color: Color.foreground }
                    }
                  }

                  // Pin / Unpin Button
                  Rectangle {
                    implicitHeight: 28
                    implicitWidth: 28
                    radius: 6
                    color: pinHover.containsMouse ? Qt.rgba(0.96, 0.62, 0.04, 0.2) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
                    border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                    border.width: 1

                    MouseArea {
                      id: pinHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.togglePin(modelData.id, modelData.important)
                    }

                    Text {
                      anchors.centerIn: parent
                      text: modelData.important ? "📌" : "󰤱"
                      font.pixelSize: 12
                      color: modelData.important ? "#F59E0B" : Color.muted
                    }
                  }

                  // Restore Button
                  Rectangle {
                    implicitHeight: 28
                    implicitWidth: restoreBtnLayout.implicitWidth + 16
                    radius: 6
                    color: restoreHover.containsMouse ? Qt.rgba(0.06, 0.72, 0.51, 0.2) : Qt.rgba(0.06, 0.72, 0.51, 0.08)
                    border.color: Qt.rgba(0.06, 0.72, 0.51, 0.3)
                    border.width: 1

                    MouseArea {
                      id: restoreHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.confirmRestore(modelData)
                    }

                    RowLayout {
                      id: restoreBtnLayout
                      anchors.centerIn: parent
                      spacing: 4
                      Text { text: "󰁯"; font.pixelSize: 11; color: "#10B981" }
                      Text { text: "Restore"; font.pixelSize: 11; font.weight: Font.Medium; color: "#10B981" }
                    }
                  }

                  // Delete Button
                  Rectangle {
                    implicitHeight: 28
                    implicitWidth: 28
                    radius: 6
                    color: delHover.containsMouse ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.2) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
                    border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                    border.width: 1

                    MouseArea {
                      id: delHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.confirmDelete(modelData)
                    }

                    Text {
                      anchors.centerIn: parent
                      text: "󰆴"
                      font.pixelSize: 12
                      color: delHover.containsMouse ? Color.urgent : Color.muted
                    }
                  }
                }
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
                focus: true
                onAccepted: root.submitCreateSnapshot()
                Keys.onReturnPressed: root.submitCreateSnapshot()
                Keys.onEnterPressed: root.submitCreateSnapshot()

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
          anchors.centerIn: parent
          width: 720
          height: 520
          radius: 12
          color: Color.background
          border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.4)
          border.width: 1

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
                anchors.fill: parent
                anchors.margins: 8
                font.pixelSize: 11
                color: Color.foreground
                onTextChanged: root.diffFilterQuery = text.trim().toLowerCase()

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
          anchors.centerIn: parent
          width: 500
          implicitHeight: restoreCol.implicitHeight + 40
          radius: 12
          color: Color.background
          border.color: "#10B981"
          border.width: 1
          focus: root.showRestoreModal

          Keys.onEscapePressed: root.showRestoreModal = false
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
          anchors.centerIn: parent
          width: 440
          implicitHeight: deleteCol.implicitHeight + 40
          radius: 12
          color: Color.background
          border.color: Color.urgent
          border.width: 1

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
