import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami
import "../lib" as Lib
import "../js/colorType.js" as ColorType

Lib.Tile {
    id: tile

    property bool darkMode: ColorType.isDark(Kirigami.Theme.backgroundColor)

    label: darkMode ? qsTr("Dark Mode") : qsTr("Light Mode")
    iconSource: darkMode ? "weather-clear-night-symbolic" : "weather-clear-symbolic"
    active: false

    // The theme id is read from the configuration and ends up in a SHELL command,
    // so only accept what a Look-and-Feel package id can contain. Anything else
    // (spaces, ; | & $ ` quotes, a leading "-" that would be read as an option)
    // could run other commands or change what this one does.
    function isSafeThemeId(id) {
        return typeof id === "string" && /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(id);
    }

    function applyTheme(target) {
        if (!isSafeThemeId(target)) {
            console.warn("Colour toggle: ignoring a theme id that is not a valid package id");
            return false;
        }
        colorschemeExec.exec("plasma-apply-lookandfeel --apply " + target);
        return true;
    }

    function toggle() {
        var next = !darkMode;
        var target = next ? Plasmoid.configuration.darkTheme : Plasmoid.configuration.lightTheme;
        if (applyTheme(target)) {
            darkMode = next;
        }
    }

    onClicked: toggle()
    onMiddleClicked: toggle()

    tooltipText: darkMode ? qsTr("Switch to light mode") : qsTr("Switch to dark mode")

    Plasma5Support.DataSource {
        id: colorschemeExec
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
        }
        function exec(cmd) {
            connectSource(cmd);
        }
    }
}
