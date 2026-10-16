import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import qs.Ui as Ui
import "."
import "Model.js" as Model

Ui.BarWidget {
    id: root
    moduleName: "mxkkyexe.sujood"
    property bool popupOpen: false
    readonly property bool opened: popupOpen
    function open() { popupOpen = true }
    readonly property var service: PrayerService
    readonly property bool countdownVisible: service.prefs.countdown !== false && !vertical
    readonly property real openPanelIndicatorWidth: countdownVisible ? content.implicitWidth : 0
    readonly property string phaseName: service.status.prayer ? service.status.prayer.name : "Fajr"
    function close() { popupOpen = false; panelContent.reset() }
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        labelVisible: false
        hasVisualContent: true
        fixedWidth: root.vertical ? -1 : (root.countdownVisible ? content.implicitWidth + scaledHorizontalMargin*2 : Style.bar.iconSlot)
        fixedHeight: root.vertical ? Style.bar.iconSlot : -1
        tooltipText: (service.prefs.location ? service.prefs.location.name + " · " : "") + service.label
                     + (service.error ? "\n" + service.error : "")
        onPressed: function(b) {
            if (b === Qt.RightButton || b === Qt.MiddleButton) service.sync(true)
            else if (root.popupOpen) root.close()
            else root.open()
        }
        Row {
            id: content
            anchors.centerIn: parent
            spacing: Style.space(6)
            PrayerIcon {
                anchors.verticalCenter: parent.verticalCenter
                // Compensate for the SVG's lower visual center and the text's font metrics.
                anchors.verticalCenterOffset: -Style.space(2)
                // Give the detailed silhouette room while keeping the bar's shared center.
                width: Math.round(Style.bar.iconCanvas * 1.15)
                height: Math.round(Style.bar.iconCanvas * 1.15)
                prayer: root.phaseName
                foreground: button.foreground
                accent: Color.accent
            }
            CountdownText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.countdownVisible
                text: service.label
                foreground: button.foreground
                accent: Color.accent
                fontFamily: button.fontFamily
                fontSize: Style.font.body
                progress: service.status.progress
                arrival: service.status.phase === "arrival"
                animate: service.prefs.animation !== false && (!root.bar || root.bar.foregroundAnimationEnabled)
            }
        }
    }
    KeyboardPanel {
        id: popup
        owner: root
        anchorItem: button
        bar: root.bar
        open: root.popupOpen
        focusTarget: panelContent
        contentWidth: fittedContentWidth(Style.space(330))
        contentHeight: fittedContentHeight(panelContent.implicitHeight)
        PrayerPanel {
            id: panelContent
            anchors.fill: parent
            onCloseRequested: root.close()
        }
    }
}
