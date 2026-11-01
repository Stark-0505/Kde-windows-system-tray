# Integration and Validation Report

## Baseline

- Target repository: `Stark-0505/Kde-windows-system-tray`
- Target baseline branch and commit: `main`, `2dd24fb`
- KaizenGit source branch and commit: `main`, `2414580`
- Evernight Vista source branch and commit: `main`, `d00e739`
- Work branch: `integration/plasma-6.8.2`
- Project instruction file: supplied `chatgpt(2).md`, titled `CLAUDE.md`

The ZIP archives include Git object databases and branch references. The target's original `main` branch was not rewritten. Local tracking refs for both source repositories remain available under `refs/remotes/integration/`.

## Integrated KaizenGit commits

| Original commit | Integrated commit | Change |
|---|---|---|
| `c2e021d` | `0564407` | Installer hardening, verification, ShellCheck workflow |
| `bc6aa15` | `11ebafd` | Fix verification pipeline false negatives |
| `6b64174` | `b9a0d47` | Tray layout, icon size, and popup controls |
| `c6245bc` | `5c0cac6` | Hidden tray popup grid layout |
| `357fe4c` | `0be93b1` | Popup grid positioning |
| `2f072bf` | `aa296d1` | Tray icon ordering, pinning, and unpinning |
| `a3d52d8` | `599b29c` | Popup switching behavior and animation |
| `2414580` | `3bb9195` | Dynamic icons, safer tooltip text, popup transition refinement, and settings UI |

Each integrated commit has a two-line commit message. Shell syntax and applet JSON metadata were checked after each commit.

## Integrated Evernight Vista change

| Original commit | Integrated commit | Change |
|---|---|---|
| `68f2f02` | `7491aaf` | RPM packaging metadata |

The RPM spec was adapted to the Stark-0505 repository, project version, and Plasma 6.8.2 build baseline. The original spec claimed translations that are not present in the target tree; those claims and the unused translation file list were removed.

## Changes not imported

- Evernight Vista `55f6ab4` and `1890bb3`: older popup animation work is superseded by the newer KaizenGit transition implementation.
- Evernight Vista `d9e943a`: changes the default placement of clipboard and brightness items. This is a user-visible default change, not a required compatibility fix.
- Evernight Vista `d00e739`: duplicates the tray ordering and pinning feature already integrated from KaizenGit and includes large translation-file rewrites. It was not overlaid on the newer implementation.

## Modernization and hardening

- Require Qt 6.11+, KDE Frameworks and ECM 6.30+, and Plasma/PlasmaQuick 6.8.2+ at CMake configure time.
- Remove `systemtray.cpp` and `systemtray.h` from the static implementation library because the applet target compiles `systemtray.cpp` directly. This avoids compiling the applet implementation into both targets.
- Link Qt QML explicitly for the QML-backed plugin.
- Set the applet metadata compatibility floor to Plasma 6.8.2 and restore the target repository URLs.
- Require Plasma 6.8.2+ in the prebuilt installer and verify the downloaded plugin's runtime dependencies before changing the icon theme or installing the plugin.
- Check the built plugin's runtime dependencies before stopping Plasma Shell.
- Restart Plasma Shell after a failed installation, and repair the known panel metadata entry only after plugin installation succeeds.
- Detect stale user-local plugin copies in the verification script.
- Guard tray model insert/remove paths against duplicate rows, missing rows, and a source that disappears during registration.
- Add focused Node tests for tray ordering and tooltip markup sanitization.
- Run static checks in the release workflow before the native build.

The build baseline follows KDE's Plasma 6 schedule, which lists Qt 6.11 and KDE Frameworks 6.30 for Plasma 6.8:
https://community.kde.org/Schedules/Plasma_6

## Validation

Passed in this environment:

- `node tests/qml_helpers.test.cjs`
- `bash -n scripts/install.sh scripts/uninstall.sh system-tray/dev.sh system-tray/verify.sh`
- `python` JSON parse of `system-tray/metadata.json`
- `xmlstarlet val -e system-tray/contents/config/main.xml`
- `git diff --check`
- ZIP archive integrity check

Not verified in this environment:

- Native C++ build and link
- Runtime loading and visual behavior in Plasma Shell
- `qmllint`, ShellCheck, and RPM spec parsing

CMake configuration was attempted. It stopped before project configuration because ECM 6.30 development files are not installed in this environment. Qt 6, KDE Frameworks 6, and Plasma development packages are also unavailable, so this environment cannot validate the plugin ABI or prove that the original `libPlasmaQuick.so.7` error is fixed.

## Required final verification on Plasma 6.8.2

On a system with the required development packages installed:

1. Run `cmake -S system-tray -B build -DCMAKE_BUILD_TYPE=Release`.
2. Run `cmake --build build --parallel`.
3. Confirm `ldd build/lib/plasma/applets/org.kde.windowsmodern.systemtray.so` reports no missing libraries.
4. Install using `system-tray/dev.sh`.
5. Run `system-tray/verify.sh` and test panel placement, tray ordering, pinning, popup transitions, and settings.

Do not treat the project as fully build-verified until these checks pass on a Plasma 6.8.2 environment.
