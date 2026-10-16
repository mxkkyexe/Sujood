import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs.Commons
import "plugin" as Prayer
ShellRoot {
    Window {
        id: win
        visible: true
        width: 430; height: 680
        color: Color.popups.background
        Prayer.PrayerPanel {
            id: panel
            x:20; y:20; width:390; height:600
            property int closes: 0
            onCloseRequested: closes++
        }
    }
    TestCase {
        name: "PrayerKeyboard"
        when: win.visible
        function find(item,name) {
            if(item.objectName===name)return item
            var kids=item.children||[]
            for(var i=0;i<kids.length;i++) {
                var result=find(kids[i],name)
                if(result)return result
            }
            return null
        }
        function checkRefreshShortcut() {
            // Hold refreshes in the service queue so this test never needs the network.
            var service=Prayer.PrayerService
            compare(service.busy,false)
            service.ready=false
            try {
                service.queued=false
                service.forceQueued=false
                keyClick(Qt.Key_R,Qt.ControlModifier)
                compare(service.queued,false,"Ctrl+R does not trigger the plain R shortcut")
                keyClick(Qt.Key_R)
                compare(service.queued,true,"R requests a refresh")
                compare(service.forceQueued,true,"R forces cached months to be fetched again")
            } finally {
                service.queued=false
                service.forceQueued=false
                service.ready=true
            }
        }
        function test_panel_shortcuts() {
            tryVerify(function() {return Prayer.PrayerService.ready},2000)
            tryVerify(function() {return !Prayer.PrayerService.busy},2000)
            compare(Prayer.PrayerService.error, "", "Real stdin sync succeeds")
            compare(Prayer.PrayerService.worker.command.length, 4)
            compare(Prayer.PrayerService.worker.command[3], "--stdin", "Location payload stays out of argv")
            win.requestActivate()
            panel.forceActiveFocus()
            wait(30)
            checkRefreshShortcut()
            keyClick(Qt.Key_S)
            wait(30)
            compare(panel.settingsOpen,true)
            checkRefreshShortcut()
            var scroll=find(panel,"settingsScroll")
            verify(scroll.contentHeight>scroll.height)
            keyClick(Qt.Key_J);verify(scroll.contentY>0)
            keyClick(Qt.Key_K);compare(scroll.contentY,0)
            keyClick(Qt.Key_Down);verify(scroll.contentY>0)
            keyClick(Qt.Key_Up);compare(scroll.contentY,0)
            keyClick(Qt.Key_PageDown);verify(scroll.contentY>40)
            keyClick(Qt.Key_PageUp);compare(scroll.contentY,0)
            keyClick(Qt.Key_End);compare(scroll.contentY,scroll.contentHeight-scroll.height)
            keyClick(Qt.Key_Home);compare(scroll.contentY,0)
            // Native Tab traversal must keep controls visible without changing settings.
            var scrolledForFocus=false
            for(var i=0;i<22;i++) {
                keyClick(Qt.Key_Tab);wait(10)
                if(scroll.contentY>0)scrolledForFocus=true
            }
            verify(scrolledForFocus,"Tab automatically scrolls focused settings controls into view")
            keyClick(Qt.Key_Escape);wait(30)
            compare(panel.settingsOpen,false)
            compare(panel.closes,0)
            keyClick(Qt.Key_C);wait(30)
            compare(panel.editingLocation,true)
            var field=find(panel,"locationField")
            verify(field.activeFocus)
            keyClick(Qt.Key_S)
            compare(panel.settingsOpen,false)
            verify(field.text.toLowerCase().indexOf('s')!==-1,"S types in the city field")
            Prayer.PrayerService.ready=false
            try {
                keyClick(Qt.Key_R)
                verify(field.text.toLowerCase().indexOf('r')!==-1,"R types in the city field")
                compare(Prayer.PrayerService.queued,false,"City typing does not request a refresh")
            } finally {
                Prayer.PrayerService.ready=true
            }
            keyClick(Qt.Key_Escape);wait(30)
            compare(panel.editingLocation,false)
            compare(panel.closes,0)
            keyClick(Qt.Key_Escape)
            compare(panel.closes,1)
            console.log("Keyboard checks passed: refresh, navigation, scroll bounds, Tab visibility, city typing, Escape")

        }
    }
    Timer {interval:8000;running:true;onTriggered:Qt.quit()}
}
