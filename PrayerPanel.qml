import QtQuick
import QtQuick.Window
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "."
import "Model.js" as Model

Item {
    id: root
    property bool settingsOpen: false
    property bool editingLocation: false
    property int locationIndex: 0
    readonly property var service: PrayerService
    signal closeRequested()
    function close() { closeRequested() }
    function scrollSettingsTo(position) {
        scroll.cancelFlick()
        scroll.contentY = Math.max(0, Math.min(position, Math.max(0, scroll.contentHeight - scroll.height)))
    }
    function scrollSettingsBy(amount) { scrollSettingsTo(scroll.contentY + amount) }
    function keepFocusedControlVisible() {
        if (!root.settingsOpen || !root.Window.window) return
        var item = root.Window.window.activeFocusItem
        var ancestor = item
        while (ancestor && ancestor !== settingsView) ancestor = ancestor.parent
        if (!ancestor) return
        var top = item.mapToItem(settingsView, 0, 0).y
        var bottom = top + item.height
        if (top < scroll.contentY) scrollSettingsTo(top - Style.space(6))
        else if (bottom > scroll.contentY + scroll.height)
            scrollSettingsTo(bottom - scroll.height + Style.space(6))
    }
    function startLocationEdit() {
        if (!service.ready) return
        editingLocation = true
        locationIndex = 0
        service.search("")
        Qt.callLater(function() {
            if (!root.editingLocation) return
            locationField.text = service.prefs.location ? service.prefs.location.name : ""
            locationField.selectAll()
            locationField.forceActiveFocus()
        })
    }
    function cancelLocationEdit() {
        editingLocation = false
        service.search("")
        locationField.text = ""
        locationButton.forceActiveFocus()
    }
    function chooseLocation(location) {
        if (!location) return
        service.update("location", location, true)
        cancelLocationEdit()
    }
    function reset() {
        settingsOpen = false
        cancelLocationEdit()
    }
    onLocationIndexChanged: Qt.callLater(function() {
        var row = locationRepeater.itemAt(root.locationIndex)
        if (!row) return
        if (row.y < locationScroll.contentY) locationScroll.contentY = row.y
        else if (row.y + row.height > locationScroll.contentY + locationScroll.height)
            locationScroll.contentY = row.y + row.height - locationScroll.height
    })
    onSettingsOpenChanged: {
        if (settingsOpen && editingLocation) cancelLocationEdit()
        // Keep navigation on the newly visible page, rather than its hidden button.
        Qt.callLater(function() { root.forceActiveFocus() })
    }
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() { Qt.callLater(root.keepFocusedControlVisible) }
    }
    Connections {
        target: root.service
        function onSearchResultsChanged() { root.locationIndex = 0 }
    }
    implicitHeight: settingsOpen ? Style.space(520) : mainColumn.implicitHeight
    focus: true
    Keys.onEscapePressed: {
        if (root.editingLocation) root.cancelLocationEdit()
        else if (root.settingsOpen) root.settingsOpen = false
        else root.close()
    }
    Keys.onPressed: function(event) {
        event.accepted = false
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
        if (root.editingLocation) return
        if (event.key === Qt.Key_R) {
            root.service.sync(true)
            event.accepted = true
            return
        }
        if (!root.settingsOpen) {
            if (event.key === Qt.Key_S) {
                root.settingsOpen = true
                event.accepted = true
            } else if (event.key === Qt.Key_C) {
                root.startLocationEdit()
                event.accepted = true
            }
            return
        }
        switch (event.key) {
        case Qt.Key_J:
        case Qt.Key_Down:
            root.scrollSettingsBy(Style.space(40)); break
        case Qt.Key_K:
        case Qt.Key_Up:
            root.scrollSettingsBy(-Style.space(40)); break
        case Qt.Key_PageDown:
            root.scrollSettingsBy(scroll.height * 0.8); break
        case Qt.Key_PageUp:
            root.scrollSettingsBy(-scroll.height * 0.8); break
        case Qt.Key_Home:
            root.scrollSettingsTo(0); break
        case Qt.Key_End:
            root.scrollSettingsTo(scroll.contentHeight); break
        default:
            return
        }
        event.accepted = true
    }
    Column {
        id: mainColumn
        width: parent.width
        spacing: Style.space(10)
        visible: !root.settingsOpen
        Row {
            width: parent.width
            spacing: Style.space(8)
            Column {
                width: parent.width - gear.width - parent.spacing
                spacing: Style.space(4)
                Button {
                    id: locationButton
                    objectName: "locationButton"
                    x: -Style.space(6)
                    width: parent.width + Style.space(6)
                    implicitHeight: cityName.implicitHeight + Style.space(8)
                    visible: !root.editingLocation
                    enabled: service.ready
                    focusable: true
                    foreground: Color.popups.text
                    tooltipText: "Change city (C)"
                    Accessible.name: "Change city"
                    onClicked: root.startLocationEdit()
                    Text {
                        id: cityName
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(6)
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - editCue.width - Style.space(16)
                        text: service.prefs.location ? service.prefs.location.name : "Choose city"
                        textFormat: Text.PlainText
                        color: locationButton.hot || locationButton.activeFocus ? Style.hoverStateColor(Color.popups.text, Color.accent) : Color.popups.text
                        font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true
                        elide: Text.ElideRight
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Text {
                        id: editCue
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(5)
                        anchors.verticalCenter: parent.verticalCenter
                        text: ""
                        color: locationButton.hot || locationButton.activeFocus ? Style.hoverStateColor(Color.popups.text, Color.accent) : Color.muted
                        opacity: locationButton.hot || locationButton.activeFocus ? 1 : 0.6
                        font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
                    }
                }
                Row {
                    width: parent.width
                    visible: root.editingLocation
                    spacing: Style.space(4)
                    TextField {
                        id: locationField
                        objectName: "locationField"
                        width: parent.width - cancelCity.width - parent.spacing
                        placeholderText: "Search city…"
                        foreground: Color.popups.text
                        Accessible.name: "Search for a city"
                        onTextEdited: service.search(text)
                        Keys.onEscapePressed: root.cancelLocationEdit()
                        Keys.onDownPressed: {
                            root.locationIndex = Math.min(root.locationIndex + 1, service.searchResults.length - 1)
                        }
                        Keys.onUpPressed: root.locationIndex = Math.max(0, root.locationIndex - 1)
                        onAccepted: root.chooseLocation(service.searchResults[root.locationIndex])
                    }
                    Button {
                        id: cancelCity
                        iconText: ""
                        tooltipText: "Cancel city change"
                        foreground: Color.popups.text
                        focusable: true
                        onClicked: root.cancelLocationEdit()
                    }
                }
                Text {
                    text: service.day ? service.day.label : "Prayer times"
                    color: Color.muted
                    font.family: Style.font.family; font.pixelSize: Style.font.caption
                }
            }
            Button {
                id: gear
                iconText: ""
                tooltipText: "Sujood settings (S)"
                foreground: Color.popups.text
                focusable: true
                onClicked: root.settingsOpen = true
            }
        }
        Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.editingLocation
            Text {
                width: parent.width
                text: service.searching ? "Searching…" : (service.searchError || "Search a city, then select its region below.")
                color: service.searchError ? Color.urgent : Color.muted
                font.family: Style.font.family; font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
            }
            Flickable {
                id: locationScroll
                width: parent.width
                height: Math.min(locationResults.implicitHeight, Style.space(200))
                contentHeight: locationResults.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: locationResults
                    width: parent.width - Style.space(8)
                    spacing: Style.space(2)
                    Repeater {
                        id: locationRepeater
                        model: root.editingLocation ? service.searchResults : []
                        Button {
                            required property var modelData
                            required property int index
                            width: locationResults.width
                            implicitHeight: resultLabels.implicitHeight + Style.space(12)
                            selected: index === root.locationIndex
                            foreground: Color.popups.text
                            focusable: true
                            onHovered: function(isHovered) { if (isHovered) root.locationIndex = index }
                            onClicked: root.chooseLocation(modelData)
                            Column {
                                id: resultLabels
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.margins: Style.space(8)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Style.space(3)
                                Text {
                                    width: parent.width
                                    text: modelData.name
                                    color: index === root.locationIndex ? Style.selectedStateColor(Color.popups.text, Color.accent) : Color.popups.text
                                    font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
                                    font.bold: true
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                }
                                Text {
                                    width: parent.width
                                    text: modelData.region || modelData.timezone
                                    color: Color.muted
                                    font.family: Style.font.family; font.pixelSize: Style.font.caption
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                }
                            }
                        }
                    }
                }
                QQC.ScrollBar.vertical: QQC.ScrollBar {
                    contentItem: Rectangle { implicitWidth: Style.space(3); radius: width/2; color: Color.accent; opacity: 0.6 }
                }
            }
        }
        Text {
            width: parent.width
            visible: !!service.day
            text: service.day ? service.day.hijri : ""
            textFormat: Text.PlainText
            color: Color.muted
            font.family: Style.font.family; font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
        }
        Rectangle { width: parent.width; height: Style.spacing.hairline; color: Color.popups.text; opacity: 0.12 }
        Repeater {
            model: service.day ? service.day.rows : []
            Item {
                id: prayerRow
                required property var modelData
                readonly property var emphasis: Model.rowState(modelData, service.status, service.day)
                readonly property bool highlighted: emphasis.highlighted
                readonly property bool sunrise: modelData.name === "Sunrise"
                width: mainColumn.width
                height: Style.space(34)
                Rectangle {
                    anchors.fill: parent
                    visible: prayerRow.highlighted
                    radius: Style.cornerRadius
                    color: Style.selectedFillFor(Color.popups.text, Color.accent)
                    border.width: Style.spacing.hairline
                    border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.45)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Style.space(3)
                        height: parent.height - Style.space(12)
                        radius: Math.min(Style.cornerRadius, width / 2)
                        color: Color.accent
                    }
                }
                Text {
                    id: prayerName
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    color: prayerRow.sunrise && !prayerRow.highlighted ? Color.muted : Color.popups.text
                    font.family: Style.font.family; font.pixelSize: Style.font.body
                    font.bold: prayerRow.highlighted
                }
                Rectangle {
                    visible: prayerRow.highlighted
                    anchors.left: prayerName.right
                    anchors.leftMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(badgeLabel.implicitWidth + Style.space(8),
                                    Math.max(0, prayerTime.x - prayerName.x - prayerName.width - Style.space(16)))
                    height: badgeLabel.implicitHeight + Style.space(6)
                    radius: Style.cornerRadius
                    color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2)
                    Text {
                        id: badgeLabel
                        anchors.centerIn: parent
                        width: parent.width - Style.space(8)
                        horizontalAlignment: Text.AlignHCenter
                        text: prayerRow.emphasis.badge
                        color: Color.popups.text
                        font.family: Style.font.family; font.pixelSize: Style.font.caption
                        font.bold: true
                        elide: Text.ElideRight
                    }
                }
                Text {
                    id: prayerTime
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.timeLabel(prayerRow.emphasis.time, service.prefs.clock24)
                    color: prayerRow.sunrise && !prayerRow.highlighted ? Color.muted : Color.popups.text
                    font.family: Style.font.family; font.pixelSize: Style.font.body
                    font.bold: prayerRow.highlighted
                }
            }
        }
        Text {
            width: parent.width
            visible: service.error !== "" || !service.day
            text: service.error || (!service.prefs.location ? "Click “Choose city” above to set your location." : (service.busy ? "Loading prayer times…" : "Today’s timetable is unavailable. Right-click the icon to retry."))
            textFormat: Text.PlainText
            color: service.error ? Color.urgent : Color.muted
            font.family: Style.font.family; font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
        }
        Text {
            width: parent.width
            text: "C City · S Settings · R Refresh · Esc Close"
            color: Color.muted
            font.family: Style.font.family; font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
        }
    }
    Column {
        anchors.fill: parent
        spacing: Style.space(10)
        visible: root.settingsOpen
        Row {
            id: settingsHeader
            width: parent.width
            spacing: Style.space(8)
            Button {
                iconText: ""; tooltipText: "Back to prayer times (Esc)"; focusable: true
                foreground: Color.popups.text
                onClicked: root.settingsOpen = false
            }
            Text {
                text: "Sujood settings"; color: Color.popups.text
                anchors.verticalCenter: parent.verticalCenter
                font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true
            }
        }
        Flickable {
            id: scroll
            objectName: "settingsScroll"
            width: parent.width
            height: Math.max(0, parent.height - settingsHeader.height - settingsHelp.implicitHeight - parent.spacing * 2)
            clip: true
            contentHeight: settingsView.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            SettingsView { id: settingsView; width: scroll.width - Style.space(10); enabled: service.ready }
            QQC.ScrollBar.vertical: QQC.ScrollBar {
                policy: QQC.ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: Style.space(3); radius: width/2; color: Color.accent; opacity: 0.6 }
            }
        }
        Text {
            id: settingsHelp
            width: parent.width
            text: "J/K or ↑/↓ Scroll · PgUp/PgDn Page\nTab Controls · Enter/Space Select · R Refresh · Esc Back"
            color: Color.muted
            font.family: Style.font.family; font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
        }
    }
}
