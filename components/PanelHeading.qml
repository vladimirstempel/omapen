import QtQuick
import qs.Commons

Item {
  id: root

  property var bar
  property string sourceKind: ""

  readonly property string badge: ({
    selection: "SELECTION",
    manual: "YOUR TEXT"
  })[root.sourceKind] || ""

  implicitHeight: title.implicitHeight

  Text {
    id: title
    text: "OmaPen"
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.title
    font.bold: true
    anchors.left: parent.left
  }

  Text {
    text: root.badge
    color: Qt.darker(root.bar.foreground, 1.6)
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.2
    anchors.right: parent.right
    anchors.verticalCenter: title.verticalCenter
  }
}
