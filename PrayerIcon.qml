import QtQuick
import "Icons.js" as Icons
Image {
    id: root
    property string prayer: "Fajr"
    property color foreground: "white"
    property color accent: "cyan"
    source: Icons.source(prayer, foreground, accent)
    sourceSize.width: Math.ceil(width * 2)
    sourceSize.height: Math.ceil(height * 2)
    fillMode: Image.PreserveAspectFit
    smooth: true
    cache: false
}
