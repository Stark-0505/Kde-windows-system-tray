/*
    SPDX-FileCopyrightText: 2016 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2020 Konrad Materka <materka@gmail.com>
    SPDX-FileCopyrightText: 2020 Nate Graham <nate@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid

PlasmaComponents3.ScrollView {
    id: hiddenTasksView

    property alias layout: hiddenTasks

    // Compact, icon-only grid: one square cell per icon, as many columns as
    // there are icons (up to the user's "icons per row" limit), then wrap.
    readonly property int cellSize: Plasmoid.configuration.iconSize + Kirigami.Units.smallSpacing * 3
    // Guard against a missing/zero/odd stored value: fall back to 5 per row.
    readonly property int maxColumns: Plasmoid.configuration.popupColumns >= 3 ? Plasmoid.configuration.popupColumns : 5
    // Beyond this many rows the grid scrolls (mouse wheel) instead of growing.
    readonly property int maxRows: 8
    readonly property int columnCount: Math.max(1, Math.min(hiddenTasks.itemCount, maxColumns))
    readonly property int rowCount: Math.ceil(hiddenTasks.itemCount / columnCount)

    // The exact size that fits every icon. ExpandedRepresentation sizes the
    // popup from these, so the popup scales with the number of hidden icons.
    readonly property int fitWidth: columnCount * cellSize
    readonly property int fitHeight: Math.min(rowCount, maxRows) * cellSize

    hoverEnabled: true
    background: null

    // ── Drag & drop support (the controller lives in main.qml) ──────────────
    // Insertion slot (0..itemCount) nearest to a point given in the grid's own
    // coordinates: the slot before the cell under the pointer, or after it when
    // the pointer is in the cell's second half.
    function slotAt(px, py) {
        const n = hiddenTasks.itemCount;
        if (n === 0) {
            return 0;
        }
        const cols = columnCount;
        const cw = hiddenTasks.cellWidth;
        const ch = hiddenTasks.cellHeight;
        // In a right-to-left layout the grid is mirrored: measure from the
        // right edge so "cell 0" is still the first icon.
        const x = hiddenTasks.effectiveLayoutDirection === Qt.RightToLeft ? hiddenTasks.width - px : px;
        const y = py + hiddenTasks.contentY;
        const lastRow = Math.ceil(n / cols) - 1;
        const row = Math.max(0, Math.min(lastRow, Math.floor(y / ch)));
        const col = Math.floor(x / cw);
        let slot;
        if (col < 0) {
            slot = row * cols;
        } else if (col >= cols) {
            slot = row * cols + cols;
        } else {
            slot = row * cols + col + ((x - col * cw) > cw / 2 ? 1 : 0);
        }
        return Math.max(0, Math.min(n, slot));
    }

    // The drop line for a slot, in the grid's content coordinates.
    function indicatorRect(slot) {
        const n = hiddenTasks.itemCount;
        if (n === 0 || slot < 0) {
            return Qt.rect(0, 0, 0, 0);
        }
        const cols = columnCount;
        const cw = hiddenTasks.cellWidth;
        const ch = hiddenTasks.cellHeight;
        const inset = Kirigami.Units.smallSpacing;
        let row;
        let col;
        if (slot >= n) {
            // after the very last icon
            row = Math.floor((n - 1) / cols);
            col = ((n - 1) % cols) + 1;
        } else {
            row = Math.floor(slot / cols);
            col = slot % cols;
        }
        // x as seen in the grid itself, then converted to content coordinates
        // (the indicator is a child of the grid's content item).
        const mirrored = hiddenTasks.effectiveLayoutDirection === Qt.RightToLeft;
        const itemX = mirrored ? hiddenTasks.width - col * cw : col * cw;
        // Centre the 2px line in the gap between two icons: icons are
        // cellSpacing narrower than their cells, so the gap sits cellSpacing/2
        // inside the cell boundary.
        return Qt.rect(itemX + hiddenTasks.contentX - 1 - hiddenTasks.cellSpacing / 2, row * ch + inset, 2, ch - inset * 2);
    }

    // Never show a scrollbar: its width would be taken out of the grid's
    // width, dropping a column, which makes the grid taller, which keeps the
    // scrollbar showing ("2 icons wide and scrolling"). The popup is sized to
    // fit every icon, so a bar is never needed; the wheel still scrolls if
    // there are more than maxRows rows.
    QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AlwaysOff
    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

    GridView {
        id: hiddenTasks

        readonly property int columns: hiddenTasksView.columnCount

        readonly property int cellSpacing: Kirigami.Units.smallSpacing

        cellWidth: hiddenTasksView.cellSize
        cellHeight: hiddenTasksView.cellSize

        // Don't let a 1px rounding overflow make the grid wiggle/scroll.
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height + 2

        // Drop line shown between icons while dragging.
        Rectangle {
            z: 10
            enabled: false
            visible: root.dragActive && root.dropZone === "popup" && root.dropSlot >= 0
            readonly property rect r: hiddenTasksView.indicatorRect(root.dropSlot)
            x: r.x
            y: r.y
            width: r.width
            height: r.height
            radius: 1
            color: Kirigami.Theme.textColor
        }

        currentIndex: -1
        highlight: PlasmaExtras.Highlight {}
        highlightMoveDuration: 0

        pixelAligned: true

        readonly property int itemCount: model.count

        model: root.hiddenModel
        delegate: ItemLoader {
            width: hiddenTasks.cellWidth - hiddenTasks.cellSpacing
            height: hiddenTasks.cellHeight - hiddenTasks.cellSpacing
            x: hiddenTasks.cellSpacing / 2
            y: hiddenTasks.cellSpacing / 2
            Accessible.role: Accessible.ListItem
        }

        keyNavigationEnabled: true
        activeFocusOnTab: true

        KeyNavigation.up: hiddenTasksView.KeyNavigation.up

        onActiveFocusChanged: {
            if (activeFocus && currentIndex === -1) {
                currentIndex = 0
            } else if (!activeFocus && currentIndex >= 0) {
                currentIndex = -1
            }
        }
    }
}
