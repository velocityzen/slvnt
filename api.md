# Sleevenote Player API

The API surface a Sleevenote hardware player exposes on the local network, as consumed
by the Sleevenote Manager desktop app. This documents the **device side** only — what
the player must implement so a client can discover it, pair, browse/manage its catalog,
and upload music. Reverse-engineered from Manager v0.0.22; treat response bodies as
observed-from-client, not an official schema.

## Transports

| Service | Port | Protocol |
|---------|------|----------|
| Discovery | `9999` | UDP (broadcast + unicast) |
| Service advertisement | — | mDNS / DNS-SD (`_sleevenote._tcp`) |
| Catalog & control API | `8080` (HTTP) / `8443` (HTTPS) | HTTP/1.1, JSON |
| File upload | `ftp_port` (default `2121`) | FTP (plaintext) |

The player advertises its `http_port` (and optionally `ftp_port`) in the discovery
response. `http_port === 8443` signals TLS. The Manager accepts self-signed certs.

## 1. Discovery service (UDP :9999)

The player listens on UDP port `9999` for two plaintext magic payloads and replies to
the sender with a JSON datagram.

### Probe: `SLEEVENOTE_DISCOVERY`
The client broadcasts the literal bytes `SLEEVENOTE_DISCOVERY` to the subnet broadcast
address and `255.255.255.255:9999` (and unicast to a cached IP). The player must reply
with its descriptor JSON:
```json
{
  "hostname": "Sleevenote",
  "ip": "192.168.1.42",
  "http_port": 8080,
  "ftp_port": 2121,
  "api": "http"
}
```
| Field | Type | Notes |
|-------|------|-------|
| `hostname` / `device` | string | Display name. Either key accepted. |
| `ip` | string | **Required.** Player's IPv4 address. |
| `http_port` | number | Catalog API port. Omitted ⇒ client assumes `8080`. `8443` ⇒ HTTPS. |
| `ftp_port` | number | FTP port. Omitted/null ⇒ client assumes `2121`. |
| `api` | string | Stored as `protocol` by the client (informational). |

A legacy descriptor shape is also accepted: `{device, ip, port, ftp_port, protocol,
username, password, ssl, url}`.

### Probe: `REQUEST_TRANSFER_CODE`
The client sends the literal bytes `REQUEST_TRANSFER_CODE` to `ip:9999`. On receipt the
player **must display a fresh 4-digit code on its own screen** and reply within ~3 s:
```json
{ "status": "success" }
```
- `status: "success"` (or the field omitted) ⇒ accepted; the client proceeds to pairing.
- Any other `status` ⇒ client treats `message` as the error string.

This is the proximity-proof step: the code is shown physically on the device, never
sent over the network by the player.

## 2. mDNS advertisement

The player should advertise a DNS-SD service of type **`_sleevenote._tcp`** with an
A record and a port. The client uses the first IPv4 address and the advertised port;
port `8443` ⇒ HTTPS. mDNS records carry no FTP port, so the client falls back to `2121`.

## 3. Authentication — the transfer code

Pairing produces a single **4-digit code** (`^\d{4}$`) displayed on the device. That one
code is the shared secret for everything that follows:

- **HTTP**: sent on every authenticated request as header `X-Sleevenote-Code: <code>`.
- **FTP**: used as the FTP **password** (username `sleevenote`).

The player validates the code on each authenticated request and should answer a wrong or
missing code with **HTTP 401** and a body containing `invalid or missing transfer code`
(the client matches on that substring). `POST /api/disconnect` should invalidate the
active code/session. There is no separate login endpoint — the client "logs in" by
issuing `GET /api/releases` with the code and treating a 2xx as success.

## 4. HTTP catalog & control API

Base URL `http(s)://<ip>:<http_port>`. JSON request/response. All endpoints require the
`X-Sleevenote-Code` header **except `GET /api/info`**.

### `GET /api/info`
Unauthenticated reachability/identity probe. Returns a device descriptor object
(`200`). The client does not depend on specific fields here; non-2xx is treated as an
error.

### `GET /api/releases`
List the catalog. Auth required.
- Query: `?q=<search>` — optional free-text filter.
- `200` response:
  ```json
  { "releases": [
      { "id": "abc123", "artist": "Aphex Twin", "release": "Selected Ambient Works" }
  ] }
  ```
  The client reads `artist` and `release` (both strings) per item and `id` (string,
  optional) for removal. Additional fields are ignored by the client.

### `GET /api/storage`
Storage usage. Auth required.
- `200` response:
  ```json
  { "totalBytes": 64000000000, "usedBytes": 18000000000 }
  ```
  Client computes used % as `100 * usedBytes / totalBytes`.

### `GET /api/battery`
Battery state. Auth required.
- `200` response:
  ```json
  { "chargePercent": 82, "charging": false }
  ```

### `POST /api/releases/remove`
Delete a release from the device. Auth required. `Content-Type: application/json`.
- Body — by id (preferred) **or** by artist/release pair:
  ```json
  { "id": "abc123" }
  ```
  ```json
  { "artist": "Aphex Twin", "release": "Selected Ambient Works" }
  ```
- `2xx` on success. (Client allows up to 60 s for this call.)

### `POST /api/disconnect`
End the session / invalidate the current transfer code. Auth required (empty body).
- `2xx` on success.

### Error convention
Any non-2xx is an error. `401` + body containing `invalid or missing transfer code`
specifically signals a bad/expired code and sends the client back to the code prompt.

## 5. FTP server (file upload)

The player runs an FTP server used to push music and artwork onto the device.

- **Port**: the advertised `ftp_port` (default `2121`).
- **Login**: username `sleevenote`, password = the 4-digit transfer code. **Plaintext**
  (no FTPS) — the client connects with TLS disabled.
- **Concurrency**: the client uses a single, reused control connection and may retry once
  after a dropped connection (`ECONNRESET`/`EPIPE`), so the server should tolerate
  reconnects.
- **Long transfers**: the client's socket timeout is 600 s; large files stream in.

### Directory layout
Uploads are written to **absolute** paths rooted at `/`:
```
/<Artist>/<Album>/<file>
```
- The server must accept `MKD`/`ensure-dir` for parent folders and `STOR` for files.
- The client creates the `Artist` and `Album` directories before storing files.
- Path segments are pre-sanitized by the client: the characters `/ \ : * ? " < > |`,
  NUL and control chars are replaced with `_`; empty segments become `Unknown`. The
  server can assume incoming segment names are already filesystem-safe.

### Uploaded content
Only these file types are sent (the client filters before upload):
- Audio: `mp3`, `flac`, `m4a`, `wav`, `aac`, `ogg`
- Artwork: `jpg`, `jpeg`, `png`, `webp`

Artist/Album are derived by the client from audio tags (falling back to folder names),
so the directory names reflect tag metadata, not necessarily the source folder names.

## Port & constant reference

| Item | Value |
|------|-------|
| UDP discovery port | `9999` |
| Discovery probe magic | `SLEEVENOTE_DISCOVERY` |
| Transfer-code request magic | `REQUEST_TRANSFER_CODE` |
| HTTP API port | `8080` |
| HTTPS API port | `8443` |
| Default FTP port | `2121` |
| mDNS service type | `_sleevenote._tcp` |
| HTTP auth header | `X-Sleevenote-Code` |
| FTP username | `sleevenote` |
| FTP password | the 4-digit transfer code |
| Transfer code format | `^\d{4}$` |
