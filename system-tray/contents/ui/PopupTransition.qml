/*
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick

import org.kde.kirigami as Kirigami

// Windows-style switch between popups.
//
// All tray popups share one window. When the window stays open but what it
// shows changes (Action Panel <-> hidden icons <-> an icon's own popup), this
// slides a snapshot of the OLD content down and fades it out, while the NEW
// content rises into place and fades in.
//
// The snapshot is taken ahead of time, while the popup is idle, so the switch
// itself never has to wait for it. No transition happens while the popup opens
// or closes: the window manager already animates those.
Item {
    id: transition

    // The item whose content is snapshotted (the popup's root item).
    required property Item target
    // What the popup is currently showing. A change while `active` animates.
    required property string mode
    // Whether the popup is open.
    required property bool active

    // Bound by the popup onto its content items.
    property real contentOpacity: 1
    property real contentShift: 0

    readonly property bool running: outAnim.running || inAnim.running
    // True while the old content's snapshot is on screen.
    readonly property bool showingOutgoing: outgoing.visible
    readonly property real shift: Kirigami.Units.gridUnit
    readonly property int duration: Kirigami.Units.longDuration

    property url snapshotUrl
    property string snapshotMode

    z: 2000
    enabled: false // never takes input

    function takeSnapshot() {
        if (!active || running || target.width <= 0 || target.height <= 0) {
            return;
        }
        const modeAtGrab = mode;
        target.grabToImage(result => {
            // Discard it if a transition started or the mode moved on meanwhile.
            if (!transition.running && transition.mode === modeAtGrab) {
                transition.snapshotUrl = result.url;
                transition.snapshotMode = modeAtGrab;
            }
        });
    }

    function start() {
        outAnim.stop();
        inAnim.stop();
        outgoing.source = snapshotUrl;
        outgoing.offsetY = 0;
        outgoing.opacity = 1;
        outgoing.visible = true;
        transition.contentOpacity = 0;
        transition.contentShift = shift;
        outAnim.start();
        inAnim.start();
    }

    onModeChanged: {
        if (active && snapshotUrl.toString() !== "" && snapshotMode !== mode) {
            start();
        }
    }

    onActiveChanged: {
        if (active) {
            snapTimer.restart();
        } else {
            // Closed: forget the snapshot (it would be stale next time).
            snapshotUrl = "";
            snapshotMode = "";
        }
    }

    // Snapshot soon after opening, and refresh it now and then so the old
    // content it shows is reasonably current.
    Timer {
        id: snapTimer
        interval: 250
        onTriggered: transition.takeSnapshot()
    }
    Timer {
        interval: 1500
        repeat: true
        running: transition.active && !transition.running
        onTriggered: transition.takeSnapshot()
    }

    // The old content, bottom-aligned and sliding down as it fades.
    Image {
        id: outgoing
        property real offsetY: 0
        visible: false
        cache: false
        x: Math.round((transition.width - width) / 2)
        y: transition.height - height + offsetY
    }

    ParallelAnimation {
        id: outAnim
        NumberAnimation {
            target: outgoing
            property: "offsetY"
            to: transition.shift
            duration: transition.duration
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            target: outgoing
            property: "opacity"
            to: 0
            duration: transition.duration
            easing.type: Easing.InCubic
        }
        onRunningChanged: {
            if (!running) {
                outgoing.visible = false;
            }
        }
    }

    ParallelAnimation {
        id: inAnim
        NumberAnimation {
            target: transition
            property: "contentShift"
            to: 0
            duration: transition.duration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: transition
            property: "contentOpacity"
            to: 1
            duration: transition.duration
            easing.type: Easing.OutCubic
        }
        onRunningChanged: {
            if (!running) {
                // Settled: make sure we end exactly at rest, then snapshot the new state.
                transition.contentOpacity = 1;
                transition.contentShift = 0;
                snapTimer.restart();
            }
        }
    }
}
