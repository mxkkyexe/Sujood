import QtQuick
import qs.Commons
import qs.Ui as Ui
import "."

Column {
    id: root
    width: parent.width
    spacing: Style.space(14)
    property bool previewArrival: false
    readonly property var prefs: PrayerService.prefs
    readonly property color foreground: Color.popups.text
    function changeOffset(name, delta) {
        var offsets = JSON.parse(JSON.stringify(prefs.offsets || {}))
        offsets[name] = Math.max(-60, Math.min(60, (offsets[name] || 0)+delta))
        PrayerService.update("offsets", offsets, true)
    }
    component Caption: Text {
        width: root.width
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
    }
    component SectionLabel: Text {
        color: root.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
    }
    SectionLabel { text: "Calculation" }
    SettingChoice {
        label: "Method"
        value: prefs.method
        options: [
            {value:"auto",label:"Automatic · regional method"},
            {value:2,label:"ISNA North America"}, {value:3,label:"Muslim World League"},
            {value:1,label:"Karachi"}, {value:4,label:"Umm al-Qura, Makkah"},
            {value:5,label:"Egyptian General Authority"}, {value:7,label:"University of Tehran"},
            {value:0,label:"Shia Ithna-Ashari"}, {value:8,label:"Gulf Region"},
            {value:9,label:"Kuwait"}, {value:10,label:"Qatar"}, {value:11,label:"Singapore"},
            {value:12,label:"France (UOIF)"}, {value:13,label:"Turkey (experimental)"},
            {value:14,label:"Russia"}, {value:15,label:"Moonsighting Committee"},
            {value:16,label:"Dubai (experimental)"}, {value:17,label:"Malaysia (JAKIM)"},
            {value:18,label:"Tunisia"}, {value:19,label:"Algeria"}, {value:20,label:"Indonesia (Kemenag)"},
            {value:21,label:"Morocco"}, {value:22,label:"Lisbon"}, {value:23,label:"Jordan"}
        ]
        onPicked: function(choice) { PrayerService.update("method", choice, true) }
    }
    Caption {
        text: PrayerService.data ? "Using " + PrayerService.data.method : "Calculations update after saving."
    }
    SettingChoice {
        label: "Asr convention"
        value: prefs.school
        options: [{value:0,label:"Standard"}, {value:1,label:"Hanafi"}]
        onPicked: function(choice) { PrayerService.update("school", choice, true) }
    }
    SettingChoice {
        label: "High-latitude adjustment"
        value: prefs.highLatitude
        options: [{value:3,label:"Angle based"}, {value:1,label:"Middle of the night"}, {value:2,label:"One seventh of the night"}]
        onPicked: function(choice) { PrayerService.update("highLatitude", choice, true) }
    }
    Caption { text: "Regional methods are starting points. Choose your local mosque’s method if its timetable differs." }
    SectionLabel { text: "Minute adjustments" }
    Caption { text: "Fine-tune each prayer to match your local timetable." }
    Repeater {
        model: ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
        Row {
            required property string modelData
            width: root.width
            spacing: Style.space(6)
            Text {
                width: root.width - Style.space(146)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
            }
            Ui.Button {
                width: Style.space(32); text: "−"; focusable: true
                foreground: root.foreground
                onClicked: root.changeOffset(modelData, -1)
            }
            Text {
                width: Style.space(58)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: {
                    var n = prefs.offsets ? prefs.offsets[modelData] : 0
                    return (n > 0 ? "+" : "") + n + " min"
                }
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
            }
            Ui.Button {
                width: Style.space(32); text: "+"; focusable: true
                foreground: root.foreground
                onClicked: root.changeOffset(modelData, 1)
            }
        }
    }
    SectionLabel { text: "Reminders & display" }
    Ui.Toggle {
        width: root.width; label: "Prayer alerts"; description: "Notify at prayer time"
        checked: !!prefs.alerts; foreground: root.foreground; titleSize: Style.font.bodySmall
        onClicked: PrayerService.update("alerts", !prefs.alerts, false)
    }
    Ui.Toggle {
        width: root.width; label: "Sound"; description: "Chime with the notification"
        visible: !!prefs.alerts; checked: !!prefs.sound; foreground: root.foreground; titleSize: Style.font.bodySmall
        onClicked: PrayerService.update("sound", !prefs.sound, false)
    }
    Ui.Toggle {
        width: root.width; label: "Bar countdown"; description: "Next prayer beside the mosque"
        checked: !!prefs.countdown; foreground: root.foreground; titleSize: Style.font.bodySmall
        onClicked: PrayerService.update("countdown", !prefs.countdown, false)
    }
    Ui.Toggle {
        width: root.width; label: "Show sunrise in bar"; description: "Countdown to sunrise after Fajr"
        checked: prefs.showSunrise === true; foreground: root.foreground; titleSize: Style.font.bodySmall
        onClicked: PrayerService.update("showSunrise", !prefs.showSunrise, false)
    }
    Ui.Toggle {
        width: root.width; label: "Countdown animation"; description: "Pulse through the progress fill; glow and breathe at prayer time"
        checked: !!prefs.animation; foreground: root.foreground; titleSize: Style.font.bodySmall
        onClicked: PrayerService.update("animation", !prefs.animation, false)
    }
    Ui.Toggle {
        width: root.width; label: "24-hour clock"
        checked: !!prefs.clock24; foreground: root.foreground; titleSize: Style.font.bodySmall
        onClicked: PrayerService.update("clock24", !prefs.clock24, false)
    }
    Caption { text: "The final 30 minutes fill the countdown with a soft moving pulse in your theme’s accent. At prayer time it shows “Now” for one minute." }
    Ui.Button {
        text: "Preview arrival animation"
        foreground: root.foreground; focusable: true
        onClicked: { root.previewArrival = true; previewTimer.restart() }
    }
    CountdownText {
        visible: root.previewArrival
        text: "Isha | Now"
        foreground: root.foreground; accent: Color.accent
        fontFamily: Style.font.family; fontSize: Style.font.body
        arrival: root.previewArrival
    }
    Timer { id: previewTimer; interval: 8000; onTriggered: root.previewArrival = false }
    Caption { text: "Times: Aladhan · City search: Open-Meteo / GeoNames" }
}
