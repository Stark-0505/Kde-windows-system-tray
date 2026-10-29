/*
    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

// Windows-style hand-over between popups.
//
// All the tray's popups share one window. When it stays open but shows
// something else (Action Panel <-> hidden icons <-> an icon's own popup) this
// keeps the OLD popup on screen in a second window, right where it was, and
// lets it slide down toward the panel and fade out underneath the new one.
//
// The old content can't be taken from the live window (it has already changed
// by then), so a snapshot is taken ahead of time: when the pointer touches a
// control that switches popups, shortly after the popup opens, and after each
// switch settles.
//
// If anything here misbehaves it only affects this cosmetic ghost; the real
// popup always switches regardless. It can be turned off in the settings.
Item {
    id: ghost

    // The popup's root item, which is snapshotted.
    required property Item target
    // What the popup shows now ("actions", "hidden", "applet"). A change while
    // `active` plays the hand-over.
    required property string mode
    // Whether the popup is open.
    required property bool active
    // Where the popup is currently anchored (the item the window is placed against).
    required property Item anchorItem
    // The real popup window: its placement is copied, and it is re-focused so
    // it ends up above the ghost.
    required property var mainDialog
    // The user's "Popup animation" setting.
    property bool animationEnabled: true

    readonly property bool playing: anim.running

    // Recorded together when a snapshot is taken, so the ghost matches the
    // popup exactly as it was then.
    property url snapshotUrl
    property string snapshotMode
    property size snapshotSize: Qt.size(0, 0)
    property Item snapshotAnchor: null

    readonly property real slide: Kirigami.Units.gridUnit
    readonly property int duration: Kirigami.Units.longDuration

    // Driven by the animation.
    property real imageOffset: 0
    property real imageOpacity: 1
    property real windowMargin: Kirigami.Units.largeSpacing

    function capture() {
        if (!animationEnabled || !active || playing || target.width <= 0 || target.height <= 0) {
            return;
        }
        const modeAtGrab = mode;
        const anchorAtGrab = anchorItem;
        const sizeAtGrab = Qt.size(target.width, target.height);
        target.grabToImage(result => {
            // Discard it if the hand-over started or the popup moved on meanwhile.
            if (!ghost.playing && ghost.active && ghost.mode === modeAtGrab) {
                ghost.snapshotUrl = result.url;
                ghost.snapshotMode = modeAtGrab;
                ghost.snapshotSize = sizeAtGrab;
                ghost.snapshotAnchor = anchorAtGrab;
            }
        });
    }

    function play() {
        anim.stop();
        picture.source = snapshotUrl;
        imageOffset = 0;
        imageOpacity = 1;
        windowMargin = Kirigami.Units.largeSpacing;
        win.visible = true;
        // The ghost window takes focus when it appears; hand it straight back so
        // the real popup is raised above it.
        raiseTimer.restart();
        // This snapshot is spent; the next one is taken fresh.
        snapshotUrl = "";
        snapshotMode = "";
        anim.start();
    }

    function stopAndHide() {
        anim.stop();
        raiseTimer.stop();
        openCapture.stop(); // a pending capture must not fire after the popup closed
        win.visible = false;
        picture.source = ""; // don't keep a picture of the popup (it can show clipboard or notification text)
    }

    onModeChanged: {
        if (animationEnabled && active && snapshotUrl.toString() !== "" && snapshotMode !== mode
                && snapshotSize.width > 0 && snapshotAnchor !== null) {
            play();
        }
    }

    onActiveChanged: {
        if (active) {
            openCapture.restart();
        } else {
            stopAndHide();
            snapshotUrl = "";
            snapshotMode = "";
        }
    }

    onAnimationEnabledChanged: {
        if (!animationEnabled) {
            stopAndHide();
            snapshotUrl = "";
        }
    }

    // A snapshot soon after opening, and another after each hand-over, so one
    // is always ready before the next click.
    Timer {
        id: openCapture
        interval: 300
        onTriggered: ghost.capture()
    }

    Timer {
        id: raiseTimer
        interval: 40
        onTriggered: ghost.mainDialog.requestActivate()
    }

    SequentialAnimation {
        id: anim
        // Give the ghost window a moment to appear before it starts to move.
        PauseAnimation {
            duration: 70
        }
        ParallelAnimation {
            NumberAnimation {
                target: ghost
                property: "imageOffset"
                to: ghost.slide
                duration: ghost.duration
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: ghost
                property: "imageOpacity"
                to: 0
                duration: ghost.duration
                easing.type: Easing.InCubic
            }
            // The whole window slides toward the panel as well.
            NumberAnimation {
                target: ghost
                property: "windowMargin"
                to: 0
                duration: ghost.duration
                easing.type: Easing.InCubic
            }
        }
        ScriptAction {
            script: {
                win.visible = false;
                picture.source = ""; // the picture of the old popup has done its job
                openCapture.restart();
            }
        }
    }

    // The second window, a copy of the real popup's placement showing the old content.
    PlasmaCore.AppletPopup {
        id: win

        objectName: "popupGhostWindow"
        visualParent: ghost.snapshotAnchor
        popupDirection: ghost.mainDialog.popupDirection
        margin: ghost.windowMargin
        removeBorderStrategy: PlasmaCore.AppletPopup.AtScreenEdges
        hideOnWindowDeactivate: false
        backgroundHints: ghost.mainDialog.backgroundHints
        appletInterface: ghost.mainDialog.appletInterface
        visible: false

        mainItem: Item {
            width: ghost.snapshotSize.width
            height: ghost.snapshotSize.height

            Image {
                id: picture
                // Bottom-aligned, so it can drop out of view toward the panel.
                x: 0
                y: parent.height - height + ghost.imageOffset
                opacity: ghost.imageOpacity
                cache: false
                enabled: false
            }
        }
    }
}
