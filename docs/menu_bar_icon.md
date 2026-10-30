# Menu Bar Icon

This document describes the menu bar status icon, how it detects inference servers started outside the app, and the two settings that control it.

The menu bar icon is a status display and a shortcut to the main window. It does not change Direct Mode, process ownership, or any server lifecycle behavior.

## Icon states

The icon is an SF Symbol that changes with the state of your model profiles.

| State | Symbol | Meaning |
| --- | --- | --- |
| Off | `bolt.circle` | No managed server is running and no outside server was found. |
| On | `bolt.circle.fill` | At least one profile is serving. |
| Busy | `arrow.triangle.2.circlepath.circle` | A profile is starting, loading, checking readiness, or stopping, and nothing is serving yet. |
| Outside server | `arrow.up.right.circle` | Nothing managed is running, but a `rapid-mlx` or `mlx_lm` server was found running outside the app. |

Precedence is **On, then Busy, then Outside server, then Off**. A managed server always decides the icon; an outside server only changes an otherwise idle icon.

### What counts as "on"

A profile counts as on when it is not in a transitional state and either:

- its runtime state is Ready, Degraded, or Adopted External Server, or
- a process started by this app is alive for the profile.

The check is per profile, so it is the same for Rapid-MLX and mlx_lm profiles. A server that was only *detected* on a profile's port (but not adopted) does not turn the icon on. The `Outside server` state covers servers in general, as described below.

## Servers running outside the app

The app also looks for `rapid-mlx` and `mlx_lm` servers that it did not start, for example one you launched from a terminal.

### How detection works

1. Every 5 seconds the app reads the process table with `ps`.
2. It keeps processes whose command line looks like Rapid-MLX or mlx-lm. The first word of the command must be a known launcher (`rapid-mlx`, `mlx_lm.server`, Python of any capitalization, `uv`, `uvx`, `pipx`, or a shell such as `bash`), and a later word must be `rapid-mlx`, `rapid_mlx`, `mlx_lm.server`, or `mlx_lm`.
3. It runs `lsof` to confirm those processes are listening on a TCP port. This excludes `rapid-mlx --help`, `pip install rapid-mlx`, editors, and `grep`, and provides the real port.
4. If `lsof` cannot run, it falls back to a stricter command-line match (`rapid-mlx serve ...`, `mlx_lm.server ...`) and reads the port from `--port` when given.

Python is matched case-insensitively because Homebrew and python.org Python appear in `ps` as `.../Python.app/Contents/MacOS/Python`.

### What is ignored

- Servers started by this app, and their worker processes. Anything running under the app's own process is skipped.
- Worker processes that share a listening socket with a parent server. The server is listed once.
- Processes that match by name but are not listening.

### What the app does with it

Display only. The app does not adopt, stop, restart, monitor memory of, or collect logs from these servers, and never sends signals to them. The scan is read-only.

The servers are shown in the menu under **Running outside the app**, as `Backend · :port · model · pid`. The port appears when `lsof` or `--port` provides it. The header also changes from "MLX: Stopped" to "MLX: Running outside the app" when nothing managed is running.

### Limits

- Detection is heuristic. Launchers other than those listed above, and command paths containing spaces, are not recognized.
- If the app were sandboxed it could not see other processes; this has not been verified against the app's entitlements.
- Because the scan runs every 5 seconds for as long as the app is open, it adds a small, constant `ps` (and, when something matches, `lsof`) cost. It is not tied to the setting that hides the icon.

## Menu contents

- Status header (title and detail line).
- Controls for the selected model and the connection details.
- **Running outside the app** list, when any are found.
- **Manage…** opens the main window. It is also the way back when the Dock icon is hidden.

The menu has no Logs or Settings entries. Logs and Settings are pages inside the main window.

## Settings

Both settings are in **Settings → General** and follow the usual draft-and-Save behavior.

### Menu bar icon

Default: **on**. Turning it off removes the status item. Removing the icon by ⌘-dragging it out of the menu bar also turns this setting off and saves it.

### When all windows are closed

Default: **off**. The outcome depends on the menu bar icon setting:

| This option | Menu bar icon | Closing the last window |
| --- | --- | --- |
| Off | Any | The app stays running with its Dock icon (previous behavior). |
| On | On | The Dock icon is hidden and the app keeps running in the menu bar. |
| On | Off | The app quits, because nothing could bring it back. |

Details:

- Only the main window counts. Sheets, alerts, and panels do not.
- A minimized window counts as an open window.
- Quitting uses the normal quit path, so any confirmation or server-shutdown handling is the same as ⌘Q.
- The Dock icon returns when a main window is opened again: with **Manage…**, by launching the app again, or by any other way a main window appears.
- If the menu bar icon is removed while the Dock icon is hidden, the Dock icon is restored so the app stays reachable.

Settings saved by older versions do not contain these two keys. They load with the defaults above.

## Test coverage

| File | Covers |
| --- | --- |
| `MenuBarIconStateTests.swift` | Symbols, on/busy/off rules, backend-independence, outside-server precedence. |
| `ExternalServerScannerTests.swift` | Detection on Homebrew Python, mlx_lm forms, `uv`, app-owned servers, worker deduplication, non-listening and unrelated processes, the no-`lsof` fallback, `ps` and `lsof` parsing. |
| `MenuBarSettingsTests.swift` | Setting defaults, loading older settings, round trip, the last-window rule. |

Not covered by automated tests, because they depend on a running app and window server: the activation-policy change that hides the Dock icon, the status item appearing and disappearing, and the live process scan.

### Manual check

1. Start a profile: the icon is filled. Stop it: the icon is outline.
2. Run `rapid-mlx serve <model> --port 8090` in a terminal. Within about 5 seconds the icon shows the outside-server symbol and the menu lists it with its port.
3. Turn **When all windows are closed** on, close the window: the Dock icon disappears and the menu bar icon stays. Choose **Manage…**: the Dock icon and window return.
4. Turn the menu bar icon off, close the window with the option on: the app quits.
