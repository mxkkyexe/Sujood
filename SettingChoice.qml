import QtQuick
import qs.Commons
import qs.Ui as Ui

Column {
    id: root
    property string label: ""
    property var value
    property var options: []
    property bool expanded: false
    property color foreground: Color.popups.text
    signal picked(var choice)
    width: parent ? parent.width : 300
    spacing: Style.space(4)
    Text {
        text: root.label
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
    }
    Ui.Button {
        width: root.width
        text: {
            for (var i=0; i<root.options.length; i++)
                if (String(root.options[i].value) === String(root.value)) return root.options[i].label
            return "Choose…"
        }
        iconText: root.expanded ? "" : ""
        leftAlign: true
        fontSize: Style.font.bodySmall
        foreground: root.foreground
        bordered: true
        focusable: true
        onClicked: root.expanded = !root.expanded
    }
    Column {
        width: root.width
        visible: root.expanded
        spacing: Style.space(2)
        Repeater {
            model: root.expanded ? root.options : []
            Ui.Button {
                required property var modelData
                width: root.width
                text: modelData.label
                selected: String(modelData.value) === String(root.value)
                leftAlign: true
                foreground: root.foreground
                fontSize: Style.font.bodySmall
                focusable: true
                onClicked: { root.expanded = false; root.picked(modelData.value) }
            }
        }
    }
}
