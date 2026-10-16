pragma ComponentBehavior: Bound
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
    property real arrivalGlow: 0
    readonly property bool pulsing: animate && !arrival && progress > 0
    readonly property color arrivalColor: Qt.tint(accent,
        Qt.rgba(foreground.r, foreground.g, foreground.b, arrivalGlow * 0.85))
    readonly property real bandWidth: Math.max(24, width * 0.36)
    readonly property real bandX: -bandWidth + sweep * (pulseClip.width + bandWidth)
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
        id: fill
        width: root.width * (root.arrival ? 1 : root.progress)
        height: root.height
        clip: true
        Text {
            text: root.text
            textFormat: Text.PlainText
            color: root.arrival && root.animate ? root.arrivalColor : root.accent
            font: base.font
            renderType: Text.NativeRendering
        }
        Behavior on width { enabled: !root.arrival; NumberAnimation { duration: 950; easing.type: Easing.Linear } }
    }
    // Soft moving band, implemented with clipped text strips. No GPU-specific shader.
    Item {
        id: pulseClip
        width: fill.width
        height: root.height
        clip: true
        visible: root.pulsing
        Repeater {
            model: root.pulsing ? 32 : 0
            Item {
                required property int index
                x: root.bandX + index * root.bandWidth / 32
                width: root.bandWidth / 32
                height: root.height
                clip: true
                opacity: Math.pow(Math.sin(Math.PI * (index + 0.5) / 32), 2)
                Text {
                    x: -parent.x
                    text: root.text
                    textFormat: Text.PlainText
                    color: Qt.tint(root.accent,
                        Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.7))
                    font: base.font
                    renderType: Text.NativeRendering
                }
            }
        }
    }
    NumberAnimation on sweep {
        from: 0; to: 1; duration: 2200; loops: Animation.Infinite
        running: root.visible && root.pulsing
    }
    onPulsingChanged: if (!pulsing) sweep = 0
    SequentialAnimation {
        running: root.visible && root.arrival && root.animate
        onRunningChanged: if (!running) root.arrivalGlow = 0
        NumberAnimation {
            target: root; property: "arrivalGlow"
            from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root; property: "arrivalGlow"
            to: 0; duration: 1000; easing.type: Easing.InOutSine
        }
        SequentialAnimation {
            loops: Animation.Infinite
            NumberAnimation {
                target: root; property: "arrivalGlow"
                to: 0.7; duration: 1500; easing.type: Easing.InOutSine
            }
            NumberAnimation {
                target: root; property: "arrivalGlow"
                to: 0; duration: 1500; easing.type: Easing.InOutSine
            }
        }
    }
}
