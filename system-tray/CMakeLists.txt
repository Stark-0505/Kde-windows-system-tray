cmake_minimum_required(VERSION 3.20)

project(windowsmodern-systemtray VERSION 1.0.0 LANGUAGES CXX)

# ------------------------------------------------------------------------------
# C++ / Qt build configuration
# ------------------------------------------------------------------------------

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# Keep generated output local to the build tree.
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/lib")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/bin")

# ------------------------------------------------------------------------------
# Extra CMake Modules
# ------------------------------------------------------------------------------

# Plasma 6.8 uses Qt 6.11 and KDE Frameworks 6.30.
# Enforce the build baseline so an older SDK cannot produce a plugin that
# requests a PlasmaQuick SONAME unavailable on the target system.
set(QT_MIN_VERSION "6.11.0")
set(KF_MIN_VERSION "6.30.0")
set(PLASMA_MIN_VERSION "6.8.2")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)

set(CMAKE_MODULE_PATH
    "${ECM_MODULE_PATH}"
    ${CMAKE_MODULE_PATH}
)

include(ECMQtDeclareLoggingCategory)

# ------------------------------------------------------------------------------
# Qt
# ------------------------------------------------------------------------------

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS
    DBus
    Gui
    Qml
    Quick
    QuickControls2
    Widgets
)

# QML sources intentionally live in additional directories such as:
# lib/, components/, and components/volume/.
#
# Enable modern Qt behavior and generate qmldir metadata for those directories.
qt_policy(SET QTP0004 NEW)

# ------------------------------------------------------------------------------
# KDE install directories
# ------------------------------------------------------------------------------
#
# Qt6 initializes GNUInstallDirs before KF6::Package loads KDEInstallDirs.
# Explicitly mirror those locations into KDE_INSTALL_* so the install layout
# is intentional and no KDEInstallDirs compatibility warnings are emitted.

set(KDE_INSTALL_BINDIR         "${CMAKE_INSTALL_BINDIR}")
set(KDE_INSTALL_SBINDIR        "${CMAKE_INSTALL_SBINDIR}")
set(KDE_INSTALL_LIBDIR         "${CMAKE_INSTALL_LIBDIR}")
set(KDE_INSTALL_LIBEXECDIR     "${CMAKE_INSTALL_LIBEXECDIR}")
set(KDE_INSTALL_INCLUDEDIR     "${CMAKE_INSTALL_INCLUDEDIR}")
set(KDE_INSTALL_LOCALSTATEDIR  "${CMAKE_INSTALL_LOCALSTATEDIR}")
set(KDE_INSTALL_SHAREDSTATEDIR "${CMAKE_INSTALL_SHAREDSTATEDIR}")
set(KDE_INSTALL_DATAROOTDIR    "${CMAKE_INSTALL_DATAROOTDIR}")
set(KDE_INSTALL_DATADIR        "${CMAKE_INSTALL_DATADIR}")
set(KDE_INSTALL_LOCALEDIR      "${CMAKE_INSTALL_LOCALEDIR}")
set(KDE_INSTALL_MANDIR         "${CMAKE_INSTALL_MANDIR}")
set(KDE_INSTALL_INFODIR        "${CMAKE_INSTALL_INFODIR}")
set(KDE_INSTALL_SYSCONFDIR     "${CMAKE_INSTALL_SYSCONFDIR}")

# ------------------------------------------------------------------------------
# KDE Frameworks / Plasma
# ------------------------------------------------------------------------------

find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS
    Config
    CoreAddons
    IconThemes
    I18n
    ItemModels
    JobWidgets
    KCMUtils # Required by the embedded org.kde.kcmutils QML imports.
    KIO
    Package
    Service
    WindowSystem
    XmlGui
)

find_package(Plasma ${PLASMA_MIN_VERSION} REQUIRED)
find_package(PlasmaQuick ${PLASMA_MIN_VERSION} REQUIRED)

# ------------------------------------------------------------------------------
# Project configuration
# ------------------------------------------------------------------------------

add_compile_definitions(
    TRANSLATION_DOMAIN="plasma_applet_org.kde.windowsmodern.systemtray"
)

set(CMAKE_INCLUDE_CURRENT_DIR ON)

# ------------------------------------------------------------------------------
# DBus interfaces
# ------------------------------------------------------------------------------

set(DBUS_SRCS)

qt_add_dbus_interface(DBUS_SRCS
    "${CMAKE_CURRENT_SOURCE_DIR}/kf6_org.kde.StatusNotifierWatcher.xml"
    statusnotifierwatcher_interface
)

qt_add_dbus_interface(DBUS_SRCS
    "${CMAKE_CURRENT_SOURCE_DIR}/org.freedesktop.DBus.Properties.xml"
    dbusproperties
)

set(SNI_XML
    "${CMAKE_CURRENT_SOURCE_DIR}/kf6_org.kde.StatusNotifierItem.xml"
)

set_source_files_properties("${SNI_XML}" PROPERTIES
    NO_NAMESPACE FALSE
    INCLUDE "systemtraytypes.h"
    CLASSNAME OrgKdeStatusNotifierItem
)

qt_add_dbus_interface(DBUS_SRCS
    "${SNI_XML}"
    statusnotifieritem_interface
)

# DBusMenu interface.
set_source_files_properties(
    "${CMAKE_CURRENT_SOURCE_DIR}/com.canonical.dbusmenu.xml"
    PROPERTIES
        NO_NAMESPACE TRUE
        INCLUDE "dbusmenutypes_p.h"
        CLASSNAME DBusMenuInterface
)

qt_add_dbus_interface(DBUS_SRCS
    "${CMAKE_CURRENT_SOURCE_DIR}/com.canonical.dbusmenu.xml"
    dbusmenu_interface
)

# ------------------------------------------------------------------------------
# Logging categories
# ------------------------------------------------------------------------------

ecm_qt_declare_logging_category(SRC_LOGGING
    HEADER debug.h
    IDENTIFIER SYSTEM_TRAY
    CATEGORY_NAME kde.systemtray
    DEFAULT_SEVERITY Info
    DESCRIPTION "plasma applet systemtray"
)

ecm_qt_declare_logging_category(SRC_LOGGING
    HEADER debug_dbusmenu.h
    IDENTIFIER DBUSMENUQT
    CATEGORY_NAME org.kde.libdbusmenuqt
    DEFAULT_SEVERITY Info
    DESCRIPTION "libdbusmenu debug"
)

# ------------------------------------------------------------------------------
# Core sources
# ------------------------------------------------------------------------------

set(SRCS
    ${DBUS_SRCS}
    ${SRC_LOGGING}

    systemtraymodel.cpp
    systemtraymodel.h

    systemtraysettings.cpp
    systemtraysettings.h

    plasmoidregistry.cpp
    plasmoidregistry.h

    dbusserviceobserver.cpp
    dbusserviceobserver.h

    statusnotifieritemhost.cpp
    statusnotifieritemhost.h

    statusnotifieritemsource.cpp
    statusnotifieritemsource.h

    sortedsystemtraymodel.cpp
    sortedsystemtraymodel.h

    systemtraytypes.cpp
    systemtraytypes.h

    systemtraytypedefs.h

    dbusmenuimporter.cpp
    dbusmenuimporter.h

    dbusmenushortcut_p.cpp
    dbusmenushortcut_p.h

    dbusmenutypes_p.cpp
    dbusmenutypes_p.h

    utils.cpp
    utils_p.h
)

# ------------------------------------------------------------------------------
# Shared implementation library
# ------------------------------------------------------------------------------

add_library(systemtray_static STATIC
    ${SRCS}
)

set_target_properties(systemtray_static PROPERTIES
    POSITION_INDEPENDENT_CODE ON
)

target_link_libraries(systemtray_static
    PUBLIC
        Qt6::DBus
        Qt6::Gui
        Qt6::Qml
        Qt6::Quick
        Qt6::Widgets

        KF6::ConfigCore
        KF6::CoreAddons
        KF6::IconThemes
        KF6::I18n
        KF6::ItemModels
        KF6::JobWidgets
        KF6::KIOCore
        KF6::KIOGui
        KF6::Service
        KF6::WindowSystem
        KF6::XmlGui

        Plasma::Plasma
        Plasma::PlasmaQuick
)

# ------------------------------------------------------------------------------
# Plasma applet
# ------------------------------------------------------------------------------

plasma_add_applet(org.kde.windowsmodern.systemtray
    CPP_SOURCES
        systemtray.cpp

    RESOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/config/main.xml"
)

target_link_libraries(org.kde.windowsmodern.systemtray
    PRIVATE
        systemtray_static
)

target_include_directories(org.kde.windowsmodern.systemtray
    PRIVATE
        "${CMAKE_CURRENT_BINARY_DIR}"
)

# ------------------------------------------------------------------------------
# QML resources
#
# Keep the original directory layout. The QML code uses relative imports such as
# "lib" and "../js/funcs.js", so flattening all files into one directory would
# break those imports.
# ------------------------------------------------------------------------------

ecm_target_qml_sources(org.kde.windowsmodern.systemtray
    SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/main.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/AbstractItem.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/BackgroundAppItem.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/CompactApplet.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/ConfigGeneral.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/config.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/CurrentItemHighLight.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/ExpanderArrow.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/PopupGhost.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/ExpandedRepresentation.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/HiddenItemsView.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/ItemLoader.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/PlasmoidItem.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/PlasmoidPopupsContainer.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/PulseAnimation.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/StatusNotifierItem.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/SystemTrayState.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/ActionPanel.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/FlyoutRouter.qml"
)

ecm_target_qml_sources(org.kde.windowsmodern.systemtray
    PATH lib
    SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/lib/Tile.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/lib/SplitTile.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/lib/Slider.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/lib/SectionHeader.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/lib/PageHeader.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/lib/Page.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/lib/MoreSettingsLink.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/lib/ListRow.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/lib/FooterButton.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/lib/DetailPage.qml"
)

ecm_target_qml_sources(org.kde.windowsmodern.systemtray
    PATH js
    SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/js/funcs.js"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/js/colorType.js"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/js/trayorder.js"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/js/safetext.js"
)

ecm_target_qml_sources(org.kde.windowsmodern.systemtray
    PATH components
    SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/NetworkPage.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/NetworkToggle.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/BluetoothPage.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/BluetoothToggle.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/VolumePage.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/VolumeSlider.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/BatteryPage.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/Battery.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/BrightnessPage.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/BrightnessSlider.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/PowerProfilePage.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/PowerButton.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/AirplaneToggle.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/BatterySaverToggle.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/NightLightToggle.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/DndToggle.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/ColorSchemeToggle.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/MicMuteToggle.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/HotspotToggle.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/QuickSettingsPager.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/CastInvertToggle.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/InhibitSleepToggle.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/TouchpadToggle.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/KeyboardBrightnessSlider.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/Footer.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/ClipboardPage.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/NotificationsPage.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/DeviceNotifierPage.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/MediaControllerPage.qml"
)

ecm_target_qml_sources(org.kde.windowsmodern.systemtray
    PATH components/volume
    SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/volume/VolumeModels.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/volume/OutputDeviceSection.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/volume/InputDeviceSection.qml"
        "${CMAKE_CURRENT_SOURCE_DIR}/contents/ui/components/volume/VolumeMixerSection.qml"
)