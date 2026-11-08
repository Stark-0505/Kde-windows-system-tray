# Repository Quality Pass 2

> Historical record of an earlier pass, kept as it was written. The workflows it names (`release.yml` triggered by tags, `shellcheck.yml`) have since been replaced by the manual `.github/workflows/release.yml` described in the README, and `scripts/install.sh` and `scripts/uninstall.sh` have been rewritten. For how things work now, read the README and `system-tray/BUILD.md`.

## Scope and method

- Reviewed the integrated Stark-0505 repository on `integration/plasma-6.8.2` without rewriting prior history.
- Performed a file inventory and source-level review across C++, QML, JavaScript helpers, shell scripts, CMake, D-Bus XML, metadata, packaging, tests, documentation, and icon assets.
- Made only changes tied to concrete duplicate work, asynchronous lifecycle, stale-pointer, or malformed-input risks. Unchanged files were not refactored for style alone.
- The supplied `chatgpt.md` / `CLAUDE.md` guidance was followed: small changes, no speculative abstractions, explicit verification, and preservation of working behavior.

## File-by-file review

Every non-binary project file listed below was inventoried and checked for relevant correctness, lifecycle, duplicate-work, API, configuration, and validation risks. “No change” means this pass did not find a sufficiently supported defect that justified editing that file; it does not mean the file is formally proven defect-free.

| File | Result |
|---|---|
| `.github/workflows/release.yml` | Reviewed as workflow/configuration; no change justified by available checks. |
| `.github/workflows/shellcheck.yml` | Reviewed as workflow/configuration; no change justified by available checks. |
| `INTEGRATION_REPORT.md` | Reviewed for build/install assumptions, documented claims, and validation coverage; no unrelated changes made. |
| `README.md` | Reviewed for build/install assumptions, documented claims, and validation coverage; no unrelated changes made. |
| `scripts/install.sh` | Reviewed; shell syntax check passed. |
| `scripts/uninstall.sh` | Reviewed; shell syntax check passed. |
| `spec/kde-windows-system-tray.spec` | Reviewed for build/install assumptions, documented claims, and validation coverage; no unrelated changes made. |
| `system-tray/BUILD.md` | Reviewed for build/install assumptions, documented claims, and validation coverage; no unrelated changes made. |
| `system-tray/CMakeLists.txt` | Reviewed for build/install assumptions, documented claims, and validation coverage; no unrelated changes made. |
| `system-tray/com.canonical.dbusmenu.xml` | Reviewed; parser validation passed. |
| `system-tray/contents/config/main.xml` | Reviewed; parser validation passed. |
| `system-tray/contents/ui/AbstractItem.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/ActionPanel.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/BackgroundAppItem.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/CompactApplet.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/ConfigGeneral.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/CurrentItemHighLight.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/ExpandedRepresentation.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/ExpanderArrow.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/FlyoutRouter.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/HiddenItemsView.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/ItemLoader.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/PlasmoidItem.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/PlasmoidPopupsContainer.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/PopupGhost.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/PulseAnimation.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/StatusNotifierItem.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/SystemTrayState.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/AirplaneToggle.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/Battery.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/BatteryPage.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/BatterySaverToggle.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/BluetoothPage.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/BluetoothToggle.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/BrightnessPage.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/BrightnessSlider.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/CastInvertToggle.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/ClipboardPage.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/ColorSchemeToggle.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/DeviceNotifierPage.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/DndToggle.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/Footer.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/HotspotToggle.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/InhibitSleepToggle.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/KeyboardBrightnessSlider.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/MediaControllerPage.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/MicMuteToggle.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/NetworkPage.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/NetworkToggle.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/NightLightToggle.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/NotificationsPage.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/PowerButton.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/PowerProfilePage.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/QuickSettingsPager.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/TouchpadToggle.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/VolumePage.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/VolumeSlider.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/volume/InputDeviceSection.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/volume/OutputDeviceSection.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/volume/VolumeMixerSection.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/components/volume/VolumeModels.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/config.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/js/colorType.js` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/js/funcs.js` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/js/safetext.js` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/js/trayorder.js` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/lib/DetailPage.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/lib/FooterButton.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/lib/ListRow.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/lib/MoreSettingsLink.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/lib/Page.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/lib/PageHeader.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/lib/SectionHeader.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/lib/Slider.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/lib/SplitTile.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/lib/Tile.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/contents/ui/main.qml` | Reviewed for state flow, event handling, helper use, and duplicate work; no change justified by available static checks. |
| `system-tray/dbusmenuimporter.cpp` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/dbusmenuimporter.h` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/dbusmenushortcut_p.cpp` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/dbusmenushortcut_p.h` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/dbusmenutypes_p.cpp` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/dbusmenutypes_p.h` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/dbusserviceobserver.cpp` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/dbusserviceobserver.h` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/dev.sh` | Reviewed; shell syntax check passed. |
| `system-tray/itemstatustracker.h` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/kf6_org.kde.StatusNotifierItem.xml` | Reviewed; parser validation passed. |
| `system-tray/kf6_org.kde.StatusNotifierWatcher.xml` | Reviewed; parser validation passed. |
| `system-tray/metadata.json` | Reviewed; parser validation passed. |
| `system-tray/org.freedesktop.DBus.Properties.xml` | Reviewed; parser validation passed. |
| `system-tray/plasmoidregistry.cpp` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/plasmoidregistry.h` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/sortedsystemtraymodel.cpp` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/sortedsystemtraymodel.h` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/statusnotifieritemhost.cpp` | Fixed stale asynchronous watcher snapshots, invalid item identifiers, and duplicate registration handling. |
| `system-tray/statusnotifieritemhost.h` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/statusnotifieritemsource.cpp` | Removed repeated iconChanged connections that retained obsolete icon paths and repeated reconfiguration work. |
| `system-tray/statusnotifieritemsource.h` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/systemtray.cpp` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/systemtray.h` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/systemtraymodel.cpp` | Guarded configuration callbacks against a cleared QPointer; rejected empty background app IDs; deduplicated Flatpak instances and guarded source lookups. |
| `system-tray/systemtraymodel.h` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/systemtraysettings.cpp` | Made known/enabled plugin list mutations idempotent and avoided redundant config writes/signals. |
| `system-tray/systemtraysettings.h` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/systemtraytypedefs.h` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/systemtraytypes.cpp` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/systemtraytypes.h` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/utils.cpp` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/utils_p.h` | Reviewed for ownership, async callbacks, model updates, duplicate work, and failure handling; no further change justified in this pass. |
| `system-tray/verify.sh` | Reviewed; shell syntax check passed. |
| `tests/qml_helpers.test.cjs` | Reviewed; existing QML helper tests passed. |

## Changes made

### `system-tray/statusnotifieritemhost.cpp`
- Ignore a pending registered-items snapshot if the StatusNotifierWatcher instance has changed while the D-Bus request was in flight. This prevents stale results from repopulating the tray after watcher restart.
- Check the asynchronous D-Bus reply before reading its payload and log failures at debug level.
- Reject malformed identifiers without a service component and ignore duplicate registration events. A service can be reported both by the signal and by the initial snapshot.

### `system-tray/statusnotifieritemsource.cpp`
- Connect `KIconLoader::iconChanged` once per loader instead of once per icon-theme-path change.
- Resolve the current icon path in the callback. This avoids retaining old paths in lambdas and avoids repeated reconfiguration work over an item’s lifetime.

### `system-tray/systemtraymodel.cpp`
- Return safely if a settings `QPointer` has cleared before a queued configuration callback runs.
- Ignore background-monitor records with an empty application ID.
- Avoid duplicate or empty Flatpak instance IDs in merged background-app records.
- Guard StatusNotifierItem lookups before dereferencing them in background filtering. This protects against service removal during signal-driven updates.

### `system-tray/systemtraysettings.cpp`
- Make add/remove operations for known and enabled plugin IDs idempotent.
- Reject empty IDs on insertion and avoid redundant disk writes and change notifications when the requested state already exists.

## Verification

- `node tests/qml_helpers.test.cjs`: passed.
- `bash -n scripts/install.sh scripts/uninstall.sh system-tray/dev.sh system-tray/verify.sh`: passed.
- `system-tray/metadata.json`: valid JSON.
- All tracked XML files: parsed successfully.
- 10,488 SVG files under `windows-icon/`: parsed successfully, zero errors.
- `git diff --check`: passed.
- Native CMake configure attempted with GCC 14.2.0. It stopped because ECM 6.30.0 development files are not installed. C++ compilation, linking, QML runtime validation, and Plasma Shell loading remain unverified in this environment.

## Known limits

- `qmllint`, `clang-tidy`, `cppcheck`, and `shellcheck` are not installed in this environment.
- No native Plasma 6.8.2 runtime is available here, so this pass does not claim the plugin ABI or runtime behavior is fully verified.
- No source changes were made to the icon artwork. The SVG parser pass found no malformed SVG documents.

## Plasma 6.8.2 API and build follow-up

The next user-reported build exposed a source/API mismatch that was not caught by the prior static-only pass. This follow-up makes these targeted changes:

- Use the `std::unique_ptr<Plasma::Applet>` returned by `PluginLoader::loadApplet()` and transfer ownership to `Containment::addApplet()` with `std::move()`.
- Use Plasma's `Applet::destroy()` when disabling/removing configured applets and when removing the migrated legacy containment. Keep direct deletion in `stopApplet()` because that path unloads a temporarily unavailable D-Bus-backed applet while retaining its configuration for restart.
- Declare the direct `KF6::CoreAddons` link and require the `KCMUtils` CMake component used by embedded QML imports.
- Make `dev.sh` show the actual configure and compiler diagnostics rather than truncating build output to the final three lines. Set the install prefix consistently to `/usr` and allow `BUILD_JOBS` to override the default parallelism.
- Align the documented Debian/Ubuntu and Arch dependency lists with the direct CoreAddons and Qt Quick Controls 2 requirements.

The follow-up is statically checked, but it is not build-verified here: this environment has no Qt 6 / KDE Frameworks / Plasma development packages, and CMake configuration cannot find ECM. Run the documented build on the target Plasma 6.8.2 or newer SDK to validate compilation, linking, and runtime loading.
