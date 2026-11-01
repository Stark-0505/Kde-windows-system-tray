/*
    SPDX-FileCopyrightText: 2013 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2014 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2019-2020 Konrad Materka <materka@gmail.com>
    SPDX-FileCopyrightText: 2022 ivan (@ratijas) tkachenko <me@ratijas.tk>
    SPDX-FileCopyrightText: 2025 Kristen McWilliam <kristen@kde.org>
    SPDX-FileCopyrightText: 2025 Nate Graham <nate@kde.org>
    SPDX-FileCopyrightText: 2026 Nathaniel Krebs <areyoufeelingitnowmrkrebs@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami
import org.kde.kitemmodels as KItemModels
import org.kde.kquickcontrols as KQC
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

KCMUtils.SimpleKCM {
    id: iconsPage

    signal configurationChanged
    property bool unsavedChanges: !(changedVisibility.size === 0 && changedShortcuts.size === 0)

    // The Windows 11–style system cluster: Network, Volume and Battery are
    // always shown next to the ExpanderArrow regardless of configuration
    // (see calculateEffectiveStatus in systemtraymodel.cpp), so their entry
    // below is locked rather than left editable. This is a separate KCM QML
    // document from main.qml/SystemTrayState.qml and can't share their
    // systemClusterPluginIds property directly — keep this literal list in
    // sync with those.
    readonly property var systemClusterPluginIds: [
        "org.kde.plasma.networkmanagement",
        "org.kde.plasma.volume",
        "org.kde.plasma.battery"
    ]

    property bool cfg_scaleIconsToFit
    property int cfg_iconSpacing
    property int cfg_iconSize
    property bool cfg_expanderOnLeft
    property bool cfg_autoSort
    property bool cfg_popupAnimation
    property int cfg_popupColumns
    property bool cfg_reverseIconOrder
    property bool cfg_showAllItems
    property list<string> cfg_shownItems: []
    property list<string> cfg_hiddenItems: []
    property list<string> cfg_dismissedItems: []
    property list<string> cfg_extraItems: []
    property list<string> cfg_disabledStatusNotifiers: []

    readonly property var changedShortcuts: new Map()
    readonly property var changedVisibility: new Map()

    // ── How an item is shown, as three independent choices ──────────────────
    // Behind the scenes there are still four stored values per item; these two
    // functions translate between them and the three controls on each row:
    //
    //   Enabled  Placement  Dynamic   stored value   meaning
    //   off      -          -         "disabled"     the item is switched off
    //   on       Pinned     -         "shown"        always in the panel
    //   on       Popup      on        "auto"         in the popup, comes to the
    //                                                panel when it has news
    //   on       Popup      off       "hidden"       always in the popup
    function visibilityParts(visibility) {
        switch (visibility) {
        case "shown":
            return { enabled: true, placement: "pinned", dynamic: false };
        case "hidden":
            return { enabled: true, placement: "popup", dynamic: false };
        case "disabled":
            return { enabled: false, placement: "popup", dynamic: true };
        case "auto":
        default:
            return { enabled: true, placement: "popup", dynamic: true };
        }
    }

    function visibilityFrom(enabled, placement, dynamic) {
        if (!enabled) {
            return "disabled";
        }
        if (placement === "pinned") {
            return "shown";
        }
        return dynamic ? "auto" : "hidden";
    }

    function saveConfig() {
        for (const [key, value] of changedVisibility.entries()) {
            updateVisibility(key, value);
        }
        for (const [key, value] of changedShortcuts.entries()) {
            key.globalShortcut = value;
        }
        changedShortcuts.clear();
        changedVisibility.clear();
        cfg_shownItemsChanged();
        cfg_hiddenItemsChanged();
        cfg_dismissedItemsChanged();
        cfg_extraItemsChanged();
        cfg_disabledStatusNotifiersChanged();
        changedShortcutsChanged();
        changedVisibilityChanged();
    }

    function updateVisibility(itemId: string, visibility: string): void {
        const shownIndex = cfg_shownItems.indexOf(itemId);
        const hiddenIndex = cfg_hiddenItems.indexOf(itemId);
        const dismissedIndex = cfg_dismissedItems.indexOf(itemId);
        const extraIndex = cfg_extraItems.indexOf(itemId);
        const disabledSniIndex = cfg_disabledStatusNotifiers.indexOf(itemId);

        if (shownIndex > -1) {
            cfg_shownItems.splice(shownIndex, 1);
        }
        if (hiddenIndex > -1) {
            cfg_hiddenItems.splice(hiddenIndex, 1);
        }
        // An explicit choice here replaces any earlier "moved it to the popup" dismissal.
        if (dismissedIndex > -1) {
            cfg_dismissedItems.splice(dismissedIndex, 1);
        }
        if (extraIndex > -1) {
            cfg_extraItems.splice(extraIndex, 1);
        }
        if (disabledSniIndex > -1) {
            cfg_disabledStatusNotifiers.splice(disabledSniIndex, 1);
        }

        switch (visibility) {
        case "auto":
        case "auto-sni":
            cfg_extraItems.push(itemId);
            break;
        case "shown":
            cfg_extraItems.push(itemId);
        /* fallthrough*/
        case "shown-sni":
            cfg_shownItems.push(itemId);
            break;
        case "hidden":
            cfg_extraItems.push(itemId);
        /* fallthrough */
        case "hidden-sni":
            cfg_hiddenItems.push(itemId);
            break;
        case "disabled-sni":
            cfg_disabledStatusNotifiers.push(itemId);
            break;
        }
    }

    function categoryName(category) {
        switch (category) {
        case "ApplicationStatus":
            return i18n("Application Status"); // qmllint disable unqualified
        case "Communications":
            return i18n("Communications"); // qmllint disable unqualified
        case "SystemServices":
            return i18n("System Services"); // qmllint disable unqualified
        case "Hardware":
            return i18n("Hardware Control"); // qmllint disable unqualified
        case "UnknownCategory":
        default:
            return i18n("Miscellaneous"); // qmllint disable unqualified
        }
    }

    Connections {
        target: Plasmoid.configSystemTrayModel
        function onRowsRemoved() {
            // if the user closes an app with a SNI that has a visibility change queued, we need to remove it
            // from the queue as the change is no longer visible in the UI.
            let idsToRemove = [...iconsPage.changedVisibility.keys()];
            for (let i = 0; i < Plasmoid.configSystemTrayModel.rowCount() && idsToRemove.length > 0; ++i) {
                let itemId = Plasmoid.configSystemTrayModel.index(i, 0).data(Qt.UserRole + 2);
                idsToRemove = idsToRemove.filter(id => id !== itemId);
            }
            idsToRemove.forEach(id => {
                iconsPage.changedVisibility.delete(id);
            });
            if (idsToRemove.length > 0) {
                iconsPage.changedVisibilityChanged();
            }
        }
    }

    // ── Reusable pieces ─────────────────────────────────────────────────────

    // A rounded card with a title; children go in the body.
    component SettingsCard: Rectangle {
        id: card

        property string title
        property string iconName
        default property alias content: body.data

        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 46
        Layout.alignment: Qt.AlignHCenter
        implicitHeight: cardLayout.implicitHeight + Kirigami.Units.largeSpacing * 2

        radius: Kirigami.Units.gridUnit / 2
        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.12)

        ColumnLayout {
            id: cardLayout
            anchors {
                fill: parent
                margins: Kirigami.Units.largeSpacing
            }
            spacing: Kirigami.Units.largeSpacing

            RowLayout {
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: card.iconName
                    fallback: "preferences-system"
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: Kirigami.Units.iconSizes.smallMedium
                }
                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 4
                    text: card.title
                    textFormat: Text.PlainText
                }
            }

            ColumnLayout {
                id: body
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
            }
        }
    }

    // One setting: title and a short explanation on the left, the control on
    // the right (or underneath, when the page is narrow).
    component SettingRow: GridLayout {
        id: row

        property string title
        property string description
        default property alias control: holder.data
        // Side by side only when the control AND a readable amount of text both
        // fit; otherwise the control goes underneath. (Based on the control's
        // own width, so a long segmented control switches to stacked earlier
        // than a short switch does.)
        readonly property bool wide: iconsPage.width - Kirigami.Units.largeSpacing * 6 >= holder.implicitWidth + Kirigami.Units.gridUnit * 14

        Layout.fillWidth: true
        columns: wide ? 2 : 1
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Kirigami.Units.smallSpacing

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            QQC2.Label {
                Layout.fillWidth: true
                text: row.title
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
            QQC2.Label {
                Layout.fillWidth: true
                visible: row.description !== ""
                text: row.description
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
        }

        RowLayout {
            id: holder
            Layout.alignment: row.wide ? (Qt.AlignRight | Qt.AlignVCenter) : Qt.AlignLeft
            spacing: Kirigami.Units.smallSpacing
        }
    }

    // A row of connected buttons, one of them selected.
    component SegmentedControl: RowLayout {
        id: seg

        // [{ text: "...", value: ... }, ...]
        property var options: []
        property var currentValue
        signal activated(var value)

        spacing: 0

        Repeater {
            model: seg.options
            delegate: QQC2.Button {
                required property var modelData
                text: modelData.text
                highlighted: seg.currentValue === modelData.value
                onClicked: seg.activated(modelData.value)
            }
        }
    }

    // ── The page ────────────────────────────────────────────────────────────

    ColumnLayout {
        id: page
        spacing: Kirigami.Units.largeSpacing

        Kirigami.InlineMessage {
            id: disablingSniMessage
            property string appName

            function showWithAppName(appName: string) {
                disablingSniMessage.appName = appName;
                visible = true;
            }

            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 46
            Layout.alignment: Qt.AlignHCenter
            type: Kirigami.MessageType.Warning
            text: xi18nc("@info:usagetip", "Look for a setting in <application>%1</application> to disable its tray icon before doing it here. Some apps’ tray icons were not designed to be disabled, and using this setting may cause them to behave unexpectedly.<nl/><nl/>Use this setting at your own risk, and do not report issues to KDE or the app’s author.", appName) // qmllint disable unqualified
            actions: [
                Kirigami.Action {
                    text: i18nc("@action:button", "I understand the risks") // qmllint disable unqualified
                    onTriggered: disablingSniMessage.visible = false
                }
            ]
        }

        Kirigami.InlineMessage {
            id: disablingKlipperMessage

            visible: iconsPage.changedVisibility.get("org.kde.plasma.clipboard") === "disabled"
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 46
            Layout.alignment: Qt.AlignHCenter
            type: Kirigami.MessageType.Warning
            text: xi18nc("@info:usagetip", "Disabling the clipboard is not recommended, as it will cause copied data to be lost when the application it was copied from is closed.<nl/><nl/>Only do this if you’ve manually added a standalone Clipboard widget somewhere else, or are using a 3rd-party clipboard manager. Also, instead consider configuring the clipboard to not save history, or to only remember one item at a time.") // qmllint disable unqualified
        }

        Kirigami.InlineMessage {
            id: disablingNotificationsMessage

            visible: iconsPage.changedVisibility.get("org.kde.plasma.notifications") === "disabled"
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 46
            Layout.alignment: Qt.AlignHCenter
            type: Kirigami.MessageType.Warning
            text: xi18nc("@info:usagetip", "Disabling the Notifications widget is not recommended, as notifications sent by apps will no longer be shown.<nl/><nl/>Only do this if you’ve manually added a standalone Notifications widget somewhere else, or are intentionally using a 3rd-party notification manager to handle notifications.") // qmllint disable unqualified
        }

        // ── Appearance ──
        SettingsCard {
            title: i18nc("@title:group", "Appearance") // qmllint disable unqualified
            iconName: "preferences-desktop-theme"

            SettingRow {
                title: i18nc("@label", "Icon size") // qmllint disable unqualified
                description: i18nc("@info", "Used in the panel and in the popup.") // qmllint disable unqualified

                SegmentedControl {
                    options: [
                        { text: i18nc("@item:inlistbox Icon size", "Custom"), value: false }, // qmllint disable unqualified
                        { text: Plasmoid.formFactor === PlasmaCore.Types.Horizontal
                              ? i18nc("@item:inlistbox Icon size", "Fit panel height")
                              : i18nc("@item:inlistbox Icon size", "Fit panel width"), value: true } // qmllint disable unqualified
                    ]
                    currentValue: iconsPage.cfg_scaleIconsToFit
                    onActivated: value => iconsPage.cfg_scaleIconsToFit = value
                }
            }

            SettingRow {
                visible: !iconsPage.cfg_scaleIconsToFit
                title: i18nc("@label:slider", "Custom size") // qmllint disable unqualified

                QQC2.Slider {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                    from: 12
                    to: 48
                    stepSize: 1
                    snapMode: QQC2.Slider.SnapAlways
                    value: iconsPage.cfg_iconSize
                    onMoved: iconsPage.cfg_iconSize = Math.round(value)
                }
                QQC2.Label {
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                    text: i18nc("@info Size in pixels", "%1 px", iconsPage.cfg_iconSize) // qmllint disable unqualified
                    textFormat: Text.PlainText
                }
            }

            SettingRow {
                title: i18nc("@option:check", "Popup animation") // qmllint disable unqualified
                description: i18nc("@info", "When one popup replaces another, the old one slides down and fades underneath.") // qmllint disable unqualified

                QQC2.Switch {
                    checked: iconsPage.cfg_popupAnimation
                    onToggled: iconsPage.cfg_popupAnimation = checked
                }
            }

            SettingRow {
                title: i18nc("@label", "Spacing") // qmllint disable unqualified
                description: i18nc("@info", "Space between icons in the panel.") // qmllint disable unqualified

                SegmentedControl {
                    options: [
                        { text: i18nc("@item:inlistbox Icon spacing", "Small"), value: 1 }, // qmllint disable unqualified
                        { text: i18nc("@item:inlistbox Icon spacing", "Normal"), value: 2 }, // qmllint disable unqualified
                        { text: i18nc("@item:inlistbox Icon spacing", "Large"), value: 6 } // qmllint disable unqualified
                    ]
                    currentValue: iconsPage.cfg_iconSpacing
                    onActivated: value => iconsPage.cfg_iconSpacing = value
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                visible: Kirigami.Settings.tabletMode
                text: i18nc("@info:usagetip when Touch Mode is on", "Spacing is set to Large automatically in Touch Mode.") // qmllint disable unqualified
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
            }
        }

        // ── Layout ──
        SettingsCard {
            title: i18nc("@title:group", "Layout") // qmllint disable unqualified
            iconName: "view-split-left-right"

            SettingRow {
                title: i18nc("@label Hidden-icons arrow button", "Expander arrow") // qmllint disable unqualified
                description: i18nc("@info", "The button that opens the popup of hidden icons.") // qmllint disable unqualified

                SegmentedControl {
                    options: [
                        { text: i18nc("@item:inlistbox", "Before the icons"), value: true }, // qmllint disable unqualified
                        { text: i18nc("@item:inlistbox", "Between icons and system group"), value: false } // qmllint disable unqualified
                    ]
                    currentValue: iconsPage.cfg_expanderOnLeft
                    onActivated: value => iconsPage.cfg_expanderOnLeft = value
                }
            }

            SettingRow {
                id: directionRow

                // Evaluate current system state for dynamic labels
                readonly property bool isRtl: Qt.application.layoutDirection === Qt.RightToLeft
                readonly property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

                title: i18nc("@label Which direction system tray icons in the Panel emerge from the expander arrow", "Direction") // qmllint disable unqualified
                description: i18nc("@info", "Which way the tray fills.") // qmllint disable unqualified

                SegmentedControl {
                    options: {
                        if (directionRow.isVertical) {
                            // Vertical default is arrow at bottom, expanding upwards
                            return [
                                { text: i18n("Bottom-to-top"), value: false }, // qmllint disable unqualified
                                { text: i18n("Top-to-bottom"), value: true } // qmllint disable unqualified
                            ];
                        } else if (directionRow.isRtl) {
                            // RTL default is arrow on left, expanding to the right
                            return [
                                { text: i18n("Left-to-right"), value: false }, // qmllint disable unqualified
                                { text: i18n("Right-to-left"), value: true } // qmllint disable unqualified
                            ];
                        }
                        // Standard LTR default is arrow on right, expanding to the left
                        return [
                            { text: i18n("Right-to-left"), value: false }, // qmllint disable unqualified
                            { text: i18n("Left-to-right"), value: true } // qmllint disable unqualified
                        ];
                    }
                    currentValue: iconsPage.cfg_reverseIconOrder
                    onActivated: value => iconsPage.cfg_reverseIconOrder = value
                }
            }

            SettingRow {
                title: i18nc("@label Hidden-icons popup", "Icons per row in the popup") // qmllint disable unqualified
                description: i18nc("@info", "The popup grows to fit its icons, up to this many per row.") // qmllint disable unqualified

                QQC2.SpinBox {
                    from: 3
                    to: 10
                    value: iconsPage.cfg_popupColumns
                    onValueModified: iconsPage.cfg_popupColumns = value
                }
            }
        }

        // ── Behaviour ──
        SettingsCard {
            title: i18nc("@title:group", "Arranging icons") // qmllint disable unqualified
            iconName: "view-sort-ascending"

            SettingRow {
                title: i18nc("@label Tray icon order", "Order") // qmllint disable unqualified
                description: iconsPage.cfg_autoSort
                    ? i18nc("@info", "Icons are sorted by category, then name.") // qmllint disable unqualified
                    : i18nc("@info", "Drag icons to arrange them. Drag between the panel and the arrow's popup to pin or unpin.") // qmllint disable unqualified

                SegmentedControl {
                    options: [
                        { text: i18nc("@item:inlistbox", "Manual"), value: false }, // qmllint disable unqualified
                        { text: i18nc("@item:inlistbox", "Automatic"), value: true } // qmllint disable unqualified
                    ]
                    currentValue: iconsPage.cfg_autoSort
                    onActivated: value => iconsPage.cfg_autoSort = value
                }
            }

            SettingRow {
                title: i18nc("@option:check, This is referring to system tray entries", "Show every icon in the panel") // qmllint disable unqualified
                description: i18nc("@info", "Nothing is kept in the popup.") // qmllint disable unqualified

                QQC2.Switch {
                    checked: iconsPage.cfg_showAllItems
                    onToggled: iconsPage.cfg_showAllItems = checked
                }
            }
        }

        // ── Apps and services ──
        SettingsCard {
            title: i18nc("@title:group", "Apps and services") // qmllint disable unqualified
            iconName: "applications-system"

            QQC2.Label {
                Layout.fillWidth: true
                text: i18nc("@info", "Pinned icons stay in the panel. Dynamic icons live in the popup and move to the panel by themselves when they have something to show, such as a new notification. If you move one back to the popup it returns the next time it has news; turn Dynamic off to keep it in the popup.") // qmllint disable unqualified
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                opacity: 0.8
            }

            Kirigami.SearchField {
                Layout.fillWidth: true
                onTextChanged: sortFilterProxyModel.filterString = text
            }

            ListView {
                id: itemsList

                Layout.fillWidth: true
                Layout.preferredHeight: contentHeight
                // The whole page scrolls, not this list.
                interactive: false

                model: KItemModels.KSortFilterProxyModel {
                    id: sortFilterProxyModel
                    filterCaseSensitivity: Qt.CaseInsensitive
                    Component.onCompleted: sourceModel = Plasmoid.configSystemTrayModel // avoid unnecessary binding, it causes loops
                }

                section {
                    property: "category"
                    delegate: Kirigami.ListSectionHeader {
                        required property string section

                        text: iconsPage.categoryName(section)
                        width: itemsList.width
                    }
                }

                delegate: TrayItemDelegate {}
            }
        }
    }

    /*!
    * Delegate representing each system tray item.
    */
    component TrayItemDelegate: Item {
        id: listItem

        required property var applet
        required property var decoration
        required property string displayText
        required property int index
        required property string itemId
        required property string itemType

        width: itemsList.width
        implicitHeight: rowLayout.implicitHeight + Kirigami.Units.largeSpacing * 2

        readonly property bool isPlasmoid: itemType === "Plasmoid"
        readonly property bool isSystemClusterItem: iconsPage.systemClusterPluginIds.indexOf(itemId) >= 0

        readonly property string originalVisibility: {
            if (isSystemClusterItem) {
                return "shown";
            } else if (iconsPage.cfg_showAllItems || iconsPage.cfg_shownItems.indexOf(itemId) !== -1) {
                return "shown";
            } else if (iconsPage.cfg_hiddenItems.indexOf(itemId) !== -1) {
                return "hidden";
            } else if ((isPlasmoid && iconsPage.cfg_extraItems.indexOf(itemId) === -1) || (!isPlasmoid && iconsPage.cfg_disabledStatusNotifiers.indexOf(itemId) > -1)) {
                return "disabled";
            } else {
                return "auto";
            }
        }
        readonly property string currentVisibility: iconsPage.changedVisibility.has(itemId) ? iconsPage.changedVisibility.get(itemId).replace("-sni", "") : originalVisibility
        readonly property var parts: iconsPage.visibilityParts(currentVisibility)

        // Remember the last "on" choices so switching an item off and on again
        // (or Pinned and back to Popup) restores what the person had.
        property string lastActive: "auto"
        property bool lastDynamic: true

        // Computed from the value itself rather than from `parts`: this runs
        // while the row is still being created, before `parts` has a value.
        function rememberChoices(): void {
            const p = iconsPage.visibilityParts(currentVisibility);
            if (p.enabled) {
                lastActive = currentVisibility;
                if (p.placement === "popup") {
                    lastDynamic = p.dynamic;
                }
            }
        }
        onCurrentVisibilityChanged: rememberChoices()
        Component.onCompleted: rememberChoices()

        // Network, Volume and Battery are always shown next to the expander
        // (see systemClusterPluginIds above) — the tray ignores any other
        // choice for them, so the controls are locked to communicate that
        // rather than silently discarding a choice made here.
        readonly property bool locked: isSystemClusterItem || !itemId

        readonly property string summary: {
            if (isSystemClusterItem) {
                return i18nc("@info:usagetip", "Always shown next to the arrow, as part of the system group"); // qmllint disable unqualified
            }
            if (!parts.enabled) {
                return i18nc("@info:usagetip", "Switched off"); // qmllint disable unqualified
            }
            if (iconsPage.cfg_showAllItems) {
                return i18nc("@info:usagetip", "Shown in the panel"); // qmllint disable unqualified
            }
            if (parts.placement === "pinned") {
                return i18nc("@info:usagetip", "Pinned: always in the panel"); // qmllint disable unqualified
            }
            return parts.dynamic
                ? i18nc("@info:usagetip", "In the popup — moves to the panel when it has something to show") // qmllint disable unqualified
                : i18nc("@info:usagetip", "Always in the popup"); // qmllint disable unqualified
        }

        function setVisibility(value: string): void {
            if (value !== originalVisibility) {
                if (value === "disabled" && !isPlasmoid) {
                    disablingSniMessage.showWithAppName(nameLabel.text);
                }
                iconsPage.changedVisibility.set(itemId, value + (isPlasmoid ? "" : "-sni"));
            } else {
                iconsPage.changedVisibility.delete(itemId);
            }
            iconsPage.changedVisibilityChanged();
        }

        ColumnLayout {
            id: rowLayout
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                    source: listItem.decoration
                    animated: false
                    opacity: listItem.parts.enabled ? 1 : 0.5
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    QQC2.Label {
                        id: nameLabel
                        Layout.fillWidth: true
                        maximumLineCount: 1
                        text: listItem.displayText
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        opacity: listItem.parts.enabled ? 1 : 0.6
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        text: listItem.summary
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                    }
                }

                QQC2.Switch {
                    id: enabledSwitch
                    enabled: !listItem.locked
                    checked: listItem.parts.enabled
                    onToggled: listItem.setVisibility(checked ? listItem.lastActive : "disabled")

                    QQC2.ToolTip {
                        visible: listItem.isSystemClusterItem && parent.hovered
                        text: i18nc("@info:tooltip", "Always shown next to the expander as part of the system cluster") // qmllint disable unqualified
                    }
                }
            }

            // A Flow, not a row: on a narrow window the controls wrap onto
            // another line instead of running off the edge of the page.
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing
                enabled: listItem.parts.enabled && !listItem.locked
                opacity: listItem.parts.enabled ? 1 : 0.5

                SegmentedControl {
                    // With "show every icon" on, everything is in the panel
                    enabled: !iconsPage.cfg_showAllItems
                    options: [
                        { text: i18nc("@item:inlistbox", "Pinned"), value: "pinned" }, // qmllint disable unqualified
                        { text: i18nc("@item:inlistbox", "Popup"), value: "popup" } // qmllint disable unqualified
                    ]
                    currentValue: iconsPage.cfg_showAllItems ? "pinned" : listItem.parts.placement
                    onActivated: value => listItem.setVisibility(iconsPage.visibilityFrom(true, value, listItem.lastDynamic))
                }

                QQC2.Switch {
                    text: i18nc("@option:check Dynamic tray icon", "Dynamic") // qmllint disable unqualified
                    enabled: !iconsPage.cfg_showAllItems && listItem.parts.placement === "popup"
                    checked: listItem.parts.dynamic
                    onToggled: listItem.setVisibility(iconsPage.visibilityFrom(true, "popup", checked))

                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    QQC2.ToolTip.text: i18nc("@info:tooltip", "Dynamic icons move to the panel by themselves when they have something to show, like a new notification. If you move one to the popup it comes back the next time it has news. Turn this off to keep it in the popup.") // qmllint disable unqualified
                }

                KQC.KeySequenceItem {
                    id: keySequenceItem

                    visible: listItem.isPlasmoid
                    enabled: listItem.parts.enabled
                    readonly property string originalKeySequence: listItem.applet ? listItem.applet.plasmoid.globalShortcut : ""
                    keySequence: iconsPage.changedShortcuts.has(listItem.applet?.plasmoid) ? iconsPage.changedShortcuts.get(listItem.applet?.plasmoid) : originalKeySequence

                    onCaptureFinished: {
                        if (listItem.applet) {
                            if (keySequence !== listItem.applet.plasmoid.globalShortcut) {
                                iconsPage.changedShortcuts.set(listItem.applet.plasmoid, keySequence.toString());
                            } else {
                                iconsPage.changedShortcuts.delete(listItem.applet.plasmoid);
                            }
                            iconsPage.changedShortcutsChanged();
                        }
                    }
                }

                QQC2.Button {
                    readonly property QtObject configureAction: (listItem.applet && listItem.applet.plasmoid.internalAction("configure")) || null

                    Accessible.name: configureAction ? configureAction.text : ""
                    icon.name: "configure"
                    enabled: configureAction && configureAction.visible && configureAction.enabled
                    // Still reserve layout space, so not setting visible to false
                    opacity: enabled ? 1 : 0
                    onClicked: configureAction.trigger()

                    QQC2.ToolTip {
                        // Strip out ampersands right before non-whitespace characters, i.e.
                        // those used to determine the alt key shortcut
                        text: parent.Accessible.name.replace(/&(?=\S)/g, "")
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                opacity: 0.5
            }
        }
    }
}
