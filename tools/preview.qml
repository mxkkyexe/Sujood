// Render actual Sujood components with isolated demonstration data.
import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import "plugin" as Sujood
ShellRoot {
    id: preview
    property string mode: Quickshell.env("SUJOOD_PREVIEW_MODE")
    property string output: Quickshell.env("SUJOOD_PREVIEW_DIR")
    property int frameNumber: 0
    function find(item, name) {
        if (item.objectName === name) return item
        var children = item.children || []
        for (var i=0; i<children.length; i++) {
            var result=find(children[i],name)
            if (result) return result
        }
        return null
    }
    function configure() {
        Sujood.PrayerService.clock.stop()
        Sujood.PrayerService.now = Date.parse("2026-10-15T15:13:00+03:00")
        Color.shellValues = ({})
        var light = mode === "light"
        Color.background = light ? "#eff1f5" : "#2e3440"
        Color.foreground = light ? "#4c4f69" : "#d8dee9"
        Color.accent = light ? "#1e66f5" : "#81a1c1"
        Color.muted = light ? "#6c6f85" : "#9aa7bd"
        Color.urgent = light ? "#d20f39" : "#bf616a"
        Style.fontBaseSize = 14
        Style.fontOverrides = ({})
        Style.barOverrides = ({})
        Style.styleOverrides = ({})
        Style.cornerRadius = 0
        Style.gapsOut = 6
        if (mode === "city") {
            cityPanel.startLocationEdit()
            Qt.callLater(function() {
                find(cityPanel,"locationField").text = "Mecca"
                Sujood.PrayerService.searchResults = [
                    {name:"Mecca",region:"Mecca Region, Saudi Arabia",timezone:"Asia/Riyadh"},
                    {name:"Mecca",region:"California, United States",timezone:"America/Los_Angeles"},
                    {name:"Mecca",region:"Indiana, United States",timezone:"America/Indiana/Indianapolis"}
                ]
            })
        }
    }
    Window {
        id: window
        visible: true
        width: preview.mode === "arrival" ? 600 : (preview.mode === "city" ? 440 : 1020)
        height: preview.mode === "arrival" ? 140 : (preview.mode === "city" ? cityPanel.implicitHeight+40 : 830)
        color: Color.background
        Rectangle {
            id: capture
            anchors.fill: parent
            color: Color.background
            Item {
                anchors.fill: parent
                visible: preview.mode === "dark" || preview.mode === "light"
                Row {
                    x:32; y:23; spacing:14
                    Sujood.PrayerIcon {width:44; height:44; prayer:"Isha"; foreground:Color.foreground;accent:Color.accent}
                    Text {text:"Sujood";color:Color.foreground;font.family:Style.font.family;font.pixelSize:34;font.bold:true}
                }
                Text {x:32;y:80;text:"Prayer times, right at home in Omarchy.";color:Color.muted;font.family:Style.font.family;font.pixelSize:15}
                Rectangle {
                    x:32;y:119;width:956;height:54
                    color:Qt.rgba(Color.foreground.r,Color.foreground.g,Color.foreground.b,0.05)
                    border.color:Qt.rgba(Color.foreground.r,Color.foreground.g,Color.foreground.b,0.12)
                    Row {
                        anchors.verticalCenter:parent.verticalCenter
                        x:18;spacing:54
                        Row {
                            spacing:7
                            Sujood.PrayerIcon {anchors.verticalCenter:parent.verticalCenter;anchors.verticalCenterOffset:-2;width:22;height:22;prayer:"Asr";foreground:Color.foreground;accent:Color.accent}
                            Sujood.CountdownText {anchors.verticalCenter:parent.verticalCenter;text:"Asr | 1h 4m";fontFamily:Style.font.family;fontSize:14;foreground:Color.foreground;accent:Color.accent}
                        }
                        Row {
                            spacing:7
                            Sujood.PrayerIcon {anchors.verticalCenter:parent.verticalCenter;anchors.verticalCenterOffset:-2;width:22;height:22;prayer:"Asr";foreground:Color.foreground;accent:Color.accent}
                            Sujood.CountdownText {anchors.verticalCenter:parent.verticalCenter;text:"Asr | 15m";progress:0.5;fontFamily:Style.font.family;fontSize:14;foreground:Color.foreground;accent:Color.accent}
                        }
                        Row {
                            spacing:7
                            Sujood.PrayerIcon {anchors.verticalCenter:parent.verticalCenter;anchors.verticalCenterOffset:-2;width:22;height:22;prayer:"Isha";foreground:Color.foreground;accent:Color.accent}
                            Sujood.CountdownText {anchors.verticalCenter:parent.verticalCenter;text:"Isha | Now";progress:1;arrival:true;animate:false;fontFamily:Style.font.family;fontSize:14;foreground:Color.foreground;accent:Color.accent}
                        }
                    }
                }
                Rectangle {
                    x:32;y:200;width:436;height:mainPanel.implicitHeight+40
                    color:Color.popups.background;border.color:Color.popups.border
                    Sujood.PrayerPanel {id:mainPanel;x:20;y:20;width:396;height:implicitHeight}
                }
                Rectangle {
                    x:496;y:200;width:492;height:588
                    color:Color.popups.background;border.color:Color.popups.border
                    Sujood.PrayerPanel {x:20;y:20;width:452;height:548;settingsOpen:true}
                }
                Row {
                    x:40;y:735;spacing:24
                    Repeater {
                        model:["Fajr","Dhuhr","Asr","Maghrib","Isha"]
                        Column {
                            required property string modelData
                            width:60;spacing:6
                            Sujood.PrayerIcon {anchors.horizontalCenter:parent.horizontalCenter;width:34;height:32;prayer:modelData;foreground:Color.foreground;accent:Color.accent}
                            Text {anchors.horizontalCenter:parent.horizontalCenter;text:modelData;color:Color.muted;font.family:Style.font.family;font.pixelSize:11}
                        }
                    }
                }
                Text {x:32;y:808;text:"Native components · Sample timetable · " + (preview.mode === "light" ? "Light palette" : "Dark palette");color:Color.muted;font.family:Style.font.family;font.pixelSize:11}
            }
            Item {
                anchors.fill:parent
                visible:preview.mode === "city"
                Sujood.PrayerPanel {id:cityPanel;x:20;y:20;width:400;height:implicitHeight}
            }
            Item {
                anchors.fill:parent
                visible:preview.mode === "arrival"
                Text {x:24;y:20;text:"At prayer time · A glow, then a slow breath.";color:Color.muted;font.family:Style.font.family;font.pixelSize:14}
                Row {
                    x:24;y:62;spacing:16
                    Sujood.PrayerIcon {anchors.verticalCenter:parent.verticalCenter;anchors.verticalCenterOffset:-2;width:38;height:36;prayer:"Asr";foreground:Color.accent;accent:Color.accent}
                    Sujood.CountdownText {id:arrival;anchors.verticalCenter:parent.verticalCenter;text:"Asr | Now";arrival:preview.mode === "arrival";fontFamily:Style.font.family;fontSize:30;foreground:Color.foreground;accent:Color.accent}
                }
            }
        }
        Timer {
            interval:100;running:true;repeat:true
            onTriggered: {
                if (!Sujood.PrayerService.ready || Sujood.PrayerService.busy) return
                stop()
                preview.configure()
                captureDelay.start()
            }
        }
        Timer {
            id:captureDelay
            interval:150
            onTriggered: {
                if (preview.mode === "arrival") animationFrames.start()
                else capture.grabToImage(function(result) {
                    result.saveToFile(preview.output + "/" + preview.mode + ".png")
                    Qt.quit()
                })
            }
        }
        Timer {
            id:animationFrames
            interval:80;repeat:true
            onTriggered: {
                var n=preview.frameNumber++
                capture.grabToImage(function(result) {
                    var number=("000"+n).slice(-3)
                    result.saveToFile(preview.output + "/frame-"+number+".png")
                    if(n===54) Qt.quit()
                })
                if(n===54)stop()
            }
        }
        Timer {interval:12000;running:true;onTriggered:Qt.quit()}
    }
}
