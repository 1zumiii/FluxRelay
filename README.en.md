# FluxRelay

Native macOS menu bar download manager powered by its own bundled aria2 engine.

The original Motrix is a capable aria2 frontend, but on macOS it insists on keeping a Dock icon instead of living quietly in the menu bar. Working with its Electron/npm setup was also painfully slow on my network, even through a proxy. Eventually frustration won: I rebuilt the experience in native Swift. The download engine is still aria2, so this is best understood as a native macOS frontend rather than a downloader written from scratch.

Originally called Motrix Native, the project is now **FluxRelay**. Motrix inspired the project; aria2 still powers the downloads, while the interface and application logic are independently implemented in Swift.

[简体中文](README.md) | English

### For personal use only!!!

The current build requires Apple Silicon (arm64) and macOS 14 or later.

## What works

- Runs as a menu bar app with no Dock icon.
- Shows a Dock icon while the main window is open, then hides back to the menu bar when the window is closed.
- Stores all runtime data in `~/Library/Application Support/Motrix Native`.
- On first launch, imports compatible settings and `download.session` from Motrix once, then stops reading the original app's data.
- Bundles aria2 `1.37.0-git.9e72735`, built from upstream source with its own configuration; neither Motrix nor Homebrew is required at runtime.
- Connects to an already-running compatible aria2 RPC server, or starts its own bundled engine.
- Shows weighted download progress in the menu bar with a compact ring icon.
- Uses a warning status icon when the aria2 RPC engine is unavailable.
- Provides a native SwiftUI task window with a compact sidebar, search, and grouped task cards.
- Includes a preferences page for key Motrix basic/advanced settings.
- Supports System Default, Simplified Chinese, and English interface languages from the General settings page.
- Adds a compact add-task sheet for URLs and `.torrent` files.
- Shows active, waiting, and stopped task counts.
- Lists active, waiting, and recent stopped tasks.
- Adds HTTP/FTP/magnet links.
- Pauses, resumes, and removes tasks.
- Provides task context menus for common operations.
- Opens a native detail page with progress, transfer statistics, files, source, location, errors, and task ID.
- Visualizes aria2 piece completion as a compact block matrix, with automatic sampling for very large tasks.
- Supports task sorting, multi-selection, batch pause/resume/removal, completed-record cleanup, and waiting-queue priority controls.
- Can remove task records while moving their downloaded and partial files to the macOS Trash.
- Saves settings to FluxRelay's independent `system.json` and `user.json`.
- Can disable BitTorrent seeding entirely; restarting the engine reloads the latest saved settings.
- Removes stale `.aria2` control files only after aria2 reports the task as fully complete.
- Provides high-throughput adaptive HTTP connection tuning with per-host learned profiles and a balanced 48-connection starting point.
- Opens task files, task locations, and the download directory.
- Keeps config, aria2 log, engine info, and restart controls under the Advanced submenu.
- Only the menu bar Quit command exits the app. Closing the main window just hides it.
- Registers and removes the main app through macOS Login Items when "Open at Login" changes.
- Sends native download-complete notifications, including when a BitTorrent task starts seeding.
- Applies the configured removal confirmation in both the main window and menu bar menu.
- Saves the aria2 session and requests an RPC shutdown before terminating the owned engine.
- Shows a small engine info panel with the inherited connection/split/limit values.
- Monitors RPC health and attempts to restart the bundled aria2 engine with backoff when it becomes unavailable.
- Provides a manual "Restart Engine" menu item.

## Build

On the first build, or whenever the engine is updated, install the build tools named by the script and produce the pinned arm64 aria2 binary:

```sh
brew install autoconf automake libtool gettext pkgconf cppunit
cd FluxRelay
Scripts/build-aria2-arm64.sh --install
```

The script pins aria2 commit `9e7273583f83e881e3ec067b523ba88724088d2f`, restores Motrix's compatibility limit of 64 connections per server, verifies every source archive, and statically links zlib, Expat, SQLite, c-ares, and a security-patched libssh2/OpenSSL stack. aria2 itself uses the macOS AppleTLS backend for HTTPS, and the resulting executable dynamically links only system libraries. The upstream suite runs 979 tests. Some macOS network setups do not loop an LPD multicast packet back to its sender, so the script permits that exact environmental timeout only; the other 978 tests must pass.

Then build the Swift app:

```sh
xcrun swift build -c release --arch arm64 --product FluxRelay
```

## Validation

```sh
swift test -c release
python3 Scripts/test-aria2-regressions.py
ARIA2_BINARY="$PWD/Resources/engine/aria2c" Scripts/smoke-test-aria2.sh
```

Regression tests cover task pagination, adaptive probe completion, asynchronous cancellation and duplicate submission, legacy proxy settings, and HTTPS certificate verification. Engine tests use temporary directories and independent loopback ports, without connecting to the running download engine or changing system certificate trust. The self-signed HTTPS test requires `python3` and `openssl`. The piece-map performance comparison is opt-in with `MOTRIX_PERFORMANCE_CHECK=1`.

## Package

```sh
Scripts/package-app.sh
```

The app bundle, built in Release configuration, is written to:

```text
FluxRelay/.build/app/FluxRelay.app
```

## Source layout

The GitHub repository, app, and executable are now named `FluxRelay`. The internal Swift module retains the historical name `MotrixNative`, and existing local checkouts do not need to be renamed. The paths above assume a fresh clone into a `FluxRelay` directory.

The executable target follows an MVC-oriented layout under `Sources/MotrixNative`:

- `Models`: application state and persisted configuration.
- `Views`: SwiftUI/AppKit views, status icons, and user-facing dialogs.
- `Controllers`: application lifecycle, windows, status menu, and adaptive task coordination.
- `Services`: aria2 RPC/process/logging and macOS system integrations.
- `Utilities`: stateless formatting and tracker parsing helpers.
- `Views/MainWindow`: page-level main window views split by feature.
- `main.swift`: executable entry point and self-check command.

User-facing strings are stored in `Resources/Localization`. Swift code accesses them through `L10n`, and the package script includes both Simplified Chinese and English resources in the app bundle.

## Notes

The packaged app contains its own arm64 aria2 engine, defaults, build manifest, icon, and language resources. Packaging rejects the wrong architecture, a mismatched engine version, or non-system dynamic dependencies. Removing the original Motrix app does not remove FluxRelay's engine or settings. Launch FluxRelay once before deleting Motrix data so the one-time configuration and session migration can complete.

## Upgrading from Motrix Native

FluxRelay keeps the bundle identifier `dev.codex.motrix-native`, the data directory `~/Library/Application Support/Motrix Native`, and the log filename `motrix-native-aria2.log`. Existing settings and download sessions do not need to be imported again. These historical names preserve compatibility; they are not dependencies on the original Motrix app.

Quit the old version before opening `FluxRelay.app`, and do not run both versions together. If opening at login stops working after moving or replacing the app, turn Open at Login off and back on in Settings.
