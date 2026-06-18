---
name: slvnt
description: Drive the slvnt CLI to manage music on a Sleevenote hardware audio player — discover and pair with a player on the LAN, browse the catalog (list/status/info), upload files or folders, and remove releases. Use when asked to put music on, inspect, or manage a Sleevenote player from the command line.
---

# Managing a Sleevenote player with `slvnt`

`slvnt` is the Swift CLI in this repo. It talks to a Sleevenote hardware player on the local network: UDP/mDNS discovery, a 4-digit pairing code, an HTTP catalog API, and FTP upload.

## Running

Assume `slvnt` is installed and on your `PATH`; invoke commands directly as `slvnt <subcommand> …`.

If `slvnt` is not found (`command -v slvnt` fails, or you get "command not found"), it isn't installed — direct the user to install it from <https://github.com/velocityzen/slvnt> and stop there, rather than trying to build it yourself.

## Pair first (one-time, needs the device)

Every command except `discover`/`info` needs a paired session. Pairing requires the **4-digit code shown on the player's screen** — there is no way to obtain it over the network, so an agent cannot pair unattended.

```sh
slvnt pair                  # discovers the player, makes it show a code, prompts you to type it
slvnt pair --host 192.168.1.42 --code 1234   # non-interactive, if you already know IP + code
```

The session (device + code) is saved to `~/.config/slvnt/session.json` and reused by later commands. **To pair non-interactively you must already have the code** — ask the user for it, or have them run `slvnt pair`.

## Commands

| Command | What it does |
|---|---|
| `slvnt discover [--timeout <s>]` | Find a player on the LAN (no pairing needed). |
| `slvnt pair [--timeout <s>]` | Pair and save the session. |
| `slvnt info` | Show device info (works unpaired with `--host`). |
| `slvnt list [query]` | List releases; optional search filter. |
| `slvnt status` | Storage and battery. |
| `slvnt upload <path>…` | Upload a file, an album folder, or a library tree. |
| `slvnt remove --id <id>` | Remove a release by id… |
| `slvnt remove --artist <a> --release <r>` | …or by artist + title. Add `-f` to skip the confirm prompt. |
| `slvnt disconnect [--local-only]` | End the session and clear the saved code. |

### Connection flags (on every command except `discover`)

`--host <ip>` · `--http-port <n>` · `--ftp-port <n>` · `--https` · `--code <1234>` · `--config <path>`

They override the saved session for a single call. `--host` must be a **numeric IPv4** for uploads (the FTP client connects to a literal address).

## Output & exit codes (for scripting)

- Results go to **stdout**; progress and per-file errors go to **stderr**.
- Exit `0` on success; `1` for domain errors (not paired, invalid code, network); `64` for bad arguments.
- `upload` prints `[i/n pct%] filename` progress, a `✗ <error>` line per failed file, and a final `Done. N uploaded[, M failed].`; it exits non-zero if any file failed.
- `not paired` / `invalid or missing transfer code` errors mean you need to (re-)run `slvnt pair`.

## Behavior worth knowing

- **Resilient uploads:** a single unreadable or player-rejected file is reported but the batch continues; only a lost connection aborts the rest.
- **What uploads:** audio (`mp3 flac m4a wav aac ogg`) and artwork (`jpg jpeg png webp`); hidden/dot-files are skipped. Artist/Album are derived from folder names and land at `/<Artist>/<Album>/<file>` on the device.
- **Credential:** the 4-digit code is the only secret, reused for both the HTTP API and FTP login, and stored in plaintext in the session file — treat it accordingly.

## Quick recipes

```sh
# Is a player reachable? (no pairing)
slvnt discover

# After pairing, push an album and confirm it landed:
slvnt upload ~/Music/"Aphex Twin - Drukqs"
slvnt list "aphex"

# One-off against a known device without touching the saved session:
slvnt status --host 192.168.1.42 --code 1234
```
