# slvnt

A Swift library and CLI for managing music on a [Sleevenote](https://sleevenote.com) hardware audio player over the local network. Implements the player's discovery, pairing, catalog, and FTP-upload surface as documented in [api.md](api.md).

Built in the functional, `Result`-first style: every side effect (UDP, HTTP, FTP, disk) sits behind a protocol seam, errors travel in a typed `SlvntError` channel, and orchestration is declarative (`Result` combinators, `Pipe`, `Bracket`).

## Requirements

- macOS 15+
- Swift 6.2+

## Build

```sh
swift build            # debug binary at .build/debug/slvnt
swift test             # run the test suite
swift build -c release # optimized binary at .build/release/slvnt
```

## Quick start

```sh
# Find a player on the LAN
slvnt discover

# Pair: shows a 4-digit code on the device screen, then enter it.
# Saves the session to ~/.config/slvnt/session.json for later commands.
slvnt pair

# Browse and inspect the catalog
slvnt list                      # all releases
slvnt list "aphex"              # filtered (?q=)
slvnt status                    # storage + battery
slvnt info                      # raw GET /api/info

# Add music — a file, an album folder, or a library tree
slvnt upload ~/Music/Aphex\ Twin\ -\ Drukqs
slvnt upload track.flac cover.jpg

# Remove a release
slvnt remove --id abc123
slvnt remove --artist "Aphex Twin" --release "Drukqs"

# End the session and clear the saved code
slvnt disconnect
```

Any command accepts `--host`, `--http-port`, `--ftp-port`, `--https`, `--code`, and `--config` to bypass the saved session for a one-off call.

## Agent skill

[`SKILL.md`](SKILL.md) teaches an agent (e.g. Claude Code) how to drive this CLI — the commands, the on-device pairing-code constraint, output/exit codes, and upload behavior. Symlink it into your skills directory to make it auto-discoverable:

```sh
mkdir -p ~/.agents/skills/slvnt
ln -s "$PWD/SKILL.md" ~/.agents/skills/slvnt/SKILL.md
```

## Library

The `Slvnt` library is usable on its own. Each service takes its transport as an injectable seam (defaulting to the real implementation):

```swift
import Slvnt

let discovery = DiscoveryService()
let device = try await discovery.discover().get()
try await discovery.requestTransferCode(host: device.ip).get()

let session = Session(device: device, code: "1234")
let catalog = CatalogClient()
let releases = try await catalog.releases(session: session).get()

// upload(...) returns a Pipe of progress events — iterate it (or use a sink).
for await element in Uploader().upload(localPath: "/Music/Album", to: session) {
    switch element {
    case .success(let event): print(event.fileName, event.fraction)
    case .failure(let error): print("upload failed:", error)
    }
}
```

### Architecture

| Area | Type | Seam |
|------|------|------|
| Discovery (mDNS + UDP `:9999`) | `DiscoveryService` | `ServiceBrowser` → `NWBrowserServiceBrowser`; `DiscoveryTransport` → `POSIXUDPTransport` |
| Pairing | `TransferCode`, `DiscoveryService.requestTransferCode` | — |
| Catalog/control (HTTP `:8080`/`:8443`) | `CatalogClient` | `HTTPTransport` → `URLSessionHTTPTransport` |
| Upload (FTP `:2121`) | `Uploader`, `FTPClient` | `FileSystem`, `MetadataReader` |
| Path planning | `UploadPlanner`, `PathSanitizer`, `FolderStructure` | pure |
| Session persistence | `SessionStore` → `FileSessionStore` | — |

The connection lifecycle for uploads is owned by a `BracketAsync` (connect → transfer → quit, always), and files stream through a sequential `Pipe`.

## Scope notes

- **Discovery** races mDNS (`_sleevenote._tcp`, via `NWBrowser`) and UDP broadcast and returns whichever answers first — fastest on networks that favor either one. mDNS usually wins thanks to the OS resolver cache.
- **Artist/Album** are derived from folder names (matching the Manager's *fallback*). Reading them from audio tags (ID3/FLAC/MP4) is a future implementation behind the `MetadataReader` seam (`NoMetadataReader` is the default).
- **ZIP upload** (extract-then-send) is not implemented; upload a folder or files instead.
- **`--host` expects a numeric IP** for uploads (the FTP client connects to a literal address).

## CI & releasing

GitHub Actions run **lint** (`swift format lint --strict`) and **build & test** when Swift sources or `Package.resolved` change on `main` or a pull request (macOS runner, Swift 6.2 installed via `swift-actions/setup-swift`).

Releasing is manual: trigger the **Release** workflow (Actions → Release → Run workflow) with a semver `version` (e.g. `0.1.0`). It validates the version, stamps it into the CLI (`Sources/cli/Slvnt.swift`'s `version:`) and commits that, builds and tests, builds an optimized, symbol-stripped Apple Silicon (`arm64`) release binary, tags the commit, and publishes a GitHub release with the zipped binary attached (`slvnt-<version>-macos-arm64.zip`). Write the release body into `release.md` first — it becomes the release notes and is then emptied (committed back); with no `release.md` content, notes are auto-generated from commit history.

## Security

The player's only credential is a 4-digit transfer code, reused as the HTTP `X-Sleevenote-Code` header and the FTP password. FTP is plaintext and HTTPS certificate validation is disabled (the device ships a self-signed cert), matching the official Manager. The saved session — including the code — is written in plaintext to `~/.config/slvnt/session.json`. All traffic is LAN-scoped.
