<div align="center">

<img src="docs/icon.png" width="120" alt="Halo">

# Halo

**A native macOS disk-space visualizer, written in SwiftUI.**

</div>

Point it at a folder
and it walks the whole tree, works out what's eating the space, and draws the
result as an interactive donut. You can read the same data two ways — the folders
sitting directly inside wherever you've drilled to, or everything rolled up by
file type — and the sidebar stays in sync as you hover and dig in. It also calls
out the kind of reclaimable junk a developer's disk tends to fill up with:
`node_modules`, caches, `DerivedData`, the Trash.

Underneath is **DiskKit**, a dependency-free library that does the filesystem
walk and hands back a classified directory tree. The app is just a view on top
of it.

## Requirements

- macOS 26 or newer
- A Swift 6.2 toolchain (ships with Xcode 26)

It's a plain SwiftPM package with no third-party dependencies, built in Swift 6
language mode with strict data-race checking.

## Building

Everything goes through the `Makefile`; run `make` on its own for the full list.

```sh
make run     # build and launch from source
make app     # Halo.app — double-clickable, ad-hoc signed
make dmg     # Halo.dmg — drag-to-install disk image
make test    # run the tests
make icon    # rebuild the app icon from Icons/make-icon.swift
```

`make app` wraps the release binary into a `.app` using the `bundle-app` SwiftPM
plugin, which writes the Info.plist, copies the icon, and ad-hoc signs the
result. CI runs the same steps on every push and uploads `Halo.dmg`.

## How it works

The scan is the interesting part. `DiskKit.TreeScanner` walks the tree with raw
POSIX calls (`opendir`, `readdir`, `lstat`) rather than `FileManager`, spreading
the work across a pool of workers that all pull from one shared, depth-first
queue. The single shared queue is deliberate: it stops one enormous subtree —
`~/Library`, a runaway `node_modules` — from starving the rest of the scan.
Sizes are real disk usage (allocated blocks), and symlinks aren't followed.

As directories come back, every file is sorted into a category — dependencies,
caches, build output, media, code, and a handful of others — and directories
that are safe to regenerate get flagged reclaimable. The donut then renders that
two ways: "by folder" shows the children of the current directory, "by type"
rolls every file up by its category. Both stay tied to the sidebar.

Scanning is streamed rather than batched, so the ring appears right away and each
top-level subtree fills in the moment it finishes, with a live file and byte
count running the whole time.

There's a longer write-up of the design in [docs/halo.md](docs/halo.md).

## Layout

| Path | What's there |
| --- | --- |
| `Sources/Halo/` | The SwiftUI app: donut, sidebar, scan model. |
| `Sources/DiskKit/` | The scan library: parallel walk, classified tree, formatting. |
| `Tests/` | Unit tests for both targets. |
| `Plugins/BundleApp/` | The `bundle-app` plugin that builds the `.app`. |
| `Icons/` | The app icon and the Swift program that generates it. |

## Development

```sh
swift build
swift test
```
