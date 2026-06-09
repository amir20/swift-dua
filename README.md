# duaswift

A tiny Swift reimplementation of [`dua`](https://github.com/Byron/dua-cli)'s
`aggregate` command: a fast, parallel disk-usage tool for the terminal.

`duaswift` walks one or more paths using raw POSIX directory calls across a pool
of worker threads, sums up disk usage, and prints a sorted summary — mirroring
`dua aggregate`'s default semantics (allocated blocks, hard-link de-duplication,
symlinks not followed).

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

## Repository layout

This package also contains an unrelated `ProgressApp` SwiftUI demo target; the
disk-usage tool lives entirely under `Sources/duaswift`.

| Path | Purpose |
| --- | --- |
| `Sources/duaswift/Duaswift.swift` | CLI entry point (`ParsableCommand`). |
| `Sources/duaswift/Scanner.swift` | Parallel POSIX directory scanner. |
| `Sources/duaswift/DirectoryQueue.swift` | Blocking work-stack for the scan. |
| `Sources/duaswift/Progress.swift` | Live progress counter + status-line renderer. |
| `Sources/duaswift/Formatting.swift` | Byte/number formatting helpers. |
