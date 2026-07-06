# Auto-Updater Design

**Date:** 2026-07-06
**Status:** Approved

## Problem

The tool has no way to tell a user their `claude-profile.sh` / `claude-profile-init.ps1`
/ `claude-profile.cmd` install is out of date. Today, upgrading means re-running the
install one-liner manually and hoping to remember to do so. There's also no version
marker anywhere in the repo besides the `v1.0.0` git tag — nothing installed on a
user's machine records what version they're running.

## Scope

Updates the **tool only** — `claude-profile.sh`, `claude-profile-init.ps1`,
`claude-profile.cmd`, and their installed `VERSION` file. Per-profile data under
`$XDG_DATA_HOME/claude-profiles/` (or `%LOCALAPPDATA%\claude-profiles\`) is untouched.

## Decision

### 1. Version tracking — separate `VERSION` file

A standalone `VERSION` file (plain text, e.g. `1.0.0`, no trailing newline — matching
the `.default` file convention) is installed alongside the scripts in the tool's
install dir:

- `$XDG_DATA_HOME/claude-profile/VERSION` (Linux/macOS/WSL, default
  `~/.local/share/claude-profile/VERSION`)
- `%LOCALAPPDATA%\claude-profile\VERSION` (Windows, including Git Bash/MSYS2)

Note the singular `claude-profile/` — the existing install directory, distinct from
the plural `claude-profiles/` profile-data directory (see `CLAUDE.md`).

`install.sh` / `install.ps1` write this file at install time, alongside the scripts
they already download. Each release bumps the `VERSION` file content and the git tag
together.

### 2. Passive check mechanism

Hook points (per your decision — only the common path per implementation, not an
extra always-on background process):

- **sh / ps1**: inside the `claude()` wrapper, on every invocation.
- **cmd**: inside `claude-profile.cmd`'s command dispatch (any subcommand), since cmd
  has no transparent `claude()` wrapper to hook into.

Behavior on each hook:

1. Read a cache file, `$XDG_DATA_HOME/claude-profile/.update-check` (mirrored path on
   Windows), containing: last-checked timestamp, latest known version, and a
   "notified" flag for that version.
2. If last-checked was less than 24h ago, skip the network call entirely and only
   act on the cached result (see step 4).
3. If 24h+ has elapsed (or the cache file doesn't exist): query
   `https://api.github.com/repos/pegasusheavy/claude-code-profiles/releases/latest`
   with a short timeout (2-3s connect/max-time). Extract `tag_name`, compare against
   the local `VERSION`. Write the result back to the cache file (new timestamp,
   latest version, reset "notified" flag to false if the version changed from what
   was previously cached).
   - On any failure — timeout, no connectivity, non-200 response, rate-limited,
     malformed JSON — **silently skip**. Still update the timestamp (so a fully
     offline machine doesn't retry the network call on every single invocation), but
     leave the cached version/notified state untouched.
4. If the cached latest version is newer than the installed `VERSION` **and** the
   "notified" flag for that version is not yet set: print one line to stderr —

   ```
   A new claude-profile version is available (v1.0.0 → v1.1.0). Run 'claude-profile update' to upgrade.
   ```

   then set the "notified" flag for that version in the cache file. On subsequent
   invocations, stay silent about that same version (avoids nagging every command).
   If an even newer version later appears, the flag resets and the notice fires once
   more for the new version.

This check must never meaningfully delay `claude` startup or `claude-profile`
dispatch — the timeout is short, failures are silent, and the common case (checked
within 24h) does zero network I/O.

### 3. Update command — dedicated logic per implementation

New `claude-profile update` subcommand, implemented independently in each of the
three files (not reusing `install.sh`/`install.ps1`):

1. Fetch the latest `VERSION` file and the matching script for that implementation
   (`claude-profile.sh`, `claude-profile-init.ps1`, or `claude-profile.cmd`) from the
   same raw GitHub URLs referenced in `CLAUDE.md`
   (`https://raw.githubusercontent.com/pegasusheavy/claude-code-profiles/main/...`).
2. Download to a temp file first (sh: `mktemp` + `trap ... EXIT`; ps1: a temp path
   via the standard temp dir; cmd: a temp file in `%TEMP%`, cleaned up in the
   existing `goto` cleanup path).
3. Only after the full download succeeds, atomically replace the installed script
   and `VERSION` file (rename/move over the old files).
4. On any failure (network error, empty/truncated download), leave the existing
   install untouched, clean up the temp file, and print an error. No partial
   upgrade is ever left in place.
5. On success, print old → new version. For sh/ps1, remind the user to re-source
   their shell config (`source ~/.bashrc` / `. $PROFILE` or equivalent) since a
   running shell can't hot-swap already-sourced functions. cmd needs no such
   reminder — `call claude-profile.cmd` re-reads the file fresh every invocation.

### 4. Error handling & offline behavior

- Every network call (passive check and `update`) uses a short timeout and fails
  gracefully. This tool's core purpose — managing local profile directories — has no
  dependency on connectivity, and the updater must never break that.
- Unauthenticated GitHub API rate limits (60 req/hr per IP) are a non-issue at a
  once-per-24h-per-user cadence.

## User Experience

```sh
# Normal usage — passive check runs silently in the background of the common path
claude
# stderr, only once when a new version first becomes known:
# A new claude-profile version is available (v1.0.0 → v1.1.0). Run 'claude-profile update' to upgrade.

# Explicit upgrade
claude-profile update
# Updating claude-profile.sh: v1.0.0 -> v1.1.0
# Done. Run 'source ~/.zshrc' (or restart your shell) to use the new version.
```

## File Changes

- `claude-profile.sh`: add version check inside `claude()`; add `update` case to
  `claude-profile()` dispatch.
- `claude-profile-init.ps1`: same two additions, PowerShell equivalents.
- `claude-profile.cmd`: add version check to command dispatch; add `update` label.
- `install.sh` / `install.ps1`: write `VERSION` file alongside the scripts at install
  time.
- `README.md`: document `claude-profile update` and the passive-check behavior.

## Out of Scope

- Updating per-profile data/configs.
- Auto-applying updates without an explicit `claude-profile update` run.
- Retry/backoff on the network calls (single-shot, fail-silent is sufficient for a
  low-frequency interactive tool — matches the existing installer's approach).
