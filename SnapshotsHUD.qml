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
  readonly property bool devMode: (Quickshell.env("OMARCHY_SNAPSHOTS_DEV") === "1" || Quickshell.env("OMARCHY_DEV") === "1" || useMockData)

  readonly property string homeDir: Quickshell.env("HOME") || "/home/ac"
  readonly property string pluginPath: manifest && manifest.__sourceDir 
    ? manifest.__sourceDir 
    : (homeDir + "/.config/omarchy/plugins/ac.snapshots")
  readonly property string coreScript: pluginPath + "/bin/omarchy-snapshots-core"

  // State data
  property var statusData: ({})
  property var snapshotsList: []
  property var filteredSnapshots: []
  property var mockSnapshotsList: null
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

  property bool showRestoreFileModal: false
  property string activeRestoreFilePath: ""
  property int activeRestoreFileSnapshotId: 0

  property bool showOptimizeModal: false
  property var activeOptimizeData: null
  property bool isOptimizing: false

  property bool showBootModal: false
  property var activeBootData: null
  property bool isSyncingBoot: false

  // Global modal state tracker
  readonly property bool anyModalOpen: showCreateModal
    || showDiffModal
    || showRestoreModal
    || showDeleteModal
    || showRestoreFileModal
    || showOptimizeModal
    || showBootModal

  onShowCreateModalChanged: {
    if (showCreateModal) {
      Qt.callLater(function() {
        if (typeof createDescInput !== "undefined") createDescInput.forceActiveFocus()
        else if (typeof createModalCard !== "undefined") createModalCard.forceActiveFocus()
      })
    } else {
      if (keyCatcher) keyCatcher.forceActiveFocus()
    }
  }

  onShowDiffModalChanged: {
    if (showDiffModal) {
      Qt.callLater(function() {
        if (typeof diffFilterInput !== "undefined") diffFilterInput.forceActiveFocus()
        else if (typeof diffModalCard !== "undefined") diffModalCard.forceActiveFocus()
      })
    } else {
      if (diffProcess.running) diffProcess.running = false
      if (keyCatcher) keyCatcher.forceActiveFocus()
    }
  }

  onShowRestoreModalChanged: {
    if (showRestoreModal) {
      Qt.callLater(function() {
        if (typeof restoreModalCard !== "undefined") restoreModalCard.forceActiveFocus()
      })
    } else {
      if (keyCatcher) keyCatcher.forceActiveFocus()
    }
  }

  onShowDeleteModalChanged: {
    if (showDeleteModal) {
      Qt.callLater(function() {
        if (typeof deleteModalCard !== "undefined") deleteModalCard.forceActiveFocus()
      })
    } else {
      if (keyCatcher) keyCatcher.forceActiveFocus()
    }
  }

  onShowRestoreFileModalChanged: {
    if (showRestoreFileModal) {
      Qt.callLater(function() {
        if (typeof restoreFileModalCard !== "undefined") restoreFileModalCard.forceActiveFocus()
      })
    } else {
      if (keyCatcher) keyCatcher.forceActiveFocus()
    }
  }

  onShowOptimizeModalChanged: {
    if (showOptimizeModal) {
      Qt.callLater(function() {
        if (typeof optimizeModalCard !== "undefined") optimizeModalCard.forceActiveFocus()
      })
    } else {
      if (!root.isOptimizing && estimateOptimizeProcess.running) estimateOptimizeProcess.running = false
      if (keyCatcher) keyCatcher.forceActiveFocus()
    }
  }

  onShowBootModalChanged: {
    if (showBootModal) {
      Qt.callLater(function() {
        if (typeof bootModalCard !== "undefined") bootModalCard.forceActiveFocus()
      })
    } else {
      if (!root.isSyncingBoot && bootHealthProcess.running) bootHealthProcess.running = false
      if (keyCatcher) keyCatcher.forceActiveFocus()
    }
  }

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
  onUseMockDataChanged: {
    root.mockSnapshotsList = null
    root.refresh()
  }

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

    if (useMockData) {
      if (!mockSnapshotsList) {
        mockSnapshotsList = (snapshotsList || []).slice()
      }
      var maxId = 19
      for (var i = 0; i < mockSnapshotsList.length; i++) {
        if (mockSnapshotsList[i].id && mockSnapshotsList[i].id > maxId) {
          maxId = mockSnapshotsList[i].id
        }
      }
      var nextId = maxId + 1
      var now = new Date()
      var newSnap = {
        "id": nextId,
        "type": "single",
        "description": desc,
        "date": Qt.formatDateTime(now, "yyyy-MM-dd hh:mm:ss"),
        "epoch": Math.floor(now.getTime() / 1000),
        "relativeAge": "just now",
        "cleanup": newSnapshotImportant ? "none" : "number",
        "important": newSnapshotImportant,
        "bootable": true,
        "bootableInLimine": true,
        "packageCount": 0,
        "hasCriticalPackages": false,
        "criticalPackages": [],
        "packageSummary": "Manual checkpoint",
        "packages": [],
        "userdata": { "description": desc }
      }
      mockSnapshotsList = [newSnap].concat(mockSnapshotsList)
      snapshotsList = mockSnapshotsList.slice()
      if (statusData && statusData.storage) {
        var copyStatus = JSON.parse(JSON.stringify(statusData))
        copyStatus.storage.snapshotCount = mockSnapshotsList.length
        statusData = copyStatus
      }
      applyFilter()
      selectedIndex = 0
      notify("Snapshot #" + nextId + " ('" + desc + "') created successfully.")
      return
    }

    notify("Creating checkpoint" + (desc ? " '" + desc + "'" : "") + "...")

    var args = [coreScript, "create", "--desc-stdin"]
    if (newSnapshotImportant) args.push("--important")

    if (actionProcess.running) actionProcess.running = false
    actionProcess.stdinPayload = (desc || "") + "\n"
    actionProcess.command = args
    actionProcess.running = true
  }

  function togglePin(snapId, currentImportant) {
    if (useMockData) {
      if (!mockSnapshotsList) {
        mockSnapshotsList = (snapshotsList || []).slice()
      }
      var found = false
      var newImportant = !currentImportant
      for (var i = 0; i < mockSnapshotsList.length; i++) {
        if (mockSnapshotsList[i].id === snapId) {
          mockSnapshotsList[i].important = newImportant
          mockSnapshotsList[i].cleanup = newImportant ? "none" : "number"
          found = true
          break
        }
      }
      if (found) {
        snapshotsList = mockSnapshotsList.slice()
        applyFilter()
        notify((newImportant ? "Pinned" : "Unpinned") + " snapshot #" + snapId + ".")
      }
      return
    }

    var action = currentImportant ? "unpin" : "pin"
    notify((currentImportant ? "Unpinning" : "Pinning") + " snapshot #" + snapId + "...")
    var args = [coreScript, action, "--id", String(snapId)]
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
    if (useMockData) {
      notify("Demo: Snapshot #" + snapId + " browse simulated (path: /.snapshots/" + snapId + "/snapshot)")
      return
    }
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

    if (useMockData) {
      notify("Recovery preview: System roll-back to snapshot #" + id + " staged successfully.")
      return
    }

    notify("Launching recovery for snapshot #" + id + "...")
    var args = [coreScript, "restore", "--id", String(id)]

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

    if (useMockData) {
      if (!mockSnapshotsList) {
        mockSnapshotsList = (snapshotsList || []).slice()
      }
      var filtered = []
      for (var i = 0; i < mockSnapshotsList.length; i++) {
        if (mockSnapshotsList[i].id !== id) {
          filtered.push(mockSnapshotsList[i])
        }
      }
      mockSnapshotsList = filtered
      snapshotsList = mockSnapshotsList.slice()
      if (statusData && statusData.storage) {
        var copyStatus = JSON.parse(JSON.stringify(statusData))
        copyStatus.storage.snapshotCount = mockSnapshotsList.length
        statusData = copyStatus
      }
      applyFilter()
      notify("Snapshot #" + id + " deleted successfully.")
      return
    }

    notify("Pruning snapshot #" + id + "...")
    var args = [coreScript, "delete", "--id", String(id)]
    actionProcess.command = args
    actionProcess.running = true
  }

  function confirmRestoreFile(snapId, filePath) {
    activeRestoreFileSnapshotId = snapId
    activeRestoreFilePath = filePath
    showRestoreFileModal = true
  }

  function executeRestoreFile() {
    if (!activeRestoreFilePath || !activeRestoreFileSnapshotId) return
    var snapId = activeRestoreFileSnapshotId
    var filePath = activeRestoreFilePath
    showRestoreFileModal = false
    if (keyCatcher) keyCatcher.forceActiveFocus()

    if (useMockData) {
      notify("File " + filePath + " safely restored from snapshot #" + snapId + ".")
      return
    }

    notify("Restoring " + filePath + " from #" + snapId + "...")

    var args = [coreScript, "restore-file", "--id", String(snapId), "--path", filePath]

    if (restoreFileProcess.running) restoreFileProcess.running = false
    restoreFileProcess.command = args
    restoreFileProcess.running = true
  }

  function openOptimizeModal() {
    showOptimizeModal = true
    notify("Evaluating Btrfs retention guards and calculating reclaimable space...")
    var args = [coreScript, "optimize"]
    if (useMockData) args.push("--mock")
    if (estimateOptimizeProcess.running) estimateOptimizeProcess.running = false
    estimateOptimizeProcess.command = args
    estimateOptimizeProcess.running = true
  }

  function executeOptimize() {
    isOptimizing = true
    notify("Safely pruning stale snapshots and reclaiming space...")

    if (useMockData) {
      if (!mockSnapshotsList) {
        mockSnapshotsList = (snapshotsList || []).slice()
      }
      var remaining = []
      for (var i = 0; i < mockSnapshotsList.length; i++) {
        if (mockSnapshotsList[i].id === 16) continue
        remaining.push(mockSnapshotsList[i])
      }
      mockSnapshotsList = remaining
      snapshotsList = mockSnapshotsList.slice()
      if (statusData && statusData.storage) {
        var copyStatus = JSON.parse(JSON.stringify(statusData))
        copyStatus.storage.snapshotCount = mockSnapshotsList.length
        statusData = copyStatus
      }
      applyFilter()
      isOptimizing = false
      showOptimizeModal = false
      notify("Optimization complete: Reclaimed ~1.4 GiB storage.")
      return
    }

    var args = [coreScript, "optimize", "--execute"]
    if (executeOptimizeProcess.running) executeOptimizeProcess.running = false
    executeOptimizeProcess.command = args
    executeOptimizeProcess.running = true
  }

  function openBootModal() {
    showBootModal = true
    notify("Querying Limine bootloader health and verified entries...")
    var args = [coreScript, "boot-health"]
    if (useMockData) args.push("--mock")
    if (bootHealthProcess.running) bootHealthProcess.running = false
    bootHealthProcess.command = args
    bootHealthProcess.running = true
  }

  function executeBootSync() {
    if (isSyncingBoot) return
    isSyncingBoot = true
    notify("Synchronizing Limine bootloader entries with Snapper snapshots...")
    var args = [coreScript, "boot-sync"]
    if (useMockData) args.push("--mock")
    if (bootSyncProcess.running) bootSyncProcess.running = false
    bootSyncProcess.command = args
    bootSyncProcess.running = true
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
        if (parsed.action === "optimize") root.openOptimizeModal()
        if (parsed.action === "boot") root.openBootModal()
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
          if (root.useMockData) {
            if (root.mockSnapshotsList === null) {
              root.mockSnapshotsList = snaps.slice()
            }
            root.snapshotsList = root.mockSnapshotsList.slice()
            if (root.statusData && root.statusData.storage) {
              root.statusData.storage.snapshotCount = root.mockSnapshotsList.length
            }
          } else {
            root.mockSnapshotsList = null
            root.snapshotsList = snaps
          }
        } catch(e) {
          console.warn("[omarchy-snapshots] Failed to parse status JSON:", e)
        }
      }
    }
  }

  Process {
    id: actionProcess
    property string stderrOutput: ""
    property string stdinPayload: ""
    stdinEnabled: true
    onStarted: {
      if (stdinPayload.length > 0) {
        write(stdinPayload)
        stdinPayload = ""
      }
    }
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
      actionProcess.stdinPayload = ""
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
    id: restoreFileProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var res = JSON.parse(text)
          if (res.ok) {
            var msg = "File restored! " + (res.backupPath ? ("Bak: " + res.backupPath) : "")
            root.notify(msg)
          } else {
            root.notify("Failed to restore file: " + (res.error || "Unknown error"))
          }
        } catch(e) {
          root.notify("Restored file successfully.")
        }
      }
    }
  }

  Process {
    id: estimateOptimizeProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var res = JSON.parse(text)
          if (res.ok) {
            root.activeOptimizeData = res
          } else {
            root.notify("Optimization estimate failed: " + (res.error || "Unknown error"))
          }
        } catch(e) {}
      }
    }
  }

  Process {
    id: executeOptimizeProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.isOptimizing = false
        try {
          var res = JSON.parse(text)
          if (res.ok) {
            root.showOptimizeModal = false
            root.notify(res.message || "Disk optimization completed!")
            root.refresh()
          } else {
            root.notify("Optimization failed: " + (res.error || "Failed"))
          }
        } catch(e) {
          root.showOptimizeModal = false
          root.notify("Optimization completed.")
          root.refresh()
        }
      }
    }
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
    id: bootHealthProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var res = JSON.parse(text)
          if (res.ok) {
            root.activeBootData = res
          }
        } catch(e) {}
      }
    }
  }

  Process {
    id: bootSyncProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.isSyncingBoot = false
        try {
          var res = JSON.parse(text)
          if (res.ok) {
            root.notify(res.message || "Limine bootloader entries synchronized!")
            root.openBootModal()
            root.refresh()
          } else {
            root.notify("Boot sync failed: " + (res.error || "Failed"))
          }
        } catch(e) {
          root.notify("Limine sync completed.")
          root.refresh()
        }
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

  Component.onDestruction: {
    if (statusProcess.running) statusProcess.running = false
    if (actionProcess.running) actionProcess.running = false
    if (diffProcess.running) diffProcess.running = false
    if (restoreFileProcess.running) restoreFileProcess.running = false
    if (estimateOptimizeProcess.running) estimateOptimizeProcess.running = false
    if (bootHealthProcess.running) bootHealthProcess.running = false
    if (bootSyncProcess.running) bootSyncProcess.running = false
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
        if (diffProcess.running) diffProcess.running = false
        if (estimateOptimizeProcess.running) estimateOptimizeProcess.running = false
        if (bootHealthProcess.running) bootHealthProcess.running = false
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
          if (root.anyModalOpen) {
            if (event.key === Qt.Key_Escape) {
              if (root.showDiffModal) root.showDiffModal = false
              else if (root.showCreateModal) root.showCreateModal = false
              else if (root.showRestoreModal) root.showRestoreModal = false
              else if (root.showDeleteModal) root.showDeleteModal = false
              else if (root.showRestoreFileModal) root.showRestoreFileModal = false
              else if (root.showOptimizeModal) { if (!root.isOptimizing) root.showOptimizeModal = false }
              else if (root.showBootModal) { if (!root.isSyncingBoot) root.showBootModal = false }
              if (keyCatcher) keyCatcher.forceActiveFocus()
              event.accepted = true
            }
            return
          }

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
            if (root.selectedSnapshot) root.confirmRestore(root.selectedSnapshot)
            event.accepted = true
          } else if (event.key === Qt.Key_X) {
            if (root.selectedSnapshot) root.confirmDelete(root.selectedSnapshot)
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
          } else if (event.key === Qt.Key_O) {
            root.openOptimizeModal()
            event.accepted = true
          } else if (event.key === Qt.Key_L) {
            root.openBootModal()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.selectedSnapshot) {
              root.inspectDiff(root.selectedSnapshot.id)
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
            root.dismiss()
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
        blocked: root.anyModalOpen
          || (searchInput && searchInput.activeFocus)
          || (typeof createDescInput !== "undefined" && createDescInput.activeFocus)
          || (typeof diffFilterInput !== "undefined" && diffFilterInput.activeFocus)

        onMoveRequested: function(dx, dy) {
          if (root.anyModalOpen) return
          if (dy > 0) root.selectNext()
          else if (dy < 0) root.selectPrev()
          else if (dx > 0) root.cycleFilter(1)
          else if (dx < 0) root.cycleFilter(-1)
        }

        onActivateRequested: function() {
          if (root.anyModalOpen) return
          if (root.selectedSnapshot) root.inspectDiff(root.selectedSnapshot.id)
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
          } else if (root.showRestoreFileModal) {
            root.showRestoreFileModal = false
            keyCatcher.forceActiveFocus()
          } else if (root.showOptimizeModal) {
            if (!root.isOptimizing) {
              root.showOptimizeModal = false
              keyCatcher.forceActiveFocus()
            }
          } else if (root.showBootModal) {
            if (!root.isSyncingBoot) {
              root.showBootModal = false
              keyCatcher.forceActiveFocus()
            }
          } else if (searchInput && searchInput.text.length > 0) {
            searchInput.text = ""
            keyCatcher.forceActiveFocus()
          } else {
            root.dismiss()
          }
        }

        onDeleteRequested: function() {
          if (root.anyModalOpen) return
          if (root.selectedSnapshot) root.confirmDelete(root.selectedSnapshot)
        }

        onTextKey: function(key, modifiers) {
          if (root.anyModalOpen) return
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
            if (root.selectedSnapshot) root.confirmRestore(root.selectedSnapshot)
          } else if (k === "l") {
            root.openBootModal()
          } else if (k === "o") {
            root.openOptimizeModal()
          } else if (k === "f" || key === "/") {
            searchInput.forceActiveFocus()
            searchInput.selectAll()
          } else if (k === "g") {
            root.refresh()
          } else if (k === "q") {
            root.dismiss()
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
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 44
            implicitHeight: 44
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
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
            spacing: 3
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter

            RowLayout {
              spacing: 10
              Layout.alignment: Qt.AlignVCenter

              Text {
                text: "Snapshots & Recovery"
                font.pixelSize: 18
                font.weight: Font.Bold
                color: Color.foreground
              }

              // Health Status Pill
              Rectangle {
                id: healthPill
                property var health: (root.statusData && root.statusData.health) || ({})
                property string status: health.status || "warning"
                readonly property color statusColor: status === "healthy"
                  ? Qt.rgba(0.13, 0.77, 0.55, 1.0)
                  : (status === "error" ? Color.urgent : Qt.rgba(0.96, 0.62, 0.15, 1.0))

                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 22
                implicitWidth: healthContent.implicitWidth + 16
                radius: 11
                color: Qt.rgba(statusColor.r, statusColor.g, statusColor.b, 0.14)
                border.color: Qt.rgba(statusColor.r, statusColor.g, statusColor.b, 0.40)
                border.width: 1

                RowLayout {
                  id: healthContent
                  anchors.centerIn: parent
                  spacing: 6

                  Rectangle {
                    implicitWidth: 6
                    implicitHeight: 6
                    Layout.preferredWidth: 6
                    Layout.preferredHeight: 6
                    radius: 3
                    color: healthPill.statusColor
                  }

                  Text {
                    id: healthLabel
                    textFormat: Text.PlainText
                    text: (root.statusData && root.statusData.health && root.statusData.health.label) || "Checking..."
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: healthPill.statusColor
                  }
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              text: (root.statusData && root.statusData.health && root.statusData.health.reason) || "Checking Btrfs subvolumes and bootloader synchronization..."
              font.pixelSize: 11
              color: Color.muted
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          // Top Action Buttons
          RowLayout {
            spacing: 8
            Layout.alignment: Qt.AlignVCenter

            // Demo toggle chip (only visible in development mode)
            Rectangle {
              id: mockToggleBtn
              visible: root.devMode
              implicitHeight: 32
              implicitWidth: mockToggleRow.implicitWidth + 20
              radius: 8
              color: root.useMockData 
                ? (mockMouse.containsMouse ? Qt.rgba(0.99, 0.82, 0.20, 0.32) : Qt.rgba(0.99, 0.82, 0.20, 0.22))
                : (mockMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.03))
              border.color: root.useMockData ? "#FDE047" : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
              border.width: 1

              MouseArea {
                id: mockMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.useMockData = !root.useMockData
              }

              RowLayout {
                id: mockToggleRow
                anchors.centerIn: parent
                spacing: 6

                Rectangle {
                  implicitWidth: 6
                  implicitHeight: 6
                  Layout.preferredWidth: 6
                  Layout.preferredHeight: 6
                  radius: 3
                  color: root.useMockData ? "#FDE047" : Color.muted
                }

                Text {
                  id: mockToggleText
                  textFormat: Text.PlainText
                  text: root.useMockData ? "DEV: Demo ON" : "DEV: Demo OFF"
                  font.pixelSize: 11
                  font.weight: root.useMockData ? Font.DemiBold : Font.Normal
                  color: root.useMockData ? "#FDE047" : Color.muted
                }
              }
            }

            // Refresh Button
            Rectangle {
              id: refreshBtn
              implicitHeight: 32
              implicitWidth: refreshBtnLayout.implicitWidth + 18
              radius: 8
              color: refreshMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.03)
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
                spacing: 7

                Text {
                  text: "󰑐"
                  font.pixelSize: 13
                  color: root.isRefreshing ? Color.accent : (refreshMouse.containsMouse ? Color.foreground : Color.muted)
                  rotation: root.isRefreshing ? 180 : 0
                  Behavior on rotation { NumberAnimation { duration: 400 } }
                }

                Rectangle {
                  implicitHeight: 18
                  implicitWidth: Math.max(18, keyRefTxt.implicitWidth + 8)
                  radius: 4
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                  border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.16)
                  border.width: 1

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
              id: createBtn
              implicitHeight: 32
              implicitWidth: createBtnLayout.implicitWidth + 20
              radius: 8
              color: createMouse.containsMouse ? Qt.lighter(Color.accent, 1.12) : Color.accent

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
                spacing: 7

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
                  implicitHeight: 18
                  implicitWidth: Math.max(18, keyNewTxt.implicitWidth + 8)
                  radius: 4
                  color: Qt.rgba(0, 0, 0, 0.22)
                  border.color: Qt.rgba(255, 255, 255, 0.18)
                  border.width: 1

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
              id: closeBtn
              implicitHeight: 32
              implicitWidth: closeBtnLayout.implicitWidth + 16
              radius: 8
              color: closeMouse.containsMouse ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.18) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.03)
              border.color: closeMouse.containsMouse ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.5) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
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
                spacing: 6

                Text {
                  text: "󰅖"
                  font.pixelSize: 13
                  color: closeMouse.containsMouse ? Color.urgent : Color.muted
                }

                Rectangle {
                  implicitHeight: 18
                  implicitWidth: Math.max(18, keyEscTxt.implicitWidth + 8)
                  radius: 4
                  color: closeMouse.containsMouse ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.15) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                  border.color: closeMouse.containsMouse ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.3) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.16)
                  border.width: 1

                  Text {
                    id: keyEscTxt
                    anchors.centerIn: parent
                    text: "Esc"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: closeMouse.containsMouse ? Color.urgent : Color.muted
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
              textFormat: Text.PlainText
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
          readonly property color authWarnColor: Qt.rgba(0.96, 0.62, 0.15, 1.0)
          color: Qt.rgba(authWarnColor.r, authWarnColor.g, authWarnColor.b, 0.12)
          border.color: Qt.rgba(authWarnColor.r, authWarnColor.g, authWarnColor.b, 0.35)
          border.width: 1

          RowLayout {
            id: authLayout
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            Text {
              text: "󰌋"
              font.pixelSize: 22
              color: authWarningCard.authWarnColor
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
              color: authWarningCard.authWarnColor

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
                color: Color.background
              }
            }
          }
        }

        // Storage & Telemetry Bar
        Rectangle {
          id: storageTelemetryCard
          Layout.fillWidth: true
          implicitHeight: 52
          radius: 10
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.03)
          border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
          border.width: 1

          property var storage: (root.statusData && root.statusData.storage) || ({})
          property int pct: storage.usedPercent || 0
          readonly property color meterColor: pct > 85 ? Color.urgent : (pct > 70 ? Qt.rgba(0.96, 0.62, 0.15, 1.0) : Color.accent)
          readonly property string subvolPath: (root.statusData && root.statusData.configs && root.statusData.configs[0] && root.statusData.configs[0].subvolume) || "/"

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 16

            // Storage telemetry section (Left)
            RowLayout {
              spacing: 10
              Layout.alignment: Qt.AlignVCenter

              Rectangle {
                implicitWidth: 32
                implicitHeight: 32
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 8
                color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
                border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25)
                border.width: 1

                Text {
                  anchors.centerIn: parent
                  text: "󰋊"
                  font.pixelSize: 16
                  color: Color.accent
                }
              }

              ColumnLayout {
                spacing: 2
                Layout.alignment: Qt.AlignVCenter

                RowLayout {
                  spacing: 6
                  Text {
                    text: "Btrfs Storage Pool"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: Color.foreground
                  }
                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: subvolTxt.implicitWidth + 8
                    radius: 4
                    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)
                    border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
                    border.width: 1
                    Text {
                      id: subvolTxt
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: "@" + (storageTelemetryCard.subvolPath === "/" ? "root" : storageTelemetryCard.subvolPath.replace(/^\//, ""))
                      font.pixelSize: 9
                      font.weight: Font.Medium
                      color: Color.muted
                    }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: (storageTelemetryCard.storage.fsAvailHuman || "0 B") + " free of " + (storageTelemetryCard.storage.fsSizeHuman || "0 B")
                  font.pixelSize: 11
                  color: Color.muted
                }
              }
            }

            // Usage meter track (Center)
            RowLayout {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              spacing: 10

              Rectangle {
                Layout.fillWidth: true
                implicitHeight: 8
                Layout.preferredHeight: 8
                radius: 4
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                clip: true

                Rectangle {
                  width: Math.max(height, parent.width * Math.min(1.0, (storageTelemetryCard.pct / 100.0)))
                  height: parent.height
                  radius: 4
                  color: storageTelemetryCard.meterColor

                  Behavior on width {
                    NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                  }
                }
              }

              Text {
                textFormat: Text.PlainText
                text: storageTelemetryCard.pct + "% used"
                font.pixelSize: 11
                font.weight: Font.Medium
                color: storageTelemetryCard.meterColor
              }
            }

            // Divider line between telemetry and actions
            Rectangle {
              implicitWidth: 1
              implicitHeight: 24
              Layout.preferredWidth: 1
              Layout.preferredHeight: 24
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10)
              Layout.alignment: Qt.AlignVCenter
            }

            // Maintenance Quick Actions (Right)
            RowLayout {
              spacing: 8
              Layout.alignment: Qt.AlignVCenter

              // Interactive Limine Bootloader Health Button Chip
              Rectangle {
                id: limineBootBtn
                implicitHeight: 28
                implicitWidth: limineBtnRow.implicitWidth + 16
                radius: 6
                property bool syncActive: (root.statusData && root.statusData.health && root.statusData.health.limineSyncActive) === true
                readonly property color bootColor: syncActive ? Qt.rgba(0.13, 0.77, 0.55, 1.0) : Color.urgent

                color: limineBtnMouse.containsMouse 
                  ? Qt.rgba(bootColor.r, bootColor.g, bootColor.b, 0.20) 
                  : Qt.rgba(bootColor.r, bootColor.g, bootColor.b, 0.09)
                border.color: limineBtnMouse.containsMouse 
                  ? bootColor 
                  : Qt.rgba(bootColor.r, bootColor.g, bootColor.b, 0.30)
                border.width: 1

                MouseArea {
                  id: limineBtnMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openBootModal()
                }

                RowLayout {
                  id: limineBtnRow
                  anchors.centerIn: parent
                  spacing: 6

                  Text {
                    textFormat: Text.PlainText
                    text: limineBootBtn.syncActive ? "󰌢" : "󰌣"
                    font.pixelSize: 12
                    color: limineBootBtn.bootColor
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: limineBootBtn.syncActive ? "Limine Boot Sync" : "Boot Sync Offline"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: limineBootBtn.syncActive ? Color.foreground : Color.urgent
                  }
                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: Math.max(16, limineKeyTxt.implicitWidth + 8)
                    radius: 3
                    color: Qt.rgba(limineBootBtn.bootColor.r, limineBootBtn.bootColor.g, limineBootBtn.bootColor.b, 0.20)
                    border.color: Qt.rgba(limineBootBtn.bootColor.r, limineBootBtn.bootColor.g, limineBootBtn.bootColor.b, 0.35)
                    border.width: 1

                    Text {
                      id: limineKeyTxt
                      anchors.centerIn: parent
                      text: "L"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: limineBootBtn.bootColor
                    }
                  }
                }
              }

              // Optimize Disk Button Chip
              Rectangle {
                id: optimizeDiskBtn
                implicitHeight: 28
                implicitWidth: optBtnRow.implicitWidth + 16
                radius: 6
                readonly property color optColor: Qt.rgba(0.13, 0.77, 0.55, 1.0)
                color: optMouse.containsMouse 
                  ? Qt.rgba(optColor.r, optColor.g, optColor.b, 0.20) 
                  : Qt.rgba(optColor.r, optColor.g, optColor.b, 0.09)
                border.color: optMouse.containsMouse 
                  ? optColor 
                  : Qt.rgba(optColor.r, optColor.g, optColor.b, 0.30)
                border.width: 1

                MouseArea {
                  id: optMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openOptimizeModal()
                }

                RowLayout {
                  id: optBtnRow
                  anchors.centerIn: parent
                  spacing: 6

                  Text {
                    text: "󰚰"
                    font.pixelSize: 12
                    color: optimizeDiskBtn.optColor
                  }
                  Text {
                    text: "Optimize Disk"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: Color.foreground
                  }
                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: Math.max(16, keyOptTxt.implicitWidth + 8)
                    radius: 3
                    color: Qt.rgba(optimizeDiskBtn.optColor.r, optimizeDiskBtn.optColor.g, optimizeDiskBtn.optColor.b, 0.20)
                    border.color: Qt.rgba(optimizeDiskBtn.optColor.r, optimizeDiskBtn.optColor.g, optimizeDiskBtn.optColor.b, 0.35)
                    border.width: 1

                    Text {
                      id: keyOptTxt
                      anchors.centerIn: parent
                      text: "O"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: optimizeDiskBtn.optColor
                    }
                  }
                }
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
                { id: "all", label: "All Points (" + root.snapshotsList.length + ")", icon: "", key: "1" },
                { id: "update", label: "Pre-Update", icon: "󰚰", key: "2" },
                { id: "manual", label: "Manual", icon: "󰐕", key: "3" },
                { id: "pinned", label: "Pinned", icon: "󰤱", key: "4" }
              ]

              Rectangle {
                id: filterChipRect
                property bool selected: root.currentFilter === modelData.id
                implicitHeight: 30
                implicitWidth: chipRowLayout.implicitWidth + 20
                radius: 8
                color: selected 
                  ? (modelData.id === "pinned" ? Qt.rgba(0.99, 0.82, 0.20, 0.24) : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)) 
                  : (filterMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.03))
                border.color: selected 
                  ? (modelData.id === "pinned" ? "#FDE047" : Color.accent) 
                  : (filterMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.18) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10))
                border.width: 1

                MouseArea {
                  id: filterMouse
                  anchors.fill: parent
                  hoverEnabled: true
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
                    visible: modelData.icon.length > 0
                    textFormat: Text.PlainText
                    text: modelData.icon
                    font.pixelSize: 12
                    color: modelData.id === "pinned" ? "#FDE047" : (filterChipRect.selected ? Color.accent : Color.muted)
                  }

                  Text {
                    id: chipText
                    textFormat: Text.PlainText
                    text: modelData.label
                    font.pixelSize: 11
                    font.weight: filterChipRect.selected ? Font.DemiBold : Font.Normal
                    color: filterChipRect.selected 
                      ? (modelData.id === "pinned" ? "#FDE047" : Color.accent) 
                      : (modelData.id === "pinned" ? "#FDE047" : Color.muted)
                  }

                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: Math.max(16, chipKeyText.implicitWidth + 6)
                    radius: 3
                    color: filterChipRect.selected 
                      ? (modelData.id === "pinned" ? Qt.rgba(0.99, 0.82, 0.20, 0.35) : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)) 
                      : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                    border.color: filterChipRect.selected 
                      ? (modelData.id === "pinned" ? "#FDE047" : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.5)) 
                      : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)
                    border.width: 1

                    Text {
                      id: chipKeyText
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: modelData.key
                      font.pixelSize: 9
                      font.weight: Font.Bold
                      color: filterChipRect.selected 
                        ? (modelData.id === "pinned" ? "#FDE047" : Color.accent) 
                        : (modelData.id === "pinned" ? "#FDE047" : Color.muted)
                    }
                  }
                }
              }
            }
          }

          Item { Layout.fillWidth: true }

          // Search Field
          Rectangle {
            implicitHeight: 30
            implicitWidth: 200
            radius: 8
            color: searchInput.activeFocus 
              ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06) 
              : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.03)
            border.color: searchInput.activeFocus 
              ? Color.accent 
              : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
            border.width: 1

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              spacing: 6

              Text {
                text: ""
                font.pixelSize: 12
                color: searchInput.activeFocus ? Color.accent : Color.muted
                Layout.alignment: Qt.AlignVCenter
              }

              TextInput {
                id: searchInput
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
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
                  verticalAlignment: Text.AlignVCenter
                }
              }

              // Key hint [/] when input is inactive and empty
              Rectangle {
                visible: searchInput.text.length === 0 && !searchInput.activeFocus
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: 18
                implicitWidth: Math.max(18, searchKeyBadge.implicitWidth + 8)
                radius: 4
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.16)
                border.width: 1

                Text {
                  id: searchKeyBadge
                  anchors.centerIn: parent
                  text: "/"
                  font.pixelSize: 9
                  font.weight: Font.Bold
                  color: Color.muted
                }
              }

              Rectangle {
                visible: searchInput.text.length > 0
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 16
                implicitHeight: 16
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                radius: 8
                color: clearSearchMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15) : "transparent"

                MouseArea {
                  id: clearSearchMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    searchInput.text = ""
                    keyCatcher.forceActiveFocus()
                  }
                }

                Text {
                  anchors.centerIn: parent
                  text: "󰅖"
                  font.pixelSize: 10
                  color: clearSearchMouse.containsMouse ? Color.foreground : Color.muted
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
                  textFormat: Text.PlainText
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
                : (modelData.important ? Qt.rgba(0.99, 0.88, 0.28, 0.45) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08))
              border.width: isSelected ? 1.5 : 1

              // Left Accent Stripe Indicator
              Rectangle {
                id: selectionStripe
                width: 3.5
                height: parent.height - 16
                radius: 2
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                visible: isSelected || (modelData.important === true)
                color: isSelected ? Color.accent : "#FDE047"
              }

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
                anchors.leftMargin: 14
                anchors.rightMargin: 12
                anchors.topMargin: 10
                anchors.bottomMargin: 10
                spacing: 14

                // Snapshot ID Badge
                Rectangle {
                  implicitWidth: 44
                  implicitHeight: 44
                  Layout.preferredWidth: 44
                  Layout.preferredHeight: 44
                  radius: 8
                  color: modelData.important ? Qt.rgba(0.99, 0.82, 0.20, 0.22) : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.1)
                  border.color: modelData.important ? "#FDE047" : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25)
                  border.width: 1

                  ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0
                    Text {
                      Layout.alignment: Qt.AlignHCenter
                      textFormat: Text.PlainText
                      text: "#" + modelData.id
                      font.pixelSize: 13
                      font.weight: Font.Bold
                      color: modelData.important ? "#FDE047" : Color.accent
                    }
                    Text {
                      Layout.alignment: Qt.AlignHCenter
                      textFormat: Text.PlainText
                      text: modelData.cleanup === "none" ? "keep" : "auto"
                      font.pixelSize: 9
                      font.weight: Font.Medium
                      color: modelData.important ? "#FDE047" : Color.muted
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
                      textFormat: Text.PlainText
                      text: modelData.description || ("Snapshot #" + modelData.id)
                      font.pixelSize: 13
                      font.weight: Font.DemiBold
                      color: Color.foreground
                    }

                    // Pinned Chip
                    Rectangle {
                      visible: modelData.important === true
                      implicitHeight: 20
                      implicitWidth: pinChipRow.implicitWidth + 14
                      radius: 10
                      color: Qt.rgba(0.99, 0.82, 0.20, 0.25)
                      border.color: "#FDE047"
                      border.width: 1

                      RowLayout {
                        id: pinChipRow
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                          text: "󰤱"
                          font.pixelSize: 12
                          color: "#FDE047"
                        }
                        Text {
                          text: "Pinned"
                          font.pixelSize: 10
                          font.weight: Font.Bold
                          color: "#FDE047"
                        }
                      }
                    }

                    // Bootable in Limine Chip
                    Rectangle {
                      id: bootChipBadge
                      implicitHeight: 20
                      implicitWidth: bootChipRow.implicitWidth + 12
                      radius: 10
                      property bool isBootable: (modelData.bootableInLimine !== false)
                      color: isBootable ? Qt.rgba(0.06, 0.72, 0.51, 0.15) : Qt.rgba(0.94, 0.27, 0.27, 0.15)
                      border.color: isBootable ? Qt.rgba(0.06, 0.72, 0.51, 0.3) : Qt.rgba(0.94, 0.27, 0.27, 0.3)
                      border.width: 1

                      RowLayout {
                        id: bootChipRow
                        anchors.centerIn: parent
                        spacing: 3
                        Text {
                          textFormat: Text.PlainText
                          text: bootChipBadge.isBootable ? "󰌢" : "󰌣"
                          font.pixelSize: 10
                          color: bootChipBadge.isBootable ? "#10B981" : "#EF4444"
                        }
                        Text {
                          textFormat: Text.PlainText
                          text: bootChipBadge.isBootable ? "Limine Boot" : "Not in Limine"
                          font.pixelSize: 9
                          font.weight: Font.Medium
                          color: bootChipBadge.isBootable ? "#10B981" : "#EF4444"
                        }
                      }
                    }

                    // Package Updates Chip
                    Rectangle {
                      visible: (modelData.packageCount && modelData.packageCount > 0) ? true : false
                      implicitHeight: 20
                      implicitWidth: pkgChipLayout.implicitWidth + 12
                      radius: 10
                      color: modelData.hasCriticalPackages ? Qt.rgba(0.96, 0.62, 0.04, 0.2) : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
                      border.color: modelData.hasCriticalPackages ? "#F59E0B" : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.3)
                      border.width: 1

                      RowLayout {
                        id: pkgChipLayout
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                          textFormat: Text.PlainText
                          text: modelData.hasCriticalPackages ? "󰒋" : "󰏔"
                          font.pixelSize: 10
                          color: modelData.hasCriticalPackages ? "#F59E0B" : Color.accent
                        }
                        Text {
                          textFormat: Text.PlainText
                          text: modelData.packageCount + " pkgs"
                          font.pixelSize: 9
                          font.weight: Font.Medium
                          color: modelData.hasCriticalPackages ? "#F59E0B" : Color.accent
                        }
                      }
                    }
                  }

                  RowLayout {
                    spacing: 12
                    Text {
                      textFormat: Text.PlainText
                      text: "󰅐 " + (modelData.relativeAge || "")
                      font.pixelSize: 11
                      color: Color.muted
                    }
                    Text {
                      textFormat: Text.PlainText
                      text: " " + (modelData.date || "")
                      font.pixelSize: 11
                      color: Color.muted
                    }
                    Text {
                      visible: (modelData.packageCount && modelData.packageCount > 0) ? true : false
                      textFormat: Text.PlainText
                      text: "󰏖 " + (modelData.packageSummary || "")
                      font.pixelSize: 11
                      color: modelData.hasCriticalPackages ? "#F59E0B" : Color.muted
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
                        implicitHeight: 16
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
                        implicitHeight: 16
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
                    implicitWidth: pinBtnLayout.implicitWidth + 14
                    radius: 6
                    color: modelData.important 
                      ? (pinHover.containsMouse ? Qt.rgba(0.99, 0.82, 0.20, 0.35) : Qt.rgba(0.99, 0.82, 0.20, 0.22))
                      : (pinHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04))
                    border.color: modelData.important ? "#FDE047" : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
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
                      spacing: 5
                      Text {
                        textFormat: Text.PlainText
                        text: modelData.important ? "󰤱" : "󰤲"
                        font.pixelSize: 13
                        color: modelData.important ? "#FDE047" : Color.muted
                      }
                      Rectangle {
                        implicitHeight: 16
                        implicitWidth: pinKeyTxt.implicitWidth + 6
                        radius: 3
                        color: modelData.important ? Qt.rgba(0.99, 0.82, 0.20, 0.35) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                        border.color: modelData.important ? "#FDE047" : "transparent"
                        border.width: modelData.important ? 1 : 0
                        Text {
                          id: pinKeyTxt
                          anchors.centerIn: parent
                          text: "P"
                          font.pixelSize: 8
                          font.weight: Font.Bold
                          color: modelData.important ? "#FDE047" : Color.muted
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
                        implicitHeight: 16
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
                    implicitWidth: delBtnLayout.implicitWidth + 14
                    radius: 6
                    color: delHover.containsMouse ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.2) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
                    border.color: delHover.containsMouse ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.4) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
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
                        implicitHeight: 16
                        implicitWidth: delKeyTxt.implicitWidth + 6
                        radius: 3
                        color: delHover.containsMouse ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.3) : Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.18)
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
          implicitHeight: 36
          radius: 8
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.03)
          border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
          border.width: 1

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            // Hint: Select
            Rectangle {
              implicitHeight: 24
              implicitWidth: h1Layout.implicitWidth + 10
              radius: 5
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
                spacing: 5
                Rectangle {
                  implicitHeight: 18
                  implicitWidth: Math.max(18, keyTxt1.implicitWidth + 8)
                  radius: 4
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                  border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.16)
                  border.width: 1
                  Text { id: keyTxt1; anchors.centerIn: parent; text: "J/K"; font.pixelSize: 9; font.weight: Font.Bold; color: Color.foreground }
                }
                Text { text: "Select"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: New
            Rectangle {
              implicitHeight: 24
              implicitWidth: h2Layout.implicitWidth + 10
              radius: 5
              color: h2Mouse.containsMouse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15) : "transparent"
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
                spacing: 5
                Rectangle {
                  implicitHeight: 18
                  implicitWidth: Math.max(18, keyTxt2.implicitWidth + 8)
                  radius: 4
                  color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
                  border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)
                  border.width: 1
                  Text { id: keyTxt2; anchors.centerIn: parent; text: "C"; font.pixelSize: 9; font.weight: Font.Bold; color: Color.accent }
                }
                Text { text: "New"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: Diff
            Rectangle {
              implicitHeight: 24
              implicitWidth: h3Layout.implicitWidth + 10
              radius: 5
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
                spacing: 5
                Rectangle {
                  implicitHeight: 18
                  implicitWidth: Math.max(18, keyTxt3.implicitWidth + 8)
                  radius: 4
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                  border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.16)
                  border.width: 1
                  Text { id: keyTxt3; anchors.centerIn: parent; text: "D / ↵"; font.pixelSize: 9; font.weight: Font.Bold; color: Color.foreground }
                }
                Text { text: "Diff"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: Browse
            Rectangle {
              implicitHeight: 24
              implicitWidth: h4Layout.implicitWidth + 10
              radius: 5
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
                spacing: 5
                Rectangle {
                  implicitHeight: 18
                  implicitWidth: Math.max(18, keyTxt4.implicitWidth + 8)
                  radius: 4
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                  border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.16)
                  border.width: 1
                  Text { id: keyTxt4; anchors.centerIn: parent; text: "B"; font.pixelSize: 9; font.weight: Font.Bold; color: Color.foreground }
                }
                Text { text: "Browse"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: Pin (Bright luminous yellow/gold with 📌)
            Rectangle {
              implicitHeight: 24
              implicitWidth: h5Layout.implicitWidth + 10
              radius: 5
              color: h5Mouse.containsMouse ? Qt.rgba(0.99, 0.82, 0.20, 0.22) : "transparent"
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
                spacing: 5
                Rectangle {
                  implicitHeight: 18
                  implicitWidth: Math.max(18, keyTxt5.implicitWidth + 8)
                  radius: 4
                  color: Qt.rgba(0.99, 0.82, 0.20, 0.25)
                  border.color: "#FDE047"
                  border.width: 1
                  Text { id: keyTxt5; anchors.centerIn: parent; text: "P"; font.pixelSize: 9; font.weight: Font.Bold; color: "#FDE047" }
                }
                Text { text: "󰤱 Pin"; font.pixelSize: 10; font.weight: Font.Medium; color: "#FDE047" }
              }
            }

            // Hint: Restore
            Rectangle {
              id: hintRestorePill
              implicitHeight: 24
              implicitWidth: h6Layout.implicitWidth + 10
              radius: 5
              readonly property color restoreGreen: Qt.rgba(0.13, 0.77, 0.55, 1.0)
              color: h6Mouse.containsMouse ? Qt.rgba(restoreGreen.r, restoreGreen.g, restoreGreen.b, 0.15) : "transparent"
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
                spacing: 5
                Rectangle {
                  implicitHeight: 18
                  implicitWidth: Math.max(18, keyTxt6.implicitWidth + 8)
                  radius: 4
                  color: Qt.rgba(hintRestorePill.restoreGreen.r, hintRestorePill.restoreGreen.g, hintRestorePill.restoreGreen.b, 0.18)
                  border.color: Qt.rgba(hintRestorePill.restoreGreen.r, hintRestorePill.restoreGreen.g, hintRestorePill.restoreGreen.b, 0.35)
                  border.width: 1
                  Text { id: keyTxt6; anchors.centerIn: parent; text: "R"; font.pixelSize: 9; font.weight: Font.Bold; color: hintRestorePill.restoreGreen }
                }
                Text { text: "Restore"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: Delete
            Rectangle {
              implicitHeight: 24
              implicitWidth: h7Layout.implicitWidth + 10
              radius: 5
              color: h7Mouse.containsMouse ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.15) : "transparent"
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
                spacing: 5
                Rectangle {
                  implicitHeight: 18
                  implicitWidth: Math.max(18, keyTxt7.implicitWidth + 8)
                  radius: 4
                  color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.18)
                  border.color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.35)
                  border.width: 1
                  Text { id: keyTxt7; anchors.centerIn: parent; text: "X"; font.pixelSize: 9; font.weight: Font.Bold; color: Color.urgent }
                }
                Text { text: "Delete"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: Filter
            Rectangle {
              implicitHeight: 24
              implicitWidth: h8Layout.implicitWidth + 10
              radius: 5
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
                spacing: 5
                Rectangle {
                  implicitHeight: 18
                  implicitWidth: Math.max(18, keyTxt8.implicitWidth + 8)
                  radius: 4
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                  border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.16)
                  border.width: 1
                  Text { id: keyTxt8; anchors.centerIn: parent; text: "1-4 / F"; font.pixelSize: 9; font.weight: Font.Bold; color: Color.foreground }
                }
                Text { text: "Filter"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: Search
            Rectangle {
              implicitHeight: 24
              implicitWidth: hSearchLayout.implicitWidth + 10
              radius: 5
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
                spacing: 5
                Rectangle {
                  implicitHeight: 18
                  implicitWidth: Math.max(18, keyTxtSearch.implicitWidth + 8)
                  radius: 4
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                  border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.16)
                  border.width: 1
                  Text { id: keyTxtSearch; anchors.centerIn: parent; text: "/"; font.pixelSize: 9; font.weight: Font.Bold; color: Color.foreground }
                }
                Text { text: "Search"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: Refresh
            Rectangle {
              implicitHeight: 24
              implicitWidth: h9Layout.implicitWidth + 10
              radius: 5
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
                spacing: 5
                Rectangle {
                  implicitHeight: 18
                  implicitWidth: Math.max(18, keyTxt9.implicitWidth + 8)
                  radius: 4
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                  border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.16)
                  border.width: 1
                  Text { id: keyTxt9; anchors.centerIn: parent; text: "G"; font.pixelSize: 9; font.weight: Font.Bold; color: Color.foreground }
                }
                Text { text: "Refresh"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: Optimize
            Rectangle {
              id: hintOptimizePill
              implicitHeight: 24
              implicitWidth: hOptLayout.implicitWidth + 10
              radius: 5
              readonly property color optGreen: Qt.rgba(0.13, 0.77, 0.55, 1.0)
              color: hOptMouse.containsMouse ? Qt.rgba(optGreen.r, optGreen.g, optGreen.b, 0.15) : "transparent"
              MouseArea {
                id: hOptMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.openOptimizeModal(); keyCatcher.forceActiveFocus() }
              }
              RowLayout {
                id: hOptLayout
                anchors.centerIn: parent
                spacing: 5
                Rectangle {
                  implicitHeight: 18
                  implicitWidth: Math.max(18, keyTxtOpt.implicitWidth + 8)
                  radius: 4
                  color: Qt.rgba(hintOptimizePill.optGreen.r, hintOptimizePill.optGreen.g, hintOptimizePill.optGreen.b, 0.18)
                  border.color: Qt.rgba(hintOptimizePill.optGreen.r, hintOptimizePill.optGreen.g, hintOptimizePill.optGreen.b, 0.35)
                  border.width: 1
                  Text { id: keyTxtOpt; anchors.centerIn: parent; text: "O"; font.pixelSize: 9; font.weight: Font.Bold; color: hintOptimizePill.optGreen }
                }
                Text { text: "Optimize"; font.pixelSize: 10; color: Color.muted }
              }
            }

            // Hint: Limine Boot
            Rectangle {
              id: hintLiminePill
              implicitHeight: 24
              implicitWidth: hLimineLayout.implicitWidth + 10
              radius: 5
              readonly property color limineGreen: Qt.rgba(0.13, 0.77, 0.55, 1.0)
              color: hLimineMouse.containsMouse ? Qt.rgba(limineGreen.r, limineGreen.g, limineGreen.b, 0.15) : "transparent"
              MouseArea {
                id: hLimineMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { root.openBootModal(); keyCatcher.forceActiveFocus() }
              }
              RowLayout {
                id: hLimineLayout
                anchors.centerIn: parent
                spacing: 5
                Rectangle {
                  implicitHeight: 18
                  implicitWidth: Math.max(18, keyTxtLimine.implicitWidth + 8)
                  radius: 4
                  color: Qt.rgba(hintLiminePill.limineGreen.r, hintLiminePill.limineGreen.g, hintLiminePill.limineGreen.b, 0.18)
                  border.color: Qt.rgba(hintLiminePill.limineGreen.r, hintLiminePill.limineGreen.g, hintLiminePill.limineGreen.b, 0.35)
                  border.width: 1
                  Text { id: keyTxtLimine; anchors.centerIn: parent; text: "L"; font.pixelSize: 9; font.weight: Font.Bold; color: hintLiminePill.limineGreen }
                }
                Text { text: "Limine"; font.pixelSize: 10; color: Color.muted }
              }
            }

            Item { Layout.fillWidth: true }

            // Hint: Close
            Rectangle {
              implicitHeight: 24
              implicitWidth: h10Layout.implicitWidth + 10
              radius: 5
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
                spacing: 5
                Rectangle {
                  implicitHeight: 18
                  implicitWidth: Math.max(18, keyTxt10.implicitWidth + 8)
                  radius: 4
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                  border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.16)
                  border.width: 1
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
        color: Qt.rgba(0, 0, 0, 0.68)

        MouseArea {
          anchors.fill: parent
          onClicked: root.showCreateModal = false
        }

        Rectangle {
          id: createModalCard
          anchors.centerIn: parent
          width: 500
          implicitHeight: createModalCol.implicitHeight + 40
          radius: 12
          color: Color.background
          border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)
          border.width: 1.5
          focus: root.showCreateModal

          Keys.onEscapePressed: {
            root.showCreateModal = false
            if (keyCatcher) keyCatcher.forceActiveFocus()
          }
          Keys.onReturnPressed: {
            root.submitCreateSnapshot()
            if (keyCatcher) keyCatcher.forceActiveFocus()
          }
          Keys.onEnterPressed: {
            root.submitCreateSnapshot()
            if (keyCatcher) keyCatcher.forceActiveFocus()
          }

          MouseArea { anchors.fill: parent }

          ColumnLayout {
            id: createModalCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            RowLayout {
              Layout.fillWidth: true
              spacing: 8
              Text {
                text: "󰄬"
                font.pixelSize: 18
                color: Color.accent
              }
              Text {
                text: "Create Recovery Checkpoint"
                font.pixelSize: 16
                font.weight: Font.Bold
                color: Color.foreground
              }
              Item { Layout.fillWidth: true }
              Rectangle {
                implicitWidth: 26
                implicitHeight: 26
                radius: 6
                color: createCloseHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent"
                MouseArea {
                  id: createCloseHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showCreateModal = false
                }
                Text {
                  anchors.centerIn: parent
                  text: "󰅖"
                  font.pixelSize: 13
                  color: createCloseHover.containsMouse ? Color.foreground : Color.muted
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
                  implicitWidth: chipPresetLayout.implicitWidth + 16
                  radius: 12
                  color: presetHover.containsMouse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
                  border.color: presetHover.containsMouse ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
                  border.width: 1

                  MouseArea {
                    id: presetHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      createDescInput.text = modelData
                      root.newSnapshotDesc = modelData
                      createDescInput.forceActiveFocus()
                    }
                  }

                  RowLayout {
                    id: chipPresetLayout
                    anchors.centerIn: parent
                    spacing: 4
                    Rectangle {
                      implicitHeight: 14
                      implicitWidth: altNumTxt.implicitWidth + 6
                      radius: 3
                      color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                      Text {
                        id: altNumTxt
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: "Alt+" + (index + 1)
                        font.pixelSize: 8
                        font.weight: Font.Bold
                        color: presetHover.containsMouse ? Color.accent : Color.muted
                      }
                    }
                    Text {
                      id: chipPresetText
                      textFormat: Text.PlainText
                      text: modelData
                      font.pixelSize: 10
                      font.weight: Font.Medium
                      color: presetHover.containsMouse ? Color.accent : Color.muted
                    }
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
              border.width: createDescInput.activeFocus ? 1.5 : 1

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                TextInput {
                  id: createDescInput
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
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
                  Keys.onPressed: function(event) {
                    if ((event.modifiers & Qt.ControlModifier || event.modifiers & Qt.AltModifier) && event.key === Qt.Key_P) {
                      root.newSnapshotImportant = !root.newSnapshotImportant
                      event.accepted = true
                      return
                    }
                    if (event.modifiers & Qt.AltModifier) {
                      var presets = ["Before Update", "Config Tweak", "Driver Test", "Clean State"]
                      if (event.key >= Qt.Key_1 && event.key <= Qt.Key_4) {
                        var idx = event.key - Qt.Key_1
                        if (idx < presets.length) {
                          createDescInput.text = presets[idx]
                          root.newSnapshotDesc = presets[idx]
                          event.accepted = true
                          return
                        }
                      }
                    }
                  }

                  Text {
                    anchors.fill: parent
                    text: "Enter checkpoint label (e.g., Before Hyprland tweak)..."
                    font.pixelSize: 12
                    color: Color.muted
                    visible: !parent.text && !parent.activeFocus
                  }
                }

                // Clear button if text exists
                Text {
                  visible: createDescInput.text.length > 0
                  text: "󰅖"
                  font.pixelSize: 11
                  color: Color.muted
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      createDescInput.text = ""
                      root.newSnapshotDesc = ""
                      createDescInput.forceActiveFocus()
                    }
                  }
                }
              }
            }

            // Pin / Protect Checkbox
            RowLayout {
              spacing: 10
              Rectangle {
                implicitWidth: 20
                implicitHeight: 20
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                radius: 5
                color: root.newSnapshotImportant ? Qt.rgba(0.99, 0.82, 0.20, 0.25) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
                border.color: root.newSnapshotImportant ? "#FDE047" : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.18)
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
                  font.pixelSize: 12
                  font.weight: Font.Bold
                  color: "#FDE047"
                }
              }

              RowLayout {
                spacing: 6
                Text {
                  text: "󰤱"
                  font.pixelSize: 13
                  color: root.newSnapshotImportant ? "#FDE047" : Color.muted
                }
                Text {
                  text: "Pin checkpoint (protect permanently from automatic retention pruning)"
                  font.pixelSize: 11
                  font.weight: root.newSnapshotImportant ? Font.DemiBold : Font.Normal
                  color: root.newSnapshotImportant ? "#FDE047" : Color.foreground
                }
                Rectangle {
                  implicitHeight: 16
                  implicitWidth: pinShortcutTxt.implicitWidth + 8
                  radius: 3
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                  border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)
                  border.width: 1
                  Text {
                    id: pinShortcutTxt
                    anchors.centerIn: parent
                    text: "Ctrl+P"
                    font.pixelSize: 8
                    font.weight: Font.Bold
                    color: root.newSnapshotImportant ? "#FDE047" : Color.muted
                  }
                }
              }
            }

            // Action Buttons
            RowLayout {
              Layout.fillWidth: true
              spacing: 10
              Item { Layout.fillWidth: true }

              Rectangle {
                implicitHeight: 32
                implicitWidth: createCancelLayout.implicitWidth + 20
                radius: 6
                color: createCancelHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
                border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
                border.width: 1

                MouseArea {
                  id: createCancelHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showCreateModal = false
                }
                RowLayout {
                  id: createCancelLayout
                  anchors.centerIn: parent
                  spacing: 6
                  Text {
                    text: "Cancel"
                    font.pixelSize: 11
                    color: Color.muted
                  }
                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: createEscTxt.implicitWidth + 6
                    radius: 3
                    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                    Text {
                      id: createEscTxt
                      anchors.centerIn: parent
                      text: "Esc"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: Color.muted
                    }
                  }
                }
              }

              Rectangle {
                implicitHeight: 32
                implicitWidth: createSubmitLayout.implicitWidth + 22
                radius: 6
                color: Color.accent
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.submitCreateSnapshot()
                }
                RowLayout {
                  id: createSubmitLayout
                  anchors.centerIn: parent
                  spacing: 6
                  Text {
                    text: "Create Checkpoint"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: Color.background
                  }
                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: createEnterTxt.implicitWidth + 6
                    radius: 3
                    color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.25)
                    Text {
                      id: createEnterTxt
                      anchors.centerIn: parent
                      text: "↵ Enter"
                      font.pixelSize: 8
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

      // ==========================================
      // MODAL 2: DIFF INSPECTOR MODAL
      // ==========================================
      Rectangle {
        visible: root.showDiffModal
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.68)

        MouseArea {
          anchors.fill: parent
          onClicked: root.showDiffModal = false
        }

        Rectangle {
          id: diffModalCard
          anchors.centerIn: parent
          width: 780
          height: 560
          radius: 12
          color: Color.background
          border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)
          border.width: 1.5
          focus: root.showDiffModal

          property string diffTab: "files" // "files" or "packages"

          Keys.onEscapePressed: {
            root.showDiffModal = false
            keyCatcher.forceActiveFocus()
          }

          Keys.onTabPressed: {
            diffModalCard.diffTab = (diffModalCard.diffTab === "files") ? "packages" : "files"
          }

          MouseArea { anchors.fill: parent }

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            RowLayout {
              Layout.fillWidth: true
              spacing: 8
              Text {
                text: "󰙅"
                font.pixelSize: 18
                color: Color.accent
              }
              Text {
                textFormat: Text.PlainText
                text: "Changes in Snapshot #" + root.activeDiffSnapshotId + " vs Current System"
                font.pixelSize: 16
                font.weight: Font.Bold
                color: Color.foreground
              }
              Item { Layout.fillWidth: true }
              Rectangle {
                implicitWidth: 26
                implicitHeight: 26
                radius: 6
                color: diffCloseHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent"
                MouseArea {
                  id: diffCloseHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showDiffModal = false
                }
                Text {
                  anchors.centerIn: parent
                  text: "󰅖"
                  font.pixelSize: 13
                  color: diffCloseHover.containsMouse ? Color.foreground : Color.muted
                }
              }
            }

            // View Mode Tabs: Files vs Packages
            RowLayout {
              spacing: 8
              Rectangle {
                id: tabFilesBtn
                property bool active: diffModalCard.diffTab === "files"
                implicitHeight: 28
                implicitWidth: tabFilesRow.implicitWidth + 20
                radius: 14
                color: active ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
                border.color: active ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                border.width: 1
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: diffModalCard.diffTab = "files"
                }
                RowLayout {
                  id: tabFilesRow
                  anchors.centerIn: parent
                  spacing: 6
                  Text {
                    text: "󰈔"
                    font.pixelSize: 12
                    color: tabFilesBtn.active ? Color.accent : Color.muted
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: "File Changes (" + ((root.activeDiffData && root.activeDiffData.files) ? root.activeDiffData.files.length : 0) + ")"
                    font.pixelSize: 11
                    font.weight: tabFilesBtn.active ? Font.Bold : Font.Normal
                    color: tabFilesBtn.active ? Color.accent : Color.muted
                  }
                }
              }

              Rectangle {
                id: tabPkgsBtn
                property bool active: diffModalCard.diffTab === "packages"
                property int pkgCount: (root.activeDiffData && root.activeDiffData.packageCount) || 0
                implicitHeight: 28
                implicitWidth: tabPkgsRow.implicitWidth + 20
                radius: 14
                color: active ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
                border.color: active ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                border.width: 1
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: diffModalCard.diffTab = "packages"
                }
                RowLayout {
                  id: tabPkgsRow
                  anchors.centerIn: parent
                  spacing: 6
                  Text {
                    textFormat: Text.PlainText
                    text: (root.activeDiffData && root.activeDiffData.hasCriticalPackages) ? "󰒋" : "󰏖"
                    font.pixelSize: 12
                    color: (root.activeDiffData && root.activeDiffData.hasCriticalPackages) ? "#F59E0B" : (tabPkgsBtn.active ? Color.accent : Color.muted)
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: "Package Updates (" + tabPkgsBtn.pkgCount + ")"
                    font.pixelSize: 11
                    font.weight: tabFilesBtn.active ? Font.Bold : Font.Normal
                    color: tabFilesBtn.active ? Color.accent : Color.muted
                  }
                  Rectangle {
                    visible: (root.activeDiffData && root.activeDiffData.hasCriticalPackages) === true
                    implicitHeight: 15
                    implicitWidth: critBadgeTxt.implicitWidth + 8
                    radius: 7
                    color: Qt.rgba(0.96, 0.62, 0.04, 0.25)
                    Text {
                      id: critBadgeTxt
                      anchors.centerIn: parent
                      text: "Critical"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: "#F59E0B"
                    }
                  }
                }
              }

              Item { Layout.fillWidth: true }

              RowLayout {
                spacing: 8
                Rectangle {
                  implicitHeight: 16
                  implicitWidth: tabKeyTxt.implicitWidth + 8
                  radius: 3
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                  border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)
                  border.width: 1
                  Text {
                    id: tabKeyTxt
                    anchors.centerIn: parent
                    text: "Tab"
                    font.pixelSize: 8
                    font.weight: Font.Bold
                    color: Color.muted
                  }
                }
                Text {
                  text: "Switch View"
                  font.pixelSize: 10
                  color: Color.muted
                }

                Rectangle {
                  implicitHeight: 16
                  implicitWidth: navKeyTxt.implicitWidth + 8
                  radius: 3
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                  border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)
                  border.width: 1
                  Text {
                    id: navKeyTxt
                    anchors.centerIn: parent
                    text: "↓/↑"
                    font.pixelSize: 8
                    font.weight: Font.Bold
                    color: Color.muted
                  }
                }
                Text {
                  text: "Navigate"
                  font.pixelSize: 10
                  color: Color.muted
                }

                RowLayout {
                  visible: diffModalCard.diffTab === "files"
                  spacing: 4
                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: rDiffKeyTxt.implicitWidth + 8
                    radius: 3
                    color: Qt.rgba(0.06, 0.72, 0.51, 0.15)
                    border.color: Qt.rgba(0.06, 0.72, 0.51, 0.3)
                    border.width: 1
                    Text {
                      id: rDiffKeyTxt
                      anchors.centerIn: parent
                      text: "R / ↵"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: "#10B981"
                    }
                  }
                  Text {
                    text: "Restore File"
                    font.pixelSize: 10
                    color: "#10B981"
                  }
                }

                Rectangle {
                  implicitHeight: 16
                  implicitWidth: filterKeyTxt.implicitWidth + 8
                  radius: 3
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                  border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)
                  border.width: 1
                  Text {
                    id: filterKeyTxt
                    anchors.centerIn: parent
                    text: "/"
                    font.pixelSize: 8
                    font.weight: Font.Bold
                    color: Color.muted
                  }
                }
                Text {
                  text: "Filter"
                  font.pixelSize: 10
                  color: Color.muted
                }

                Rectangle {
                  implicitHeight: 16
                  implicitWidth: escDiffKeyTxt.implicitWidth + 8
                  radius: 3
                  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                  border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)
                  border.width: 1
                  Text {
                    id: escDiffKeyTxt
                    anchors.centerIn: parent
                    text: "Esc"
                    font.pixelSize: 8
                    font.weight: Font.Bold
                    color: Color.muted
                  }
                }
                Text {
                  text: "Close"
                  font.pixelSize: 10
                  color: Color.muted
                }
              }
            }

            // Summary row
            RowLayout {
              spacing: 12

              // File summary chips (visible when files tab active)
              RowLayout {
                id: fileSummaryRow
                visible: diffModalCard.diffTab === "files"
                spacing: 8
                property var summary: (root.activeDiffData && root.activeDiffData.summary) || ({})
                Rectangle {
                  implicitHeight: 22
                  implicitWidth: addSummaryText.implicitWidth + 14
                  radius: 11
                  color: Qt.rgba(0.06, 0.72, 0.51, 0.15)
                  Text {
                    id: addSummaryText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "+" + (fileSummaryRow.summary.added || 0) + " Added"
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    color: "#10B981"
                  }
                }
                Rectangle {
                  implicitHeight: 22
                  implicitWidth: modSummaryText.implicitWidth + 14
                  radius: 11
                  color: Qt.rgba(0.96, 0.62, 0.04, 0.15)
                  Text {
                    id: modSummaryText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "~" + (fileSummaryRow.summary.modified || 0) + " Modified"
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    color: "#F59E0B"
                  }
                }
                Rectangle {
                  implicitHeight: 22
                  implicitWidth: delSummaryText.implicitWidth + 14
                  radius: 11
                  color: Qt.rgba(0.94, 0.27, 0.27, 0.15)
                  Text {
                    id: delSummaryText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "-" + (fileSummaryRow.summary.deleted || 0) + " Deleted"
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    color: "#EF4444"
                  }
                }
              }

              // Package summary text (visible when packages tab active)
              RowLayout {
                visible: diffModalCard.diffTab === "packages"
                spacing: 8
                Text {
                  textFormat: Text.PlainText
                  text: (root.activeDiffData && root.activeDiffData.packageSummary) ? ("󰏖 " + root.activeDiffData.packageSummary) : "No packages logged"
                  font.pixelSize: 11
                  color: (root.activeDiffData && root.activeDiffData.hasCriticalPackages) ? "#F59E0B" : Color.muted
                }
              }
            }

            // Search filter
            Rectangle {
              Layout.fillWidth: true
              implicitHeight: 32
              radius: 6
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
              border.color: diffFilterInput.activeFocus ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 6

                Text {
                  text: "󰍉"
                  font.pixelSize: 12
                  color: diffFilterInput.activeFocus ? Color.accent : Color.muted
                }

                TextInput {
                  id: diffFilterInput
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
                  font.pixelSize: 11
                  color: Color.foreground
                  onTextChanged: root.diffFilterQuery = text.trim().toLowerCase()
                  Keys.onEscapePressed: {
                    if (text.length > 0) text = ""
                    else root.showDiffModal = false
                    if (keyCatcher) keyCatcher.forceActiveFocus()
                  }
                  Keys.onTabPressed: function(event) {
                    diffModalCard.diffTab = (diffModalCard.diffTab === "files") ? "packages" : "files"
                    event.accepted = true
                  }
                  Keys.onBacktabPressed: function(event) {
                    diffModalCard.diffTab = (diffModalCard.diffTab === "files") ? "packages" : "files"
                    event.accepted = true
                  }
                  Keys.onDownPressed: function(event) {
                    if (diffModalCard.diffTab === "files") {
                      if (diffFilesList.count > 0) {
                        diffFilesList.currentIndex = 0
                        diffFilesList.forceActiveFocus()
                      }
                    } else {
                      if (diffPackagesList.count > 0) {
                        diffPackagesList.currentIndex = 0
                        diffPackagesList.forceActiveFocus()
                      }
                    }
                    event.accepted = true
                  }

                  Text {
                    anchors.fill: parent
                    textFormat: Text.PlainText
                    text: diffModalCard.diffTab === "files" ? "Filter changed files (e.g. /etc or .conf)..." : "Filter packages (e.g. linux, hyprland, mesa)..."
                    font.pixelSize: 11
                    color: Color.muted
                    visible: !parent.text
                  }
                }

                // Clear button
                Text {
                  visible: diffFilterInput.text.length > 0
                  text: "󰅖"
                  font.pixelSize: 11
                  color: Color.muted
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      diffFilterInput.text = ""
                      root.diffFilterQuery = ""
                    }
                  }
                }
              }
            }

            // Content View 1: Diff files list
            ScrollView {
              visible: diffModalCard.diffTab === "files"
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true

              ListView {
                id: diffFilesList
                width: parent.width
                spacing: 4
                focus: true
                currentIndex: 0
                clip: true
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

                Keys.onUpPressed: function(event) {
                  if (diffFilesList.currentIndex <= 0) {
                    diffFilterInput.forceActiveFocus()
                    event.accepted = true
                  } else {
                    diffFilesList.decrementCurrentIndex()
                    event.accepted = true
                  }
                }
                Keys.onDownPressed: function(event) {
                  if (diffFilesList.currentIndex < diffFilesList.count - 1) {
                    diffFilesList.incrementCurrentIndex()
                    event.accepted = true
                  }
                }
                Keys.onTabPressed: function(event) {
                  diffModalCard.diffTab = "packages"
                  event.accepted = true
                }
                Keys.onBacktabPressed: function(event) {
                  diffModalCard.diffTab = "packages"
                  event.accepted = true
                }
                Keys.onEscapePressed: function(event) {
                  root.showDiffModal = false
                  if (keyCatcher) keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_R || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    var raw = diffFilesList.model
                    if (raw && diffFilesList.currentIndex >= 0 && diffFilesList.currentIndex < raw.length) {
                      var item = raw[diffFilesList.currentIndex]
                      if (item && item.path) {
                        root.confirmRestoreFile(root.activeDiffSnapshotId, item.path)
                        event.accepted = true
                        return
                      }
                    }
                  } else if (event.key === Qt.Key_Slash || event.key === Qt.Key_F) {
                    diffFilterInput.forceActiveFocus()
                    diffFilterInput.selectAll()
                    event.accepted = true
                  }
                }

                delegate: Rectangle {
                  id: fileRowRect
                  width: parent.width
                  implicitHeight: 32
                  radius: 6
                  property bool isCurrent: ListView.isCurrentItem && diffFilesList.activeFocus
                  color: isCurrent ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15) : (fileRowMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.02))
                  border.color: isCurrent ? Color.accent : (fileRowMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1) : "transparent")
                  border.width: isCurrent ? 1.5 : 1

                  MouseArea {
                    id: fileRowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                      diffFilesList.currentIndex = index
                      diffFilesList.forceActiveFocus()
                    }
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 8

                    Rectangle {
                      implicitWidth: 18
                      implicitHeight: 18
                      Layout.preferredWidth: 18
                      Layout.preferredHeight: 18
                      radius: 4
                      color: modelData.status === "added" ? Qt.rgba(0.06, 0.72, 0.51, 0.2) : (modelData.status === "deleted" ? Qt.rgba(0.94, 0.27, 0.27, 0.2) : Qt.rgba(0.96, 0.62, 0.04, 0.2))
                      Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: modelData.status === "added" ? "+" : (modelData.status === "deleted" ? "-" : "~")
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: modelData.status === "added" ? "#10B981" : (modelData.status === "deleted" ? "#EF4444" : "#F59E0B")
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.path
                      font.pixelSize: 11
                      font.family: Style.fontFamily
                      color: Color.foreground
                      Layout.fillWidth: true
                      elide: Text.ElideMiddle
                    }

                    // Restore File Action Chip
                    Rectangle {
                      id: fileRestoreBtn
                      implicitHeight: 22
                      implicitWidth: resChipLayout.implicitWidth + 14
                      radius: 4
                      color: (fileRowRect.isCurrent || fileRestoreBtnMouse.containsMouse) ? Qt.rgba(0.06, 0.72, 0.51, 0.25) : Qt.rgba(0.06, 0.72, 0.51, 0.12)
                      border.color: (fileRowRect.isCurrent || fileRestoreBtnMouse.containsMouse) ? "#10B981" : Qt.rgba(0.06, 0.72, 0.51, 0.3)
                      border.width: 1

                      MouseArea {
                        id: fileRestoreBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.confirmRestoreFile(root.activeDiffSnapshotId, modelData.path)
                      }

                      RowLayout {
                        id: resChipLayout
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                          text: "󰁌"
                          font.pixelSize: 11
                          color: "#10B981"
                        }
                        Text {
                          text: "Restore"
                          font.pixelSize: 10
                          font.weight: Font.Bold
                          color: "#10B981"
                        }
                        Rectangle {
                          visible: fileRowRect.isCurrent
                          implicitHeight: 14
                          implicitWidth: rKeyTxt.implicitWidth + 4
                          radius: 2
                          color: Qt.rgba(0.06, 0.72, 0.51, 0.3)
                          Text {
                            id: rKeyTxt
                            anchors.centerIn: parent
                            text: "R"
                            font.pixelSize: 8
                            font.weight: Font.Bold
                            color: "#10B981"
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            // Content View 2: Package updates list
            ScrollView {
              visible: diffModalCard.diffTab === "packages"
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true

              ListView {
                id: diffPackagesList
                width: parent.width
                spacing: 6
                focus: true
                currentIndex: 0
                clip: true
                model: {
                  var raw = (root.activeDiffData && root.activeDiffData.packages) || []
                  if (!root.diffFilterQuery) return raw
                  var filtered = []
                  for (var i = 0; i < raw.length; i++) {
                    var n = (raw[i].name || "").toLowerCase()
                    var v = (raw[i].version || "").toLowerCase()
                    var c = (raw[i].criticalCategory || "").toLowerCase()
                    if (n.indexOf(root.diffFilterQuery) !== -1 || v.indexOf(root.diffFilterQuery) !== -1 || c.indexOf(root.diffFilterQuery) !== -1) {
                      filtered.push(raw[i])
                    }
                  }
                  return filtered
                }

                Keys.onUpPressed: function(event) {
                  if (diffPackagesList.currentIndex <= 0) {
                    diffFilterInput.forceActiveFocus()
                    event.accepted = true
                  } else {
                    diffPackagesList.decrementCurrentIndex()
                    event.accepted = true
                  }
                }
                Keys.onDownPressed: function(event) {
                  if (diffPackagesList.currentIndex < diffPackagesList.count - 1) {
                    diffPackagesList.incrementCurrentIndex()
                    event.accepted = true
                  }
                }
                Keys.onTabPressed: function(event) {
                  diffModalCard.diffTab = "files"
                  event.accepted = true
                }
                Keys.onBacktabPressed: function(event) {
                  diffModalCard.diffTab = "files"
                  event.accepted = true
                }
                Keys.onEscapePressed: function(event) {
                  root.showDiffModal = false
                  if (keyCatcher) keyCatcher.forceActiveFocus()
                  event.accepted = true
                }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Slash || event.key === Qt.Key_F) {
                    diffFilterInput.forceActiveFocus()
                    diffFilterInput.selectAll()
                    event.accepted = true
                  }
                }

                // Empty packages state
                Item {
                  visible: parent.count === 0
                  anchors.centerIn: parent
                  width: parent.width
                  height: 120
                  ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text { Layout.alignment: Qt.AlignHCenter; text: "󰏖"; font.pixelSize: 28; color: Color.muted }
                    Text {
                      Layout.alignment: Qt.AlignHCenter
                      textFormat: Text.PlainText
                      text: (root.activeDiffData && root.activeDiffData.packageCount > 0) ? "No packages match filter." : "No package changes recorded for this snapshot."
                      font.pixelSize: 12
                      color: Color.muted
                    }
                  }
                }

                delegate: Rectangle {
                  width: parent.width
                  implicitHeight: 34
                  radius: 6
                  property bool isCurrent: ListView.isCurrentItem && diffPackagesList.activeFocus
                  color: isCurrent
                    ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
                    : (modelData.isCritical ? Qt.rgba(0.96, 0.62, 0.04, 0.08) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.03))
                  border.color: isCurrent
                    ? Color.accent
                    : (modelData.isCritical ? Qt.rgba(0.96, 0.62, 0.04, 0.3) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06))
                  border.width: isCurrent ? 1.5 : 1

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                      diffPackagesList.currentIndex = index
                      diffPackagesList.forceActiveFocus()
                    }
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    // Action pill
                    Rectangle {
                      implicitHeight: 20
                      implicitWidth: actTxt.implicitWidth + 10
                      radius: 4
                      color: modelData.action === "installed" ? Qt.rgba(0.06, 0.72, 0.51, 0.2) : (modelData.action === "removed" ? Qt.rgba(0.94, 0.27, 0.27, 0.2) : (modelData.action === "reinstalled" ? Qt.rgba(0.96, 0.62, 0.04, 0.2) : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2)))
                      Text {
                        id: actTxt
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: modelData.action
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: modelData.action === "installed" ? "#10B981" : (modelData.action === "removed" ? "#EF4444" : (modelData.action === "reinstalled" ? "#F59E0B" : Color.accent))
                      }
                    }

                    // Package name
                    Text {
                      textFormat: Text.PlainText
                      text: modelData.name
                      font.pixelSize: 12
                      font.weight: Font.DemiBold
                      color: Color.foreground
                    }

                    // Critical Category Tag
                    Rectangle {
                      visible: modelData.isCritical === true
                      implicitHeight: 18
                      implicitWidth: catTxt.implicitWidth + 10
                      radius: 4
                      color: Qt.rgba(0.96, 0.62, 0.04, 0.2)
                      border.color: "#F59E0B"
                      border.width: 1
                      RowLayout {
                        anchors.centerIn: parent
                        spacing: 3
                        Text { text: "󰒋"; font.pixelSize: 9; color: "#F59E0B" }
                        Text {
                          id: catTxt
                          textFormat: Text.PlainText
                          text: modelData.criticalCategory || "Critical"
                          font.pixelSize: 9
                          font.weight: Font.Bold
                          color: "#F59E0B"
                        }
                      }
                    }

                    Item { Layout.fillWidth: true }

                    // Version transition
                    Text {
                      textFormat: Text.PlainText
                      text: modelData.version || ""
                      font.pixelSize: 11
                      font.family: Style.fontFamily
                      color: Color.muted
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
        color: Qt.rgba(0, 0, 0, 0.68)

        MouseArea {
          anchors.fill: parent
          onClicked: root.showRestoreModal = false
        }

        Rectangle {
          id: restoreModalCard
          anchors.centerIn: parent
          width: 520
          implicitHeight: restoreCol.implicitHeight + 40
          radius: 12
          color: Color.background
          border.color: Qt.rgba(0.06, 0.72, 0.51, 0.45)
          border.width: 1.5
          focus: root.showRestoreModal

          Keys.onEscapePressed: {
            root.showRestoreModal = false
            if (keyCatcher) keyCatcher.forceActiveFocus()
          }
          Keys.onReturnPressed: root.executeRestore()
          Keys.onEnterPressed: root.executeRestore()
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_R) {
              root.executeRestore()
              event.accepted = true
            }
          }

          MouseArea { anchors.fill: parent }

          ColumnLayout {
            id: restoreCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            RowLayout {
              Layout.fillWidth: true
              spacing: 10
              Text { text: "󰁯"; font.pixelSize: 22; color: "#10B981" }
              Text {
                textFormat: Text.PlainText
                text: "Restore System to Snapshot #" + (root.activeRestoreSnapshot ? root.activeRestoreSnapshot.id : "")
                font.pixelSize: 16
                font.weight: Font.Bold
                color: Color.foreground
              }
              Item { Layout.fillWidth: true }
              Rectangle {
                implicitWidth: 26
                implicitHeight: 26
                radius: 6
                color: resCloseHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent"
                MouseArea {
                  id: resCloseHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showRestoreModal = false
                }
                Text {
                  anchors.centerIn: parent
                  text: "󰅖"
                  font.pixelSize: 13
                  color: resCloseHover.containsMouse ? Color.foreground : Color.muted
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "This will invoke Limine & Snapper rollback to restore the root filesystem to the state recorded at " + (root.activeRestoreSnapshot ? root.activeRestoreSnapshot.date : "") + " (" + (root.activeRestoreSnapshot ? root.activeRestoreSnapshot.description : "") + ").\n\nAll package and root system changes made since this snapshot will be reverted upon reboot."
              font.pixelSize: 12
              color: Color.muted
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            // Safety Guarantee Callout Box
            Rectangle {
              Layout.fillWidth: true
              implicitHeight: restoreSafeCol.implicitHeight + 16
              radius: 6
              color: Qt.rgba(0.06, 0.72, 0.51, 0.08)
              border.color: Qt.rgba(0.06, 0.72, 0.51, 0.25)
              border.width: 1

              ColumnLayout {
                id: restoreSafeCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 4
                RowLayout {
                  spacing: 6
                  Text { text: "󰞌"; font.pixelSize: 13; color: "#10B981" }
                  Text {
                    text: "Safety Guarantee: Non-Destructive Rollback"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: "#10B981"
                  }
                }
                Text {
                  text: "The current system state is automatically captured into a pre-restore backup snapshot before applying changes. You can always boot back into your existing setup via Limine if needed."
                  font.pixelSize: 10
                  color: Color.muted
                  wrapMode: Text.WordWrap
                  Layout.fillWidth: true
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 10
              Item { Layout.fillWidth: true }

              Rectangle {
                implicitHeight: 32
                implicitWidth: resCancelLayout.implicitWidth + 20
                radius: 6
                color: resCancelHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
                border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
                border.width: 1
                MouseArea {
                  id: resCancelHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showRestoreModal = false
                }
                RowLayout {
                  id: resCancelLayout
                  anchors.centerIn: parent
                  spacing: 6
                  Text {
                    text: "Cancel"
                    font.pixelSize: 11
                    color: Color.muted
                  }
                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: resEscTxt.implicitWidth + 6
                    radius: 3
                    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                    Text {
                      id: resEscTxt
                      anchors.centerIn: parent
                      text: "Esc"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: Color.muted
                    }
                  }
                }
              }

              Rectangle {
                implicitHeight: 32
                implicitWidth: resSubmitLayout.implicitWidth + 22
                radius: 6
                color: "#10B981"
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.executeRestore()
                }
                RowLayout {
                  id: resSubmitLayout
                  anchors.centerIn: parent
                  spacing: 6
                  Text {
                    text: "Proceed to Restore"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: "#ffffff"
                  }
                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: resEnterTxt.implicitWidth + 6
                    radius: 3
                    color: Qt.rgba(0, 0, 0, 0.2)
                    Text {
                      id: resEnterTxt
                      anchors.centerIn: parent
                      text: "↵ Enter"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: "#ffffff"
                    }
                  }
                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: resKeyRBadge.implicitWidth + 6
                    radius: 3
                    color: Qt.rgba(0, 0, 0, 0.2)
                    Text {
                      id: resKeyRBadge
                      anchors.centerIn: parent
                      text: "R"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: "#ffffff"
                    }
                  }
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
        color: Qt.rgba(0, 0, 0, 0.68)

        MouseArea {
          anchors.fill: parent
          onClicked: root.showDeleteModal = false
        }

        Rectangle {
          id: deleteModalCard
          anchors.centerIn: parent
          width: 480
          implicitHeight: deleteCol.implicitHeight + 40
          radius: 12
          color: Color.background
          border.color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.55)
          border.width: 1.5
          focus: root.showDeleteModal

          Keys.onEscapePressed: {
            root.showDeleteModal = false
            if (keyCatcher) keyCatcher.forceActiveFocus()
          }
          Keys.onReturnPressed: root.executeDelete()
          Keys.onEnterPressed: root.executeDelete()
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_D || event.key === Qt.Key_X) {
              root.executeDelete()
              event.accepted = true
            }
          }

          MouseArea { anchors.fill: parent }

          ColumnLayout {
            id: deleteCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            RowLayout {
              Layout.fillWidth: true
              spacing: 10
              Text { text: "󰆴"; font.pixelSize: 22; color: Color.urgent }
              Text {
                textFormat: Text.PlainText
                text: "Delete Snapshot #" + (root.activeDeleteSnapshot ? root.activeDeleteSnapshot.id : "")
                font.pixelSize: 16
                font.weight: Font.Bold
                color: Color.foreground
              }
              Item { Layout.fillWidth: true }
              Rectangle {
                implicitWidth: 26
                implicitHeight: 26
                radius: 6
                color: delCloseHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent"
                MouseArea {
                  id: delCloseHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showDeleteModal = false
                }
                Text {
                  anchors.centerIn: parent
                  text: "󰅖"
                  font.pixelSize: 13
                  color: delCloseHover.containsMouse ? Color.foreground : Color.muted
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "Are you sure you want to permanently delete snapshot #" + (root.activeDeleteSnapshot ? root.activeDeleteSnapshot.id : "") + " (" + (root.activeDeleteSnapshot ? root.activeDeleteSnapshot.description : "") + ")?\nThis recovery point and its boot entry will be permanently removed."
              font.pixelSize: 12
              color: Color.muted
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            // Irreversible Deletion Warning Box
            Rectangle {
              Layout.fillWidth: true
              implicitHeight: delWarnCol.implicitHeight + 16
              radius: 6
              color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.08)
              border.color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.25)
              border.width: 1

              ColumnLayout {
                id: delWarnCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 4
                RowLayout {
                  spacing: 6
                  Text { text: "󰅚"; font.pixelSize: 13; color: Color.urgent }
                  Text {
                    text: "Irreversible Action Safeguard"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: Color.urgent
                  }
                }
                Text {
                  text: "The underlying subvolume data will be permanently freed from disk. This snapshot cannot be recovered after deletion."
                  font.pixelSize: 10
                  color: Color.muted
                  wrapMode: Text.WordWrap
                  Layout.fillWidth: true
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 10
              Item { Layout.fillWidth: true }

              Rectangle {
                implicitHeight: 32
                implicitWidth: delCancelLayout.implicitWidth + 20
                radius: 6
                color: delCancelHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
                border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
                border.width: 1
                MouseArea {
                  id: delCancelHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showDeleteModal = false
                }
                RowLayout {
                  id: delCancelLayout
                  anchors.centerIn: parent
                  spacing: 6
                  Text {
                    text: "Cancel"
                    font.pixelSize: 11
                    color: Color.muted
                  }
                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: delEscTxt.implicitWidth + 6
                    radius: 3
                    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                    Text {
                      id: delEscTxt
                      anchors.centerIn: parent
                      text: "Esc"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: Color.muted
                    }
                  }
                }
              }

              Rectangle {
                implicitHeight: 32
                implicitWidth: delSubmitLayout.implicitWidth + 22
                radius: 6
                color: Color.urgent
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.executeDelete()
                }
                RowLayout {
                  id: delSubmitLayout
                  anchors.centerIn: parent
                  spacing: 6
                  Text {
                    text: "Delete Snapshot"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: "#ffffff"
                  }
                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: delEnterTxt.implicitWidth + 6
                    radius: 3
                    color: Qt.rgba(0, 0, 0, 0.25)
                    Text {
                      id: delEnterTxt
                      anchors.centerIn: parent
                      text: "↵ Enter"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: "#ffffff"
                    }
                  }
                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: delKeyDBadge.implicitWidth + 6
                    radius: 3
                    color: Qt.rgba(0, 0, 0, 0.25)
                    Text {
                      id: delKeyDBadge
                      anchors.centerIn: parent
                      text: "D"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: "#ffffff"
                    }
                  }
                }
              }
            }
          }
        }
      }

      // ==========================================
      // MODAL 5: RESTORE FILE CONFIRMATION DIALOG
      // ==========================================
      Rectangle {
        visible: root.showRestoreFileModal
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.68)

        MouseArea {
          anchors.fill: parent
          onClicked: root.showRestoreFileModal = false
        }

        Rectangle {
          id: restoreFileModalCard
          anchors.centerIn: parent
          width: 520
          implicitHeight: restoreFileCol.implicitHeight + 40
          radius: 12
          color: Color.background
          border.color: Qt.rgba(0.06, 0.72, 0.51, 0.45)
          border.width: 1.5
          focus: root.showRestoreFileModal

          Keys.onEscapePressed: {
            root.showRestoreFileModal = false
            if (keyCatcher) keyCatcher.forceActiveFocus()
          }
          Keys.onReturnPressed: root.executeRestoreFile()
          Keys.onEnterPressed: root.executeRestoreFile()
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_R) {
              root.executeRestoreFile()
              event.accepted = true
            }
          }

          MouseArea { anchors.fill: parent }

          ColumnLayout {
            id: restoreFileCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            RowLayout {
              Layout.fillWidth: true
              spacing: 10
              Text { text: "󰁌"; font.pixelSize: 22; color: "#10B981" }
              Text {
                textFormat: Text.PlainText
                text: "Roll Back File from Snapshot #" + root.activeRestoreFileSnapshotId
                font.pixelSize: 16
                font.weight: Font.Bold
                color: Color.foreground
              }
              Item { Layout.fillWidth: true }
              Rectangle {
                implicitWidth: 26
                implicitHeight: 26
                radius: 6
                color: resFileCloseHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent"
                MouseArea {
                  id: resFileCloseHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showRestoreFileModal = false
                }
                Text {
                  anchors.centerIn: parent
                  text: "󰅖"
                  font.pixelSize: 13
                  color: resFileCloseHover.containsMouse ? Color.foreground : Color.muted
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "Restore this individual file to its exact state recorded in snapshot #" + root.activeRestoreFileSnapshotId + ":"
              font.pixelSize: 12
              color: Color.muted
              wrapMode: Text.WordWrap
              Layout.fillWidth: true
            }

            Rectangle {
              Layout.fillWidth: true
              implicitHeight: 36
              radius: 6
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
              border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                Text { text: "󰈔"; font.pixelSize: 14; color: Color.accent }
                Text {
                  textFormat: Text.PlainText
                  text: root.activeRestoreFilePath
                  font.pixelSize: 12
                  font.family: Style.fontFamily
                  font.weight: Font.Bold
                  color: Color.foreground
                  elide: Text.ElideMiddle
                  Layout.fillWidth: true
                }
              }
            }

            // Safety Guarantee Callout Box
            Rectangle {
              Layout.fillWidth: true
              implicitHeight: safetyCol.implicitHeight + 16
              radius: 6
              color: Qt.rgba(0.06, 0.72, 0.51, 0.08)
              border.color: Qt.rgba(0.06, 0.72, 0.51, 0.25)
              border.width: 1

              ColumnLayout {
                id: safetyCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 4

                RowLayout {
                  spacing: 6
                  Text { text: "󰞌"; font.pixelSize: 13; color: "#10B981" }
                  Text {
                    text: "Safety Guarantee: Automatic Backup"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: "#10B981"
                  }
                }
                Text {
                  textFormat: Text.PlainText
                  text: "The current live file will be safely preserved as a timestamped backup (" + root.activeRestoreFilePath + ".bak.<timestamp>) before applying changes."
                  font.pixelSize: 10
                  color: Color.muted
                  wrapMode: Text.WordWrap
                  Layout.fillWidth: true
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 10
              Item { Layout.fillWidth: true }

              Rectangle {
                implicitHeight: 32
                implicitWidth: resFileCancelLayout.implicitWidth + 20
                radius: 6
                color: resFileCancelHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
                border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
                border.width: 1
                MouseArea {
                  id: resFileCancelHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showRestoreFileModal = false
                }
                RowLayout {
                  id: resFileCancelLayout
                  anchors.centerIn: parent
                  spacing: 6
                  Text {
                    text: "Cancel"
                    font.pixelSize: 11
                    color: Color.muted
                  }
                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: resFileEscTxt.implicitWidth + 6
                    radius: 3
                    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                    Text {
                      id: resFileEscTxt
                      anchors.centerIn: parent
                      text: "Esc"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: Color.muted
                    }
                  }
                }
              }

              Rectangle {
                implicitHeight: 32
                implicitWidth: resFileSubmitLayout.implicitWidth + 22
                radius: 6
                color: "#10B981"
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.executeRestoreFile()
                }
                RowLayout {
                  id: resFileSubmitLayout
                  anchors.centerIn: parent
                  spacing: 6
                  Text {
                    text: "Restore File"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: "#ffffff"
                  }
                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: resFileEnterTxt.implicitWidth + 6
                    radius: 3
                    color: Qt.rgba(0, 0, 0, 0.2)
                    Text {
                      id: resFileEnterTxt
                      anchors.centerIn: parent
                      text: "↵ Enter"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: "#ffffff"
                    }
                  }
                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: resFileKeyRBadge.implicitWidth + 6
                    radius: 3
                    color: Qt.rgba(0, 0, 0, 0.2)
                    Text {
                      id: resFileKeyRBadge
                      anchors.centerIn: parent
                      text: "R"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: "#ffffff"
                    }
                  }
                }
              }
            }
          }
        }
      }

      // ==========================================
      // MODAL 6: SMART DISK OPTIMIZER & RETENTION GUARD
      // ==========================================
      Rectangle {
        visible: root.showOptimizeModal
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.68)

        MouseArea {
          anchors.fill: parent
          onClicked: {
            if (!root.isOptimizing) root.showOptimizeModal = false
          }
        }

        Rectangle {
          id: optimizeModalCard
          anchors.centerIn: parent
          width: 600
          implicitHeight: Math.min(540, optimizeCol.implicitHeight + 40)
          radius: 12
          color: Color.background
          border.color: Qt.rgba(0.06, 0.72, 0.51, 0.45)
          border.width: 1.5
          focus: root.showOptimizeModal

          Keys.onEscapePressed: {
            if (!root.isOptimizing) {
              root.showOptimizeModal = false
              if (keyCatcher) keyCatcher.forceActiveFocus()
            }
          }
          Keys.onReturnPressed: {
            if (!root.isOptimizing && root.activeOptimizeData && root.activeOptimizeData.prunableCount > 0) {
              root.executeOptimize()
            }
          }
          Keys.onEnterPressed: {
            if (!root.isOptimizing && root.activeOptimizeData && root.activeOptimizeData.prunableCount > 0) {
              root.executeOptimize()
            }
          }
          Keys.onPressed: function(event) {
            if (!root.isOptimizing && (event.key === Qt.Key_O || event.key === Qt.Key_C)) {
              if (root.activeOptimizeData && root.activeOptimizeData.prunableCount > 0) {
                root.executeOptimize()
                event.accepted = true
              }
            }
          }

          MouseArea { anchors.fill: parent }

          ColumnLayout {
            id: optimizeCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // Title & Icon + Close
            RowLayout {
              Layout.fillWidth: true
              spacing: 10
              Text { text: "󰚰"; font.pixelSize: 22; color: "#10B981" }
              ColumnLayout {
                spacing: 2
                Text {
                  text: "Smart Btrfs Disk Optimizer"
                  font.pixelSize: 16
                  font.weight: Font.Bold
                  color: Color.foreground
                }
                Text {
                  textFormat: Text.PlainText
                  text: (root.activeOptimizeData && root.activeOptimizeData.retentionPolicy) || "Analyzing retention guards and space reclamation..."
                  font.pixelSize: 11
                  color: Color.muted
                }
              }
              Item { Layout.fillWidth: true }
              Rectangle {
                implicitWidth: 26
                implicitHeight: 26
                radius: 6
                color: optCloseHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent"
                MouseArea {
                  id: optCloseHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (!root.isOptimizing) root.showOptimizeModal = false
                  }
                }
                Text {
                  anchors.centerIn: parent
                  text: "󰅖"
                  font.pixelSize: 13
                  color: optCloseHover.containsMouse ? Color.foreground : Color.muted
                }
              }
            }

            // Stat tiles grid
            RowLayout {
              Layout.fillWidth: true
              spacing: 8

              // Tile 1: Total
              Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                radius: 6
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
                border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                ColumnLayout {
                  anchors.centerIn: parent
                  spacing: 2
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    textFormat: Text.PlainText
                    text: String((root.activeOptimizeData && root.activeOptimizeData.totalSnapshots) || 0)
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    color: Color.foreground
                  }
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Total Points"
                    font.pixelSize: 9
                    color: Color.muted
                  }
                }
              }

              // Tile 2: Protected
              Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                radius: 6
                color: Qt.rgba(0.06, 0.72, 0.51, 0.08)
                border.color: Qt.rgba(0.06, 0.72, 0.51, 0.25)
                ColumnLayout {
                  anchors.centerIn: parent
                  spacing: 2
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    textFormat: Text.PlainText
                    text: String((root.activeOptimizeData && root.activeOptimizeData.protectedCount) || 0)
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    color: "#10B981"
                  }
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󰞌 Protected"
                    font.pixelSize: 9
                    font.weight: Font.Medium
                    color: "#10B981"
                  }
                }
              }

              // Tile 3: Prunable
              Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                radius: 6
                color: Qt.rgba(0.96, 0.62, 0.04, 0.08)
                border.color: Qt.rgba(0.96, 0.62, 0.04, 0.25)
                ColumnLayout {
                  anchors.centerIn: parent
                  spacing: 2
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    textFormat: Text.PlainText
                    text: String((root.activeOptimizeData && root.activeOptimizeData.prunableCount) || 0)
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    color: "#F59E0B"
                  }
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󰆴 Prunable Stale"
                    font.pixelSize: 9
                    font.weight: Font.Medium
                    color: "#F59E0B"
                  }
                }
              }

              // Tile 4: Potential Reclaim
              Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                radius: 6
                color: Qt.rgba(0.06, 0.72, 0.51, 0.15)
                border.color: "#10B981"
                ColumnLayout {
                  anchors.centerIn: parent
                  spacing: 2
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    textFormat: Text.PlainText
                    text: (root.activeOptimizeData && root.activeOptimizeData.reclaimableHuman) ? ("~" + root.activeOptimizeData.reclaimableHuman) : "0 B"
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    color: "#10B981"
                  }
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󰚰 Est. Reclaim"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    color: "#10B981"
                  }
                }
              }
            }

            // Safety Guard Policy banner
            Rectangle {
              Layout.fillWidth: true
              implicitHeight: guardCol.implicitHeight + 14
              radius: 6
              color: Qt.rgba(0.06, 0.72, 0.51, 0.05)
              border.color: Qt.rgba(0.06, 0.72, 0.51, 0.2)
              border.width: 1

              ColumnLayout {
                id: guardCol
                anchors.fill: parent
                anchors.margins: 10
                spacing: 4
                RowLayout {
                  spacing: 6
                  Text { text: "󰞌"; font.pixelSize: 12; color: "#10B981" }
                  Text {
                    text: "Safe Retention Guard Active"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: "#10B981"
                  }
                }
                Text {
                  text: "Pinned checkpoints (󰤱), the newest system state, and recent recovery points are strictly locked against pruning. Only stale checkpoints outside retention limits will be reclaimed."
                  font.pixelSize: 10
                  color: Color.muted
                  wrapMode: Text.WordWrap
                  Layout.fillWidth: true
                }
              }
            }

            // Prunable Candidates Subhead
            Text {
              text: "Eligible Stale Snapshots for Reclaim:"
              font.pixelSize: 12
              font.weight: Font.Bold
              color: Color.foreground
            }

            // Prunable Candidates List
            ScrollView {
              Layout.fillWidth: true
              implicitHeight: 130
              clip: true

              ListView {
                id: optimizeCandidatesList
                width: parent.width
                spacing: 4
                focus: true
                currentIndex: 0
                clip: true
                model: (root.activeOptimizeData && root.activeOptimizeData.prunableSnapshots) || []

                Keys.onUpPressed: function(event) {
                  if (optimizeCandidatesList.currentIndex > 0) {
                    optimizeCandidatesList.decrementCurrentIndex()
                    event.accepted = true
                  }
                }
                Keys.onDownPressed: function(event) {
                  if (optimizeCandidatesList.currentIndex < optimizeCandidatesList.count - 1) {
                    optimizeCandidatesList.incrementCurrentIndex()
                    event.accepted = true
                  }
                }
                Keys.onEscapePressed: {
                  if (!root.isOptimizing) {
                    root.showOptimizeModal = false
                    if (keyCatcher) keyCatcher.forceActiveFocus()
                  }
                }
                Keys.onReturnPressed: {
                  if (!root.isOptimizing && root.activeOptimizeData && root.activeOptimizeData.prunableCount > 0) {
                    root.executeOptimize()
                  }
                }
                Keys.onEnterPressed: {
                  if (!root.isOptimizing && root.activeOptimizeData && root.activeOptimizeData.prunableCount > 0) {
                    root.executeOptimize()
                  }
                }

                // Empty state if no prunable
                Item {
                  visible: parent.count === 0
                  anchors.centerIn: parent
                  width: parent.width
                  height: 90
                  ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    Text { Layout.alignment: Qt.AlignHCenter; text: "󰄬"; font.pixelSize: 22; color: "#10B981" }
                    Text {
                      Layout.alignment: Qt.AlignHCenter
                      text: "All recovery points are protected or recent. Storage is fully optimized!"
                      font.pixelSize: 11
                      color: Color.muted
                    }
                  }
                }

                delegate: Rectangle {
                  width: parent.width
                  implicitHeight: 30
                  radius: 4
                  property bool isCurrent: ListView.isCurrentItem && optimizeCandidatesList.activeFocus
                  color: isCurrent
                    ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
                    : (optItemMouse.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.02))
                  border.color: isCurrent ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)
                  border.width: isCurrent ? 1.5 : 1

                  MouseArea {
                    id: optItemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                      optimizeCandidatesList.currentIndex = index
                      optimizeCandidatesList.forceActiveFocus()
                    }
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 8

                    Text {
                      textFormat: Text.PlainText
                      text: "#" + modelData.id
                      font.pixelSize: 11
                      font.weight: Font.Bold
                      color: Color.foreground
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.description || ""
                      font.pixelSize: 11
                      color: Color.muted
                      Layout.fillWidth: true
                      elide: Text.ElideRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.age || ""
                      font.pixelSize: 10
                      color: Color.muted
                    }

                    Rectangle {
                      implicitHeight: 18
                      implicitWidth: estTxt.implicitWidth + 8
                      radius: 3
                      color: Qt.rgba(0.06, 0.72, 0.51, 0.15)
                      Text {
                        id: estTxt
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: "~" + (modelData.estimatedHuman || "")
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: "#10B981"
                      }
                    }
                  }
                }
              }
            }

            // Bottom action buttons
            RowLayout {
              Layout.fillWidth: true
              spacing: 10
              Item { Layout.fillWidth: true }

              Rectangle {
                implicitHeight: 32
                implicitWidth: optCancelLayout.implicitWidth + 20
                radius: 6
                color: optCancelHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
                border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
                border.width: 1
                MouseArea {
                  id: optCancelHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (!root.isOptimizing) root.showOptimizeModal = false
                  }
                }
                RowLayout {
                  id: optCancelLayout
                  anchors.centerIn: parent
                  spacing: 6
                  Text {
                    text: "Cancel"
                    font.pixelSize: 11
                    color: Color.muted
                  }
                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: optEscTxt.implicitWidth + 6
                    radius: 3
                    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                    Text {
                      id: optEscTxt
                      anchors.centerIn: parent
                      text: "Esc"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: Color.muted
                    }
                  }
                }
              }

              Rectangle {
                implicitHeight: 32
                implicitWidth: optSubmitLayout.implicitWidth + 22
                radius: 6
                color: (root.activeOptimizeData && root.activeOptimizeData.prunableCount > 0 && !root.isOptimizing) ? "#10B981" : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
                opacity: (root.activeOptimizeData && root.activeOptimizeData.prunableCount > 0 && !root.isOptimizing) ? 1.0 : 0.6

                MouseArea {
                  anchors.fill: parent
                  cursorShape: (root.activeOptimizeData && root.activeOptimizeData.prunableCount > 0 && !root.isOptimizing) ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: {
                    if (root.activeOptimizeData && root.activeOptimizeData.prunableCount > 0 && !root.isOptimizing) {
                      root.executeOptimize()
                    }
                  }
                }

                RowLayout {
                  id: optSubmitLayout
                  anchors.centerIn: parent
                  spacing: 6
                  Text {
                    textFormat: Text.PlainText
                    text: root.isOptimizing ? "󰑐" : "󰚰"
                    font.pixelSize: 13
                    color: (root.activeOptimizeData && root.activeOptimizeData.prunableCount > 0 && !root.isOptimizing) ? "#ffffff" : Color.muted
                    rotation: root.isOptimizing ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 400 } }
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: root.isOptimizing ? "Pruning Snapshots..." : "Clean & Reclaim Space"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: (root.activeOptimizeData && root.activeOptimizeData.prunableCount > 0 && !root.isOptimizing) ? "#ffffff" : Color.muted
                  }
                  Rectangle {
                    visible: (root.activeOptimizeData && root.activeOptimizeData.prunableCount > 0 && !root.isOptimizing)
                    implicitHeight: 16
                    implicitWidth: optEnterTxt.implicitWidth + 6
                    radius: 3
                    color: Qt.rgba(0, 0, 0, 0.2)
                    Text {
                      id: optEnterTxt
                      anchors.centerIn: parent
                      text: "↵ Enter"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: "#ffffff"
                    }
                  }
                  Rectangle {
                    visible: (root.activeOptimizeData && root.activeOptimizeData.prunableCount > 0 && !root.isOptimizing)
                    implicitHeight: 16
                    implicitWidth: optKeyOBadge.implicitWidth + 6
                    radius: 3
                    color: Qt.rgba(0, 0, 0, 0.2)
                    Text {
                      id: optKeyOBadge
                      anchors.centerIn: parent
                      text: "O"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: "#ffffff"
                    }
                  }
                }
              }
            }
          }
        }
      }

      // ==========================================
      // MODAL 7: LIMINE BOOTLOADER VERIFICATION & HEALTH
      // ==========================================
      Rectangle {
        visible: root.showBootModal
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.68)

        MouseArea {
          anchors.fill: parent
          onClicked: {
            if (!root.isSyncingBoot) root.showBootModal = false
          }
        }

        Rectangle {
          id: bootModalCard
          anchors.centerIn: parent
          width: 660
          implicitHeight: Math.min(540, bootCol.implicitHeight + 40)
          radius: 12
          color: Color.background
          border.color: Qt.rgba(0.06, 0.72, 0.51, 0.45)
          border.width: 1.5
          focus: root.showBootModal

          Keys.onEscapePressed: {
            if (!root.isSyncingBoot) {
              root.showBootModal = false
              if (keyCatcher) keyCatcher.forceActiveFocus()
            }
          }
          Keys.onReturnPressed: {
            if (!root.isSyncingBoot) {
              root.executeBootSync()
            }
          }
          Keys.onEnterPressed: {
            if (!root.isSyncingBoot) {
              root.executeBootSync()
            }
          }
          Keys.onPressed: function(event) {
            if (!root.isSyncingBoot && (event.key === Qt.Key_S || event.key === Qt.Key_B)) {
              root.executeBootSync()
              event.accepted = true
            }
          }

          MouseArea { anchors.fill: parent }

          ColumnLayout {
            id: bootCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // Title & Icon + Health Badge + Close Button
            RowLayout {
              Layout.fillWidth: true
              spacing: 10
              Text { text: "󰌢"; font.pixelSize: 22; color: "#10B981" }
              ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                  text: "Limine Bootloader Verification & Health"
                  font.pixelSize: 16
                  font.weight: Font.Bold
                  color: Color.foreground
                }
                Text {
                  textFormat: Text.PlainText
                  text: (root.activeBootData && root.activeBootData.healthReason) || "Inspecting Limine configuration, EFI kernel payloads and ESP headroom..."
                  font.pixelSize: 11
                  color: Color.muted
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                }
              }

              // Health Status Badge
              Rectangle {
                id: bootHealthBadge
                implicitHeight: 22
                implicitWidth: healthBadgeRow.implicitWidth + 12
                radius: 11
                property bool isHealthy: (root.activeBootData && root.activeBootData.healthStatus === "healthy")
                color: isHealthy ? Qt.rgba(0.06, 0.72, 0.51, 0.15) : Qt.rgba(0.96, 0.62, 0.04, 0.15)
                border.color: isHealthy ? "#10B981" : "#F59E0B"
                border.width: 1

                RowLayout {
                  id: healthBadgeRow
                  anchors.centerIn: parent
                  spacing: 4
                  Text {
                    textFormat: Text.PlainText
                    text: bootHealthBadge.isHealthy ? "●" : "▲"
                    font.pixelSize: 8
                    color: bootHealthBadge.isHealthy ? "#10B981" : "#F59E0B"
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: (root.activeBootData && root.activeBootData.healthLabel) || "Checking..."
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: bootHealthBadge.isHealthy ? "#10B981" : "#F59E0B"
                  }
                }
              }

              // Close Button
              Rectangle {
                implicitWidth: 26
                implicitHeight: 26
                radius: 6
                color: bootCloseHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent"
                MouseArea {
                  id: bootCloseHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (!root.isSyncingBoot) root.showBootModal = false
                  }
                }
                Text {
                  anchors.centerIn: parent
                  text: "󰅖"
                  font.pixelSize: 13
                  color: bootCloseHover.containsMouse ? Color.foreground : Color.muted
                }
              }
            }

            // Stat tiles grid (4 columns)
            RowLayout {
              Layout.fillWidth: true
              spacing: 8

              // Tile 1: ESP Storage
              Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52
                radius: 6
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
                border.color: (root.activeBootData && root.activeBootData.espWarning) ? "#EF4444" : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                ColumnLayout {
                  anchors.centerIn: parent
                  spacing: 2
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    textFormat: Text.PlainText
                    text: root.activeBootData ? (root.activeBootData.espUsedHuman + " / " + root.activeBootData.espSizeHuman) : "--"
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    color: (root.activeBootData && root.activeBootData.espWarning) ? "#EF4444" : Color.foreground
                  }
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    textFormat: Text.PlainText
                    text: root.activeBootData ? ("ESP " + root.activeBootData.espUsedPercent + "% used (" + root.activeBootData.limitUsagePercent + "% limit)") : "ESP Storage"
                    font.pixelSize: 9
                    color: Color.muted
                  }
                }
              }

              // Tile 2: Sync Daemon
              Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52
                radius: 6
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
                border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                ColumnLayout {
                  anchors.centerIn: parent
                  spacing: 2
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    textFormat: Text.PlainText
                    text: (root.activeBootData && root.activeBootData.daemonActive) ? "Active" : "Offline"
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    color: (root.activeBootData && root.activeBootData.daemonActive) ? "#10B981" : "#EF4444"
                  }
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "limine-snapper-sync"
                    font.pixelSize: 9
                    color: Color.muted
                  }
                }
              }

              // Tile 3: Verified Boot Entries
              Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52
                radius: 6
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
                border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                ColumnLayout {
                  anchors.centerIn: parent
                  spacing: 2
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    textFormat: Text.PlainText
                    text: root.activeBootData ? (String(root.activeBootData.totalEntries) + " Snapshots") : "--"
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    color: "#10B981"
                  }
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Limine Boot Menu"
                    font.pixelSize: 9
                    color: Color.muted
                  }
                }
              }

              // Tile 4: Last Sync
              Rectangle {
                Layout.fillWidth: true
                implicitHeight: 52
                radius: 6
                color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
                border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                ColumnLayout {
                  anchors.centerIn: parent
                  spacing: 2
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    textFormat: Text.PlainText
                    text: (root.activeBootData && root.activeBootData.lastSyncRelative) ? root.activeBootData.lastSyncRelative : "--"
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    color: Color.foreground
                  }
                  Text {
                    Layout.alignment: Qt.AlignHCenter
                    textFormat: Text.PlainText
                    text: (root.activeBootData && root.activeBootData.lastSyncTimestamp) ? root.activeBootData.lastSyncTimestamp : "Last Synced"
                    font.pixelSize: 9
                    color: Color.muted
                  }
                }
              }
            }

            // Entries section header
            Text {
              text: "Verified Bootable Snapshots in Limine Menu"
              font.pixelSize: 12
              font.weight: Font.Bold
              color: Color.foreground
            }

            // Table header
            Rectangle {
              Layout.fillWidth: true
              implicitHeight: 26
              radius: 4
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text { text: "ID"; font.pixelSize: 10; font.weight: Font.Bold; color: Color.muted; Layout.preferredWidth: 36 }
                Text { text: "Kernel & Release"; font.pixelSize: 10; font.weight: Font.Bold; color: Color.muted; Layout.preferredWidth: 150 }
                Text { text: "EFI Payload"; font.pixelSize: 10; font.weight: Font.Bold; color: Color.muted; Layout.preferredWidth: 140 }
                Text { text: "Snapshot Timestamp"; font.pixelSize: 10; font.weight: Font.Bold; color: Color.muted; Layout.fillWidth: true }
                Text { text: "Status"; font.pixelSize: 10; font.weight: Font.Bold; color: Color.muted; Layout.preferredWidth: 105; horizontalAlignment: Text.AlignRight }
              }
            }

            // List of verified Limine entries
            ScrollView {
              Layout.fillWidth: true
              implicitHeight: 180
              clip: true

              ListView {
                id: bootEntriesList
                anchors.fill: parent
                spacing: 4
                focus: true
                currentIndex: 0
                clip: true
                model: (root.activeBootData && root.activeBootData.entries) || []

                Keys.onUpPressed: function(event) {
                  if (bootEntriesList.currentIndex > 0) {
                    bootEntriesList.decrementCurrentIndex()
                    event.accepted = true
                  }
                }
                Keys.onDownPressed: function(event) {
                  if (bootEntriesList.currentIndex < bootEntriesList.count - 1) {
                    bootEntriesList.incrementCurrentIndex()
                    event.accepted = true
                  }
                }
                Keys.onEscapePressed: {
                  if (!root.isSyncingBoot) {
                    root.showBootModal = false
                    if (keyCatcher) keyCatcher.forceActiveFocus()
                  }
                }
                Keys.onReturnPressed: {
                  if (!root.isSyncingBoot) {
                    root.executeBootSync()
                  }
                }
                Keys.onEnterPressed: {
                  if (!root.isSyncingBoot) {
                    root.executeBootSync()
                  }
                }

                delegate: Rectangle {
                  width: bootEntriesList.width
                  implicitHeight: 34
                  radius: 5
                  property bool isCurrent: ListView.isCurrentItem && bootEntriesList.activeFocus
                  color: isCurrent
                    ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
                    : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, index % 2 === 0 ? 0.02 : 0.04)
                  border.color: isCurrent ? Color.accent : "transparent"
                  border.width: isCurrent ? 1.5 : 0

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                      bootEntriesList.currentIndex = index
                      bootEntriesList.forceActiveFocus()
                    }
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    Rectangle {
                      implicitHeight: 18
                      implicitWidth: 32
                      radius: 4
                      color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
                      Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: "#" + modelData.snapshotId
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: Color.accent
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.kernel + (modelData.kernelRelease ? (" (" + modelData.kernelRelease + ")") : "")
                      font.pixelSize: 11
                      color: Color.foreground
                      Layout.preferredWidth: 150
                      elide: Text.ElideRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.efiPayload || "EFI"
                      font.pixelSize: 11
                      font.family: "monospace"
                      color: Color.muted
                      Layout.preferredWidth: 140
                      elide: Text.ElideRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.timestamp || ""
                      font.pixelSize: 10
                      color: Color.muted
                      Layout.fillWidth: true
                    }

                    Rectangle {
                      implicitHeight: 18
                      implicitWidth: 95
                      radius: 9
                      color: Qt.rgba(0.06, 0.72, 0.51, 0.15)
                      border.color: Qt.rgba(0.06, 0.72, 0.51, 0.3)
                      border.width: 1

                      RowLayout {
                        anchors.centerIn: parent
                        spacing: 3
                        Text { text: "✓"; font.pixelSize: 9; color: "#10B981" }
                        Text { text: "Boot Ready"; font.pixelSize: 9; font.weight: Font.Medium; color: "#10B981" }
                      }
                    }
                  }
                }

                Item {
                  visible: !bootEntriesList.model || bootEntriesList.model.length === 0
                  width: bootEntriesList.width
                  height: 100
                  ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                      Layout.alignment: Qt.AlignHCenter
                      text: "󰄬"
                      font.pixelSize: 22
                      color: Color.muted
                    }
                    Text {
                      Layout.alignment: Qt.AlignHCenter
                      text: "No snapshot entries registered in Limine configuration."
                      font.pixelSize: 12
                      color: Color.muted
                    }
                  }
                }
              }
            }

            // Bottom action bar
            RowLayout {
              Layout.fillWidth: true
              spacing: 12

              Text {
                text: "󰋼 Limine boots directly into read-only btrfs snapshots to recover from kernel or driver breakage."
                font.pixelSize: 10
                color: Color.muted
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
              }

              Rectangle {
                implicitHeight: 32
                implicitWidth: bootCloseLayout.implicitWidth + 20
                radius: 6
                color: bootCloseBtnHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
                border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
                border.width: 1
                MouseArea {
                  id: bootCloseBtnHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (!root.isSyncingBoot) root.showBootModal = false
                  }
                }
                RowLayout {
                  id: bootCloseLayout
                  anchors.centerIn: parent
                  spacing: 6
                  Text {
                    text: "Close"
                    font.pixelSize: 11
                    color: Color.muted
                  }
                  Rectangle {
                    implicitHeight: 16
                    implicitWidth: bootEscTxt.implicitWidth + 6
                    radius: 3
                    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                    Text {
                      id: bootEscTxt
                      anchors.centerIn: parent
                      text: "Esc"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: Color.muted
                    }
                  }
                }
              }

              Rectangle {
                implicitHeight: 32
                implicitWidth: bootSubmitLayout.implicitWidth + 22
                radius: 6
                color: root.isSyncingBoot ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1) : "#10B981"
                opacity: root.isSyncingBoot ? 0.6 : 1.0

                MouseArea {
                  anchors.fill: parent
                  cursorShape: root.isSyncingBoot ? Qt.ArrowCursor : Qt.PointingHandCursor
                  onClicked: {
                    if (!root.isSyncingBoot) {
                      root.executeBootSync()
                    }
                  }
                }

                RowLayout {
                  id: bootSubmitLayout
                  anchors.centerIn: parent
                  spacing: 6
                  Text {
                    textFormat: Text.PlainText
                    text: root.isSyncingBoot ? "󰑐" : "󰌢"
                    font.pixelSize: 13
                    color: root.isSyncingBoot ? Color.muted : "#ffffff"
                    rotation: root.isSyncingBoot ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 400 } }
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: root.isSyncingBoot ? "Syncing Limine..." : "Sync Bootloader Now"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: root.isSyncingBoot ? Color.muted : "#ffffff"
                  }
                  Rectangle {
                    visible: !root.isSyncingBoot
                    implicitHeight: 16
                    implicitWidth: bootEnterTxt.implicitWidth + 6
                    radius: 3
                    color: Qt.rgba(0, 0, 0, 0.2)
                    Text {
                      id: bootEnterTxt
                      anchors.centerIn: parent
                      text: "↵ Enter"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: "#ffffff"
                    }
                  }
                  Rectangle {
                    visible: !root.isSyncingBoot
                    implicitHeight: 16
                    implicitWidth: bootKeySBadge.implicitWidth + 6
                    radius: 3
                    color: Qt.rgba(0, 0, 0, 0.2)
                    Text {
                      id: bootKeySBadge
                      anchors.centerIn: parent
                      text: "S"
                      font.pixelSize: 8
                      font.weight: Font.Bold
                      color: "#ffffff"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
