# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ztms is a config-driven PowerShell toolkit for running a multi-service .NET +
Postgres + Redis local dev environment on Windows: starting/stopping
services, publishing, pulling repos, and cloning data from a dev server. It
is not hardcoded to any one machine's folder layout — all machine-specific
paths, ports, and hostnames live in a gitignored `tms.config.json`, generated
by `900_init-config.ps1`.

There is no build step and no package manager — this is a flat collection of
PowerShell 7+ (`pwsh`) scripts plus two shared modules under `modules/`. All
scripts require PowerShell 7+ specifically because several use
`ForEach-Object -Parallel`.

## Running tests

```powershell
.\tests\smoke-test.ps1
```

This is the only test suite and the only thing that resembles a build/CI
check in this repo. It:
1. Parses every `.ps1`/`.psm1` file to catch syntax errors.
2. Copies the repo to an isolated temp folder with a synthetic, intentionally
   incomplete `tms.config.json`, then runs each script's guard clauses
   against it (e.g. "No services configured") to confirm they fail
   gracefully — without touching real Docker/dotnet/Postgres/Redis.

It does **not** exercise actually running a service, cloning a real DB/Redis
cache, or the interactive prompts in `900_init-config.ps1` /
`901_set-env.ps1` — those need manual verification against a real setup
before a release. When adding a new script or changing a guard clause, add a
corresponding `Test-Step`/`Invoke-Guarded` case in `smoke-test.ps1` following
the existing pattern.

## Architecture

**Config flows one way, through two shared modules.** `tms.config.json`
(gitignored, created by `900_init-config.ps1`, schema documented in
`tms.config.example.json`) is the single source of machine-specific truth —
`reposRoot`, `deployRoot`, `processTag`, `services[]` (name/port/enabled),
`pullIgnoreFolders`, `database.*`, `redis.*`, `frontend.*`. Every numbered
script starts with:

```powershell
Import-Module (Join-Path $PSScriptRoot "modules\TmsConfig.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "modules\ProjectMenu.psm1") -Force
$config = Get-TmsConfig
```

- `modules/TmsConfig.psm1` — `Get-TmsConfig` reads/parses the JSON (throws
  with a helpful message if missing). `Get-TmsSecret` reads a secret from a
  **user-level** environment variable, prompting with hidden input and
  caching it at process scope if unset (never written to the config file or
  disk). Secrets never live in `tms.config.json`.
- `modules/ProjectMenu.psm1` — shared console UI: `Show-ProjectSelection`
  (multi-select checkbox menu, arrow keys + Enter, "Select All" and
  "Confirm & Run" pseudo-items, no selection = select all), `Show-Menu`
  (plain single-select arrow-key menu, generic/reusable), `Show-GroupedMenu`
  (single-select menu flattened across groups with non-selectable group
  headers — what `ztms.ps1` itself uses), `Confirm-Prompt` (y/N prompt).
  These have a specific ConPTY quirk workaround — see the comment above
  `Draw-Menu` in each function before changing cursor-position
  logic; Windows Terminal / VS Code's integrated terminal both report
  `BufferHeight == WindowHeight`, so rows must be reserved (blank lines
  written) before capturing `$top`, or Up/Down redraws break once the menu
  is taller than the visible window.

**Menu / process model.** `ztms.ps1` is the interactive entry point (also
reachable as the global `ztms` command once installed). It's a `$groups`
array (`BE`, `FE`, `DB`, `Redis`, `Setup`), each holding an `Entries` list of
`{ DisplayName, Path, Desc }`, rendered always-expanded and flattened by
`Show-GroupedMenu` (`modules/ProjectMenu.psm1`): group names print as
non-selectable headers, Up/Down skip over them so only actual scripts get
highlighted. On selection, the chosen script launches as a **separate child
`pwsh` process** (`& pwsh -NoProfile -ExecutionPolicy Bypass -File
$scriptPath`) rather than being dot-sourced — so a script's `exit` only ends
that script, and the menu always regains control afterward. Escape exits
`ztms.ps1`. Adding a new script means adding an entry to the right group's
`Entries` list in `ztms.ps1` (create a new group if it doesn't fit
`BE`/`FE`/`DB`/`Redis`/`Setup`) — it is not auto-discovered from the
filesystem. This also means environment variables set by one menu pick
(e.g. `901_set-env.ps1`) do **not** propagate to a script picked afterward
in the same `ztms` session; persisting at the user level
(`[System.Environment]::SetEnvironmentVariable($k, $v, "User")`) is the
workaround, offered interactively by `901_set-env.ps1`.

Similarly, `001_run-services.ps1`/`002_run-published.ps1` launch each
service in its own `cmd.exe /k` window (tagged with `[$processTag]` in the
window title), and `090_publish.ps1` launches each `dotnet publish` in its
own window — all via `Start-Process`, all fire-and-forget from the
script's perspective. `800_stop-services.ps1` finds and kills processes by
matching `processTag` against window titles (`cmd` windows) and command
lines (`dotnet.exe` processes via `Get-CimInstance Win32_Process`).

**Service discovery convention.** Scripts that operate on a service (run,
publish) resolve it as `<reposRoot>/<service.name>/src/*.Api/*.csproj` — the
repo folder name in config must match an actual folder directly under
`reposRoot`, and it must contain exactly a `src/<Name>.Api/` folder with a
`.csproj`. There's no other registration mechanism; a service missing that
folder shape is silently skipped with a warning, not an error.

**Numeric script prefixes are ordering hints for the menu / a mental model
of the workflow**, not a strict pipeline: `0xx` = day-to-day run scripts,
`09x` = publish, `8xx` = teardown, `9xx` = one-time setup. `db/` and
`redis/` scripts are grouped by concern rather than numbered.

**Cross-script state file.** `010_pull-all.ps1` writes
`.pull-changed.json` (which repos actually pulled new commits) next to the
scripts; `090_publish.ps1` reads it back to pre-check those services in its
selection menu, and trims consumed entries back out after publishing. This
is the only file-based handoff between scripts.

**DB clone pipeline (`db/clone-db-dev.ps1`)** is the most involved script:
it terminates local connections (delegates to `terminate-connections.ps1`),
`pg_dump`s each configured database from the dev host in parallel
(`ForEach-Object -Parallel`, `ThrottleLimit 8`), splits the schema into
pre-data (tables, no indexes) and post-data (indexes/constraints) sections,
then writes a worker script to disk and launches one `powershell` process
per database to drop/recreate/restore data first and build indexes last
(faster than restoring with indexes already present) — each worker runs in
its own visible window and writes a `.status` file so progress is visible
per-database. `db/restore-db-dev.ps1` reuses the last downloaded
`.dump`/`-schema-pre.sql`/`-schema-post.sql` files from `database.backupFolder`
and reruns just the terminate + worker-launch phases (same worker script,
same drop/recreate/pre-schema/data/post-schema order) — no dev connection,
no dev password, and it guards up front that all three files exist per
configured database before launching anything. `redis/clone-redis-dev.ps1`
is simpler: export RDB from dev
via `docker exec redis-cli --rdb`, copy out, stop the local container,
replace the volume's dump file, restart. `redis/restore-redis-dev.ps1` reuses
the last downloaded `dump-dev.rdb` from `redis.backupFolder` and replays just
the stop/replace/restart steps — no dev connection, no password needed —
for re-applying a backup without re-syncing from dev.

**Distribution mechanism.** `install.ps1` (meant to be run via
`irm <raw-github-url> | iex`) clones this repo and calls
`install-ztms.ps1`, which drops a one-line `ztms.cmd` shim into
`%LocalAppData%\Microsoft\WindowsApps` (a per-user PATH folder on Windows
10/11 — same mechanism winget/uv use, no admin/PATH edits needed) pointing
by absolute path at `ztms.ps1`. Because the shim is an absolute-path
pointer, updating is just `git pull` in the checkout (`902_update.ps1`,
also reachable from the menu) — no reinstall needed unless the repo is
moved.

## Working in this repo

- Any new script that reads config must `Import-Module` both shared modules
  and call `Get-TmsConfig` the same way existing scripts do — don't
  reimplement config loading or menu prompting inline.
- Guard clauses that print a specific message and `exit 1` when required
  config is missing (e.g. "No services configured.") are load-bearing for
  `smoke-test.ps1` — match that pattern (message text + exit code) for new
  scripts, and add a corresponding smoke-test case.
- Nothing sensitive belongs in `tms.config.json` — only paths, names,
  ports, hostnames. Passwords/secrets always come from user-level
  environment variables (via `Get-TmsSecret`) or `tms.env.local` (loaded by
  `901_set-env.ps1`), both gitignored.
- `db/drop-all.ps1` is destructive by design (drops configured local
  databases) — it already gates on `Confirm-Prompt -DefaultYes $false`;
  preserve that default when touching it.
