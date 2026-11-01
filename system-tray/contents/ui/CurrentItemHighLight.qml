/*
    SPDX-FileCopyrightText: 2011 Marco Martin <mart@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick

import org.kde.kirigami as Kirigami

// A single flat, rounded selection box (same look as the system cluster's
// highlight) that sits behind whatever the open popup belongs to.
//
// Unlike the stock Plasma "active tab" indicator this replaces, it does NOT
// slide between items and it never stretches across the whole tray: it just
// fades in on the item that opened the popup and fades out when it closes.
Rectangle {
    id: currentItemHighLight

    // Still passed by main.qml; unused by this flat style.
    property int location

    // What to highlight while the hidden-items popup is open (the arrow).
    property Item hiddenPopupAnchor: null

    property var highlightedItem: null

    readonly property real inset: Math.round(Kirigami.Units.smallSpacing / 2)

    z: -1 // always draw behind icons

    radius: 5
    color: Kirigami.Theme.textColor
    opacity: (highlightedItem && systemTrayState.expanded) ? 0.12 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: Kirigami.Units.shortDuration
            easing.type: systemTrayState.expanded ? Easing.OutCubic : Easing.InCubic
        }
    }

    // update when System Tray is expanded - applet activated or hidden icons shown
    Connections {
        target: systemTrayState

        function onActiveAppletChanged() {
            Qt.callLater(currentItemHighLight.updateHighlightedItem);
        }

        function onExpandedChanged() {
            Qt.callLater(currentItemHighLight.updateHighlightedItem);
        }

        // Switching between the Action Panel and the hidden-icons popup
        // keeps the tray expanded, so watch this one too.
        function onHiddenItemsRequestedChanged() {
            Qt.callLater(currentItemHighLight.updateHighlightedItem);
        }
    }

    // update when applet changes parent (e.g. moves from active to hidden icons)
    Connections {
        target: systemTrayState.activeApplet

        function onParentChanged() {
            Qt.callLater(updateHighlightedItem);
        }
    }

    // update when System Tray size changes
    Connections {
        target: parent

        function onWidthChanged() {
            Qt.callLater(updateHighlightedItem);
        }

        function onHeightChanged() {
            Qt.callLater(updateHighlightedItem);
        }
    }

    // update when scale of newly added tray item changes (check 'add' animation in GridView in main.qml)
    Connections {
        target: !!currentItemHighLight.highlightedItem && currentItemHighLight.highlightedItem.parent ? currentItemHighLight.highlightedItem.parent : null

        function onScaleChanged() {
            Qt.callLater(currentItemHighLight.updateHighlightedItem);
        }
    }

    function updateHighlightedItem() {
        if (!systemTrayState.expanded) {
            highlightedItem = null;
            return;
        }

        const applet = systemTrayState.activeApplet;
        if (applet && applet.parent && applet.parent.inVisibleLayout) {
            // A tray icon's own popup: highlight just that icon.
            changeHighlightedItem(applet.parent.container);
        } else if (systemTrayState.actionPanelShowing) {
            // The system cluster draws its own highlight for the Action Panel.
            highlightedItem = null;
        } else if (hiddenPopupAnchor) {
            // Hidden-icons popup (or a hidden icon's popup): highlight the arrow.
            changeHighlightedItem(hiddenPopupAnchor);
        } else {
            highlightedItem = null;
        }
    }

    function changeHighlightedItem(nextItem) {
        const p = parent.mapFromItem(nextItem, 0, 0);
        x = p.x + inset;
        y = p.y + inset;
        width = Math.max(0, nextItem.width - inset * 2);
        height = Math.max(0, nextItem.height - inset * 2);
        highlightedItem = nextItem;
    }
}
