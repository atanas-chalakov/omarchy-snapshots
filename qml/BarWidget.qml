import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "ac.snapshots"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰆼"
    horizontalMargin: 7.5
    onPressed: function(btn) {
      if (!root.bar) return
      if (btn === Qt.RightButton) {
        root.bar.run("omarchy-shell shell toggle ac.snapshots '{\"action\":\"create\"}'")
      } else {
        root.bar.run("omarchy-shell shell toggle ac.snapshots")
      }
    }
  }
}
