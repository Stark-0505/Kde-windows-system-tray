<h1 align="center">Windows-kde System Tray</h1>

<p align="center">
  A Windows 11-style System Tray for KDE Plasma 6.
</p>

<p align="center">
  <a href="https://kde.org/plasma-desktop">
    <img src="https://img.shields.io/badge/Plasma_6-1D99F3?logo=kde&logoColor=white&style=flat-square" alt="KDE Plasma 6">
  </a>
  <a href="https://fedoraproject.org">
    <img src="https://img.shields.io/badge/Fedora-51A2DA?logo=fedora&logoColor=white&style=flat-square" alt="Fedora">
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-GPLv3-86dbce?style=flat-square" alt="License: GPLv3">
  </a>
</p>

<p align="center">
  <img
    width="400"
    alt="Windows Modern System Tray and Action Centre on KDE Plasma"
    src="https://github.com/user-attachments/assets/eef42836-b658-4a9e-95a9-32ac0cc1380b"
  />
</p>

<br>

## ✨ Features

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>🖥️ Windows-style System Tray</h3>
      Network, Volume, and Battery docked into a compact, always-visible cluster next to the expander arrow.
    </td>
    <td width="50%" valign="top">
      <h3>🔔 Action Centre</h3>
      A dedicated Windows 11-inspired popup for system controls, separate from the Hidden Items tray popup.
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <h3>🧩 Configurable Tiles</h3>
      Double-click and drag to reorder Quick Settings tiles. Your layout persists across sessions.
    </td>
    <td width="50%" valign="top">
      <h3>🎨 Matching Icons</h3>
      The bundled WindowsModern-WhiteSurApps theme rounds out the look.
    </td>
  </tr>
</table>

### Tray appearance settings

Right-click the tray → **Configure System Tray…** → General:

- **Icon size** — a slider (12–48 px) instead of fixed sizes; it also sets the icon size in the hidden-icons popup. Choose "Scale with Panel height" to have it follow the panel instead.
- **Expander arrow** — shown on the left, before the icons (Windows style), or between the icons and the system cluster.
- **Icons per row in popup** — the hidden-icons popup is a compact, icon-only grid that sizes itself to the number of icons (names appear as tooltips).
- The popup highlight is a flat rounded box on the icon or arrow that opened it, rather than the theme's sliding tab indicator.

### Arranging, pinning and unpinning icons

- **Drag an icon** (in the panel or in the arrow's popup) to rearrange it. The icon you are dragging is dimmed, a copy follows the pointer, and a line shows where it will land.
- **Pin** an icon by dragging it from the popup onto the panel (or onto the arrow). **Unpin** it by dragging it onto the arrow, or into the popup.
- **Icon order** (settings): leave "Sort icons automatically" off (the default) to keep your own order, or turn it on to sort by category and name. Your manual order is remembered while automatic sorting is on.
- The system group (network, volume, battery) stays where it is.

<br>

## 📦 Installation

### ⭐ Recommended — one-command install

```bash
curl -fsSL https://github.com/Stark-0505/Kde-windows-system-tray/releases/latest/download/install.sh | bash
```

This automatically:

- finds the latest release and downloads everything from that one release
- checks every file against the release's `SHA256SUMS`, and refuses a release that doesn't match your system
- installs the plugin, then installs and activates the WindowsModern-WhiteSurApps icon theme
- replaces the stock System Tray on your panel, preserving its position
- restarts plasmashell and verifies the install

It's safe to run more than once: a repeat run checks what is installed and
only fixes what is wrong, without asking for your password if nothing needs
changing. Only the plugin-install step requires administrator authentication
via `pkexec`; the rest runs as your user. If a download or check fails, nothing
on your system is changed.

The prebuilt plugin is built for **Fedora 45 on x86_64** and the installer
refuses any other system. On another distribution or version, use
[manual installation](#-manual-installation).

### 🛠️ Manual installation

For other distros, or if you'd rather build from source.

1. Install build dependencies (Fedora shown; see [system-tray/BUILD.md](system-tray/BUILD.md) for Arch/Debian/Ubuntu):
   ```bash
   sudo dnf install gcc-c++ cmake extra-cmake-modules \
     qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtquickcontrols2-devel \
     kf6-kpackage-devel kf6-kconfig-devel kf6-ki18n-devel kf6-kcoreaddons-devel \
     kf6-kwindowsystem-devel kf6-kio-devel kf6-kiconthemes-devel \
     kf6-kitemmodels-devel kf6-kservice-devel kf6-kxmlgui-devel \
     kf6-kjobwidgets-devel kf6-kcmutils-devel \
     libplasma-devel plasma-workspace-devel plasma-workspace-libs
   ```
2. Clone this repository:
   ```bash
   git clone https://github.com/Stark-0505/Kde-windows-system-tray.git
   cd Kde-windows-system-tray
   ```
3. Build and install:
   ```bash
   cd system-tray
   ./dev.sh
   ```
4. Add "System Tray (Windows Modern)" to your panel: right-click the panel → **Add or Manage Widgets…**
5. (Optional) Install the icon theme, still from inside `system-tray/`:
   ```bash
   cp -r ../windows-icon/WindowsModern-WhiteSurApps ~/.local/share/icons/
   ```
   then set it via System Settings → Colors & Themes → Icons.

The source installer builds against your installed Qt and KDE libraries. It does
not replace your panel widget, but it can repair the known invalid
`plugin=metadata` entry if that corruption is present.

<br>

## 🔒 Security notes

The one-command installer downloads a **prebuilt binary** and installs it as root (via `pkexec`) into the system Qt plugin directory, where it loads into `plasmashell`. Know what you're trusting:

- It downloads from **this repository's releases** only (HTTPS only). Releases are built by GitHub Actions (`.github/workflows/release.yml`) from the exact commit the release tag points to, and come with a build attestation. You can check a downloaded file was built by this repository's workflow:
  ```
  gh attestation verify <downloaded file> --repo Stark-0505/Kde-windows-system-tray
  ```
- The installer rejects a release whose `SHA256SUMS` doesn't list every file it needs exactly once, or whose hashes don't match. The file is served from the same release as the binary, so on its own it catches corruption, **not** a malicious publisher. The attestation above is what ties a binary to the source it was built from.
- Pin repo and version for repeatable installs:
  ```
  curl -fsSL <install.sh URL> | WM_REPO=owner/repo WM_VERSION=v1.0.0 bash
  ```
- The safest option is to skip prebuilt binaries: use [manual installation](#️-manual-installation), which builds from source on your machine so you can read what you run.
- The root step re-verifies the binary's hash from a root-owned copy, so a local process can't swap the file between the check and the install.
- If there is no release yet, the one-liner stops with an error. Build from source in that case.
- The script is only run once it has been downloaded completely, so a dropped connection can't leave you with half an installer.

## ✅ Requirements

- **Runtime:** KDE Plasma 6.8.2 or newer.
- **Source build:** Qt 6.11 or newer, plus KDE Frameworks and ECM 6.30 or newer.
- **Prebuilt release:** Fedora 45, x86_64, not an image-based variant such as Kinoite. The installer checks this and stops on anything else. Other distributions and versions should use [manual installation](#-manual-installation).

## 🗑️ Uninstall

```bash
curl -fsSL https://github.com/Stark-0505/Kde-windows-system-tray/releases/latest/download/uninstall.sh | bash
```

Restores the stock System Tray in its original position, restores your
previous icon theme (if you haven't picked another one since), and removes the
Windows Modern plugin and icon theme. Nothing else is touched. Safe to run more
than once: if nothing is installed it says so and stops. If a step fails, the
install record is kept so you can run it again.

## 🧑‍💻 Development

Source code lives in [`system-tray/`](system-tray) — see
[`system-tray/BUILD.md`](system-tray/BUILD.md) for build dependencies and
development instructions. The icon theme is under
[`windows-icon/WindowsModern-WhiteSurApps/`](windows-icon/WindowsModern-WhiteSurApps).

Tests live in [`tests/`](tests). The shell and Node tests need no KDE install:

```bash
tests/installer.test.sh       # installer and uninstaller, against stand-ins for Plasma
tests/release_notes.test.sh   # release notes from real git history
tests/release_assets.test.sh  # the release gate
tests/release_contract.test.sh
node tests/qml_helpers.test.cjs
```

The C++ tests only need Qt 6: `cmake -S tests/cpp -B build-tests && cmake --build build-tests && ctest --test-dir build-tests`.

## 🚀 Releasing

Releases are made by hand, from `main`, with the **Release** workflow. Nothing is
published on a push, a pull request or a tag.

1. Make sure the version in `system-tray/CMakeLists.txt`, `system-tray/metadata.json`
   and `spec/kde-windows-system-tray.spec` is the one you are releasing (the
   workflow stops if they differ from what you enter).
2. On GitHub: **Actions → Release → Run workflow**, branch `main`, and enter the
   version, for example `v1.2.0`. Or from a terminal:
   ```bash
   gh workflow run release.yml --ref main -f version=v1.2.0
   ```

Versions are stable `vMAJOR.MINOR.PATCH` and must be higher than the latest
release. The workflow builds the commit `main` points at when you start it, even
if `main` moves on while it runs, runs the tests, builds on Fedora 45, checks
the result, and only then publishes. The release is created as a draft, checked
against what the installer expects, and published as the latest release in one
step, so users never see a half-made release. The tag is created on the commit
that was built. The notes list every commit since the previous release, under
"New Changes".

A release contains exactly these files:

| File | What it is |
| --- | --- |
| `org.kde.windowsmodern.systemtray-fedora-x86_64.so` | the compiled plugin (Fedora 45, x86_64) |
| `WindowsModern-WhiteSurApps.tar.gz` | the icon theme |
| `install.sh` | the installer |
| `uninstall.sh` | the uninstaller |
| `SHA256SUMS` | SHA-256 of every file above |
| `build-info.txt` | version, source commit, what it was built on, and the system it targets |

The file names are defined once, at the top of `scripts/install.sh`. The workflow
and the tests read them from there, and the release is refused if what was built
doesn't match what the installer will ask for.

<br>

## 🙌 Credits

This project builds upon: 

- [Jeysef/KDE-Windows-Modern](https://github.com/Jeysef/KDE-Windows-Modern) — the System Tray plugin in `system-tray/` is a modified fork of this, itself built on KDE's plasma-workspace System Tray
- [WhiteSur-icon-theme](https://github.com/vinceliuice/WhiteSur-icon-theme) — the icon theme is a derivative of this

Original source headers and applicable license notices are preserved in the project source files.

## 📄 License

GPL-3.0. See [LICENSE](LICENSE).
