# SPDX-License-Identifier: GPL-2.0-or-later
# RPM spec for kde-windows-system-tray
# Builds the Plasma 6 system tray applet (org.kde.windowsmodern.systemtray)
# and its embedded QML resources.

Name:           kde-windows-system-tray
Version:        1.0.0
Release:        1%{?dist}
Summary:        Windows 11–style System Tray plasmoid for KDE Plasma 6

License:        GPL-2.0-or-later
URL:            https://github.com/Stark-0505/Kde-windows-system-tray
Source0:        https://github.com/Stark-0505/Kde-windows-system-tray/archive/refs/heads/main.zip

# ---- Build-time dependencies ------------------------------------------------
BuildRequires:  gcc-c++
BuildRequires:  cmake
BuildRequires:  extra-cmake-modules >= 6.30.0

# Qt6
BuildRequires:  qt6-qtbase-devel >= 6.11.0
BuildRequires:  qt6-qtdeclarative-devel >= 6.11.0
BuildRequires:  qt6-qtquickcontrols2-devel >= 6.11.0

# KDE Frameworks 6
BuildRequires:  kf6-kpackage-devel >= 6.30.0
BuildRequires:  kf6-kconfig-devel >= 6.30.0
BuildRequires:  kf6-ki18n-devel >= 6.30.0
BuildRequires:  kf6-kcoreaddons-devel >= 6.30.0
BuildRequires:  kf6-kwindowsystem-devel >= 6.30.0
BuildRequires:  kf6-kio-devel >= 6.30.0
BuildRequires:  kf6-kiconthemes-devel >= 6.30.0
BuildRequires:  kf6-kitemmodels-devel >= 6.30.0
BuildRequires:  kf6-kservice-devel >= 6.30.0
BuildRequires:  kf6-kxmlgui-devel >= 6.30.0
BuildRequires:  kf6-kjobwidgets-devel >= 6.30.0
BuildRequires:  kf6-kcmutils-devel >= 6.30.0

# Plasma
BuildRequires:  libplasma-devel >= 6.8.2
BuildRequires:  plasma-workspace-devel >= 6.8.2

Requires:       plasma-workspace >= 6.8.2

%description
A Windows 11–style System Tray applet for KDE Plasma 6, forked from
KDE's plasma-workspace systemtray. Provides the Windows Modern tray
layout with a system cluster (Network/Volume/Battery), quick settings
flyout, and background app management.

%prep
%autosetup -n Kde-windows-system-tray-main

%build
%cmake -DCMAKE_BUILD_TYPE=Release \
       -DKDE_INSTALL_USE_QT_SYS_PATHS=ON \
       system-tray
%cmake_build

%install
%cmake_install

%files
%license LICENSE
%doc README.md
# This is a C++ Plasma Containment, not a pure-QML plasmoid package.
# plasma_add_applet() compiles the C++ plugin, the QML sources
# (ecm_target_qml_sources) and the metadata.json into a single .so via
# Qt resources. Therefore the only runtime artifact is the applet plugin
# below — there is no KPackage directory under share/plasma/plasmoids/
# and no kxmlgui5 .rc file installed. Listing those (non-existent) paths
# here was what caused the "File not found" RPM build errors.
%{_qt6_plugindir}/plasma/applets/org.kde.windowsmodern.systemtray.so

%changelog
* Sun Nov 01 2026 Repository Maintenance Bot <repository-maintenance@localhost> - 1.0.0-1
- Package the applet for Plasma 6.8.2 and newer.
- Require the Qt and KDE Frameworks versions used by Plasma 6.8.
