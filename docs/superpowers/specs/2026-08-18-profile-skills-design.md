# Profile Skill Pools — Design Spec

Date: 2026-08-18
Status: Approved (Approach A: manifest + symlinks)

## Problem

Skills are hand-curated per profile today: each profile's `skills/`
directory is a manually maintained farm of symlinks into skill source
repos. There is no shared registry of available skills, no declarative
record of which skills a profile should have, and no tooling to add,
remove, or re-sync them. The goal is managed curation: a central pool
of registered skills, a per-profile manifest selecting a subset, and
commands to materialize that selection as links.

## Data model

```
<data-root>/                          # $XDG_DATA_HOME/claude-profiles/ or %LOCALAPPDATA%\claude-profiles\
├── skills/                           # NEW: central pool
│   ├── humanize -> <source path>     # registered as symlink/junction, or a real directory
│   └── ...
├── <profile>/
│   ├── skills/                       # managed links into the pool + untouched manual entries
│   └── skills.conf                   # NEW: optional manifest
```

### Pool

- Located at `<data-root>/skills/`. Created on demand.
- Entries are directories or links to directories. `skills register`
  creates a symlink (POSIX) or directory junction (Windows, no admin
  required) pointing at a user-supplied source path, which must
  contain a `SKILL.md`.
- Pool entry names follow the existing profile-name validation:
  `[A-Za-z0-9_-]+`, no leading `.`, no `/`, `\`, or `..`.
- The profile name `skills` is reserved (case-insensitively, since the
  Windows data directory is case-insensitive) in all three validators and
  in the `.claude-profile` resolvers. If `<data-root>/skills` exists but
  looks like a pre-reservation profile (contains `settings.json` or
  `.credentials.json`), every pool operation and sync refuses with an
  error telling the user to move that profile aside.

### Manifest (`<profile>/skills.conf`)

- Plain text, one pool-skill name per line. Blank lines and lines
  starting with `#` are ignored (same parser style as
  `.claude-profile`).
- **File absent** = profile gets **all** pool skills (backward
  compatible default).
- **File present but empty** (or only comments) = explicitly **no**
  pool skills.
- **File present but unreadable** = error; sync aborts rather than
  treating it as "select nothing" and stripping the profile's links.
- Names are validated with the same rule as pool entries; invalid
  lines are skipped with a warning.
- Manifests may be CRLF (written by the cmd/PowerShell implementations
  into the shared Windows data directory); all readers and the sh
  add/remove editors strip CR before comparing.

### Managed vs unmanaged entries

- A link in `<profile>/skills/` is **managed** iff its literal link
  target resolves under the pool directory. Only one level of linking
  is ever created by the tool, so a prefix comparison of the literal
  target against the pool path suffices — no recursive resolution.
- Sync creates and removes managed links only. Hand-made symlinks,
  real directories, and files are never touched.
- If a manifest entry collides with an unmanaged entry of the same
  name, the unmanaged entry wins; sync warns and skips.

## Command surface

Identical across `claude-profile.sh`, `claude-profile-init.ps1`, and
`claude-profile.cmd`:

| Command | Behavior |
|---|---|
| `claude-profile skills` | List pool skills with status for the target profile: `linked`, `not linked`, or `conflict` (unmanaged entry shadows the name). |
| `claude-profile skills register <name> <path>` | Add `<path>` to the pool as `<name>` (symlink/junction). `<path>` must exist and contain `SKILL.md`. Fails if `<name>` already exists in the pool. |
| `claude-profile skills unregister <name>` | Remove `<name>` from the pool. Warns for each profile whose manifest still references it (manifests are not edited). Refuses to delete a real (non-link) directory without `--force`. |
| `claude-profile skills add <skill> [profile]` | Append to the manifest and link immediately. If the manifest is absent (= all), it is first written out as the full current pool list so the "all" semantics stay sticky, then `<skill>` is added. |
| `claude-profile skills remove <skill> [profile]` | Remove from the manifest (materializing it first, as with `add`) and unlink. |
| `claude-profile skills set <s1,s2,...> [profile]` | Replace the manifest wholesale, then sync. |
| `claude-profile skills reset [profile]` | Delete the manifest (back to "all") and sync. |
| `claude-profile skills sync [profile\|--all]` | Re-materialize managed links from manifest/pool state. |

- `[profile]` defaults to the active profile if set, else the default
  profile. `sync --all` iterates every profile directory.
- Sync algorithm: desired set = manifest names present in the pool
  (or the whole pool when no manifest) → delete managed links that
  are dangling or not in the desired set → create missing links.
  Manifest names absent from the pool produce a warning, never a
  failure.

## Touch points with existing behavior

- `claude-profile create` runs a sync at the end: with no manifest
  and a non-empty pool the new profile links every pool skill; with
  no pool it is a no-op (current behavior preserved).
- `claude-profile delete` is unchanged — the manifest lives inside
  the profile directory and is removed with it.
- `use` and directory-local auto-switching are untouched: profile
  switching remains a pure environment-variable change with no
  filesystem work on the bash per-prompt hot path.
- `claude-profile` (status) shows `Skills: all pool skills (M)` or
  `Skills: N of M pool skills (filtered)` once a pool exists; `list`
  appends `[skills: N/M]` to profiles that have a manifest (unfiltered
  profiles stay unannotated to keep the listing quiet).
- `help` documents the new subcommands.

## Per-implementation notes

- **POSIX sh** (`claude-profile.sh`): `ln -s` for links. Strict
  POSIX (no `local`, no arrays, `_cp_` variable prefix, `return` not
  `exit`). On MSYS2/Git Bash (`$MSYSTEM` set), link creation is
  delegated to `cmd //c mklink /J` with `cygpath -w` paths so links
  are junctions readable by the cmd and PowerShell implementations.
  Managed-link detection on MSYS2 compares the junction target (via
  `cygpath -u` of the reparse target as reported by `readlink`). If
  `readlink` cannot read a junction, the link is treated as unmanaged —
  a deliberately non-destructive degradation (links are left alone and
  reported as conflicts) rather than an untestable `cmd //c dir`
  parsing fallback.
- **PowerShell** (`claude-profile-init.ps1`): `New-Item -ItemType
  Junction` on Windows, `-ItemType SymbolicLink` elsewhere. Managed
  detection via the item's `LinkType`/`Target` properties. Manual
  `$args` parsing consistent with the rest of the file.
- **cmd** (`claude-profile.cmd`): `mklink /J` for pool and profile
  links, `rmdir` to remove a junction without touching its target.
  Managed detection parses `dir /AL` output for the `[target]`
  suffix and prefix-compares against the pool path. Same `goto`
  dispatch and `setlocal enabledelayedexpansion` idiom.

## Error handling

- All validation errors print to stderr and return non-zero without
  partial writes where feasible; sync is idempotent so a re-run
  repairs any interrupted state.
- Dangling pool registrations (source path deleted) are reported by
  `skills` listing and cleaned from profiles by `sync` (the managed
  link is removed when its pool entry no longer resolves).

## Testing

Manual verification matrix (project has no test framework):

1. `register` / `unregister` (link + real-dir + `--force` paths).
2. `add` / `remove` / `set` / `reset` on profiles with and without an
   existing manifest.
3. Absent-manifest default (all pool skills) at `create` and `sync`.
4. Empty manifest = zero managed links, unmanaged entries preserved.
5. Unmanaged conflict: hand-made link with a pool name survives sync
   with a warning.
6. Dangling pool target cleanup.
7. Platforms: Linux sh + pwsh; Windows cmd + PowerShell + Git Bash
   (junction interop between all three).
8. `shellcheck` and `checkbashisms` clean on `claude-profile.sh`.

## Documentation

README gains a "Per-profile skills" section covering the pool, the
manifest format and defaults, and the command table. CLAUDE.md's
command table and architecture notes are updated per repo rules.
