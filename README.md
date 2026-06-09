# duaswift

A tiny Swift reimplementation of [`dua`](https://github.com/Byron/dua-cli)'s
`aggregate` command: a fast, parallel disk-usage tool for the terminal.

`duaswift` walks one or more paths using raw POSIX directory calls across a pool
of worker threads, sums up disk usage, and prints a sorted summary — mirroring
`dua aggregate`'s default semantics (allocated blocks, hard-link de-duplication,
symlinks not followed).

> **Also in this repo:** **Halo** (`swift run Halo`) — a native SwiftUI donut
> disk visualizer built on the same scanner (the `DiskKit` library). See
> [docs/halo.md](docs/halo.md) for its architecture, or build a double-clickable
> app with `swift package bundle-app Halo` (see below).

```console
$ duaswift Sources Tests Package.swift
  10.49 KB Package.swift
  18.43 KB Tests
  24.58 KB Sources
  53.50 KB total
```

While a scan runs, a live status line is rendered to stderr (only when stderr is
an interactive terminal):

```
⠹ scanning… 12,418 files · 1.21 GB · 0.4s  …/Sources/duaswift/Scanner.swift
```

## Requirements

- macOS 26 or newer
- Swift 6.2+ toolchain (ships with Xcode 26)

The tool uses the standard-library [`Synchronization`](https://developer.apple.com/documentation/synchronization)
module (`Mutex`) and builds in Swift 6 language mode with strict data-race
checking enabled.

## Build & run

```sh
# Debug build + run
swift run duaswift [OPTIONS] [PATH...]

# Optimized release binary
swift build -c release
.build/release/duaswift ~/Downloads
```

## Usage

```
duaswift [OPTIONS] [PATH...]
```

With no `PATH`, `duaswift` aggregates each entry in the current directory.

| Option | Description |
| --- | --- |
| `-A`, `--apparent-size` | Use apparent size (`st_size`) instead of disk usage (allocated blocks). |
| `-l`, `--count-hard-links` | Count hard-linked files each time they are seen, instead of de-duplicating. |
| `-t`, `--threads <N>` | Number of worker threads (default: logical CPU count). |
| `-f`, `--format <FMT>` | Byte format: `metric` (default) or `bytes`. |
| `--no-progress` | Disable the live progress line on stderr. |
| `-h`, `--help` | Print help. |

### Examples

```sh
# Disk usage of every entry in the current directory, sorted ascending
duaswift

# Apparent size of two directories, raw byte counts, no progress line
duaswift --apparent-size --format bytes --no-progress ~/src ~/docs

# Limit to 4 worker threads
duaswift -t 4 /usr
```

## How it works

- **Parallel walk.** A shared, depth-first work-stack (`DirectoryQueue`) hands
  directories to a pool of workers running on `DispatchQueue.concurrentPerform`.
  Each worker owns a private accumulator, so the hot path is lock-free; the only
  shared locks are the work-stack condition variable and an inode set used for
  hard-link de-duplication.
- **Disk usage vs. apparent size.** By default each file contributes
  `st_blocks * 512` (what it actually occupies on disk). `--apparent-size`
  switches to `st_size` (the logical file length).
- **Hard links.** By default a file with multiple hard links is counted once
  (tracked by `(device, inode)`); `--count-hard-links` counts every occurrence.

## Development

```sh
swift build      # build
swift test       # run the test suite
```

The test suite covers the formatting helpers and includes characterization
tests for the scanner (apparent-size deltas and hard-link de-duplication against
real temporary directory trees).

## Halo (GUI app)

**Halo** is the SwiftUI disk visualizer. A `Makefile` drives the packaging (run
`make` to list targets):

```sh
make run     # build & launch from source
make app     # -> Halo.app  (double-clickable, ad-hoc signed)
make dmg     # -> Halo.dmg  (drag-to-install disk image)
make icon    # regenerate Icons/AppIcon.icns from the Swift generator
```

The icon is drawn from the same oklch palette the app uses
(`Icons/make-icon.swift`). CI builds and uploads `Halo.dmg` as an artifact on
every push and PR.

## Repository layout

The package builds three products on a shared `DiskKit` core: the `duaswift`
CLI, the `Halo` SwiftUI app, and the `DiskKit` library itself.

| Path | Purpose |
| --- | --- |
| `Sources/duaswift/` | CLI entry point + parallel POSIX scanner (`dua aggregate`-style). |
| `Sources/DiskKit/` | Shared scan model: classified directory tree, derivations, formatting. |
| `Sources/Halo/` | SwiftUI donut visualizer built on `DiskKit`. |
| `Plugins/BundleApp/` | `swift package bundle-app` — wraps a release binary into a `.app`. |
| `Makefile` · `Icons/` | Build/package targets and the Swift app-icon generator. |
