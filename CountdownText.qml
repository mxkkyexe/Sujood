import QtQuick

Item {
    id: root
    property string text: ""
    property color foreground: "white"
    property color accent: "cyan"
    property string fontFamily: "sans-serif"
    property real fontSize: 14
    property real progress: 0
    property bool arrival: false
    property bool animate: true
    property real sweep: 0
    readonly property real bandWidth: Math.max(24, width * 0.36)
    readonly property real bandX: -bandWidth + sweep * (width + bandWidth)
    implicitWidth: base.implicitWidth
    implicitHeight: base.implicitHeight
    clip: true

    Text {
        id: base
        text: root.text
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        renderType: Text.NativeRendering
    }
    Item {
        visible: !root.arrival || !root.animate
        width: root.width * (root.arrival ? 1 : root.progress)
        height: root.height
        clip: true
        Text {
            text: root.text
            textFormat: Text.PlainText
            color: root.accent
            font: base.font
            renderType: Text.NativeRendering
        }
        Behavior on width { enabled: !root.arrival; NumberAnimation { duration: 950; easing.type: Easing.Linear } }
    }
    // Soft moving band, implemented with clipped text strips. No GPU-specific shader.
    Repeater {
        model: root.arrival && root.animate ? 16 : 0
        Item {
            required property int index
            x: root.bandX + index * root.bandWidth / 16
            width: root.bandWidth / 16
            height: root.height
            clip: true
            opacity: Math.sin(Math.PI * (index + 0.5) / 16)
            Text {
                x: -parent.x
                text: root.text
                textFormat: Text.PlainText
                color: root.accent
                font: base.font
                renderType: Text.NativeRendering
            }
        }
    }
    NumberAnimation on sweep {
        from: 0; to: 1; duration: 2200; loops: Animation.Infinite
        running: root.visible && root.arrival && root.animate
    }
    onArrivalChanged: if (!arrival) sweep = 0
}
