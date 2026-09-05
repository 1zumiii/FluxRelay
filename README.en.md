# FluxRelay

FluxRelay is a native macOS menu bar download manager built with SwiftUI and AppKit. It bundles its own arm64 aria2 engine and provides lightweight task management, detailed download views, and a system-level menu bar experience.

The current packaged version is `0.2.0`. It requires Apple Silicon (arm64) and macOS 14 or later.

[简体中文](README.md) | English

## Features

- Runs as a menu bar app without a Dock icon in the background.
- Shows a Dock icon while the main window is open, then returns to the menu bar when it closes.
- Bundles aria2 `1.37.0-git.9e72735` as its download engine.
- Supports HTTP, FTP, SFTP, magnet links, and `.torrent` files.
- Lets you choose individual files when adding a torrent.
- Pauses, resumes, removes, and clears completed tasks, with queue priority controls.
- Provides filtering, search, sorting, multi-selection, and batch actions.
- Persists download history so source, completion time, file location, and checksum results remain searchable after a restart.
- Shares one task snapshot between the menu bar and main window: 2-second polling during activity, 10 seconds when idle, and immediate refresh after actions.
- Uses compact list queries, caches file metadata, and loads torrent files and piece data on demand for details or actions.
- Includes task details, transfer statistics, files, sources, peers, trackers, and a piece map.
- Provides download, BitTorrent, connection, RPC, notification, and login item settings.
- Reports which settings applied immediately and provides a direct engine restart action for the rest.
- Learns per-host connection levels and recommends a split count based on file size.
- Can disable seeding and removes stale `.aria2` control files after completion.
- Shows overall progress in a Retina menu bar icon and reports completion or engine errors.
- Includes Simplified Chinese and English localization with instant language switching.

Configuration, download sessions, and logs are stored in macOS application support data. The bundled aria2 engine uses local JSON-RPC, saves its session, and shuts down cleanly when the app exits.

Completion times reflect transitions observed by the app. Imported completed tasks without a recorded date keep that date unknown; unavailable checksum configuration is shown as Unknown. Download defaults apply to new tasks. Pending engine settings remain visible until successfully applied. Restart saves the session and waits for the owned engine to exit; an external engine is never reported as successfully restarted.

## Build

Install the tools required by the engine build script:

```sh
brew install autoconf automake libtool gettext pkgconf cppunit
Scripts/build-aria2-arm64.sh --install
```

The script pins the aria2 source and dependency versions, verifies source archives, and produces an arm64-only engine. The engine build runs the upstream test suite; one environment-specific LPD multicast timeout on macOS is handled separately, while all other tests must pass.

Build the Swift app:

```sh
xcrun swift build -c release --arch arm64 --product FluxRelay
```

## Validation

```sh
swift test -c release
python3 Scripts/test-aria2-regressions.py
ARIA2_BINARY="$PWD/Resources/engine/aria2c" Scripts/smoke-test-aria2.sh
```

Regression tests cover task pagination, adaptive probe completion, asynchronous cancellation and duplicate submission, proxy configuration compatibility, and HTTPS certificate verification. Engine tests use temporary directories and independent loopback ports, without connecting to a running download engine or changing system certificate trust. The self-signed HTTPS test requires `python3` and `openssl`. The piece-map performance comparison is skipped by default and can be enabled through the switch documented in its test file.

Regression tests also cover history reload and deletion races, snapshot caching, idle polling, pending settings, and session recovery after changing the owned engine’s RPC port and secret.

## Package

```sh
Scripts/package-app.sh
```

The packaging script checks the engine version, architecture, and dynamic dependencies, then creates a signed app bundle at:

```text
.build/app/FluxRelay.app
```

## Project layout

- `Models`: application state, task models, and persisted configuration.
- `Views`: SwiftUI/AppKit views, status icons, and user-facing dialogs.
- `Controllers`: application lifecycle, windows, menu bar, and task coordination.
- `Services`: aria2 RPC, engine process, logging, and system integrations.
- `Utilities`: formatting, localization, and stateless helpers.
- `Tests`: task models, rendering, configuration, asynchronous flows, and engine regression tests.

User-facing strings live in `Resources/Localization`. The package script includes both Simplified Chinese and English resources in the app bundle.
