/*
    SPDX-FileCopyrightText: 2016 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2020 Konrad Materka <materka@gmail.com>
    SPDX-FileCopyrightText: 2020 Nate Graham <nate@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick

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
    readonly property int columnCount: Math.max(1, Math.min(hiddenTasks.itemCount, Plasmoid.configuration.popupColumns))
    readonly property int rowCount: Math.ceil(hiddenTasks.itemCount / columnCount)

    // The exact size that fits every icon. ExpandedRepresentation sizes the
    // popup from these, so the popup scales with the number of hidden icons.
    readonly property int fitWidth: columnCount * cellSize
    readonly property int fitHeight: rowCount * cellSize

    hoverEnabled: true
    background: null

    GridView {
        id: hiddenTasks

        readonly property int columns: hiddenTasksView.columnCount

        readonly property int cellSpacing: Kirigami.Units.smallSpacing

        cellWidth: hiddenTasksView.cellSize
        cellHeight: hiddenTasksView.cellSize

        // Keep the grid centred if the popup ever ends up wider than it.
        leftMargin: Math.max(0, Math.floor((hiddenTasksView.availableWidth - hiddenTasksView.fitWidth) / 2))

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
