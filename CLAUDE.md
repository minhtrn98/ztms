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
PowerShell 7+ (`pwsh`) scripts plus shared modules under `modules/`. All
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
`901_set-env.ps1` / `common/checkout-branch.ps1` (branch name + confirm) —
those need manual verification against a real setup before a release. When
adding a new script or changing a guard clause, add a corresponding
`Test-Step`/`Invoke-Guarded` case in `smoke-test.ps1` following the existing
pattern.

## Architecture

**Config flows one way, through shared modules.** `tms.config.json`
(gitignored, created by `900_init-config.ps1`, schema documented in
`tms.config.example.json`) is the single source of machine-specific truth —
`reposRoot`, `deployRoot`, `processTag`, `services[]` (name/port/enabled),
`pullIgnoreFolders`, `database.*`, `redis.*`, `frontend.*`, `android.*`.
Every numbered script starts with:

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
  headers — what `ztms.ps1` itself uses; the plain menu has **no search**
  (deliberately — Up/Down, 1–9 group jump, Enter, Esc). `-SearchOnly` (the
  hotkey window only) replaces the list with a search box: the terminal's
  real blinking caret after the query, best-first results via
  `Find-MenuEntries` (each entry's `Desc` feeds the search only — it's
  deliberately not shown), Backspace/Ctrl+Backspace(=Ctrl+W), Escape clears
  the query before it quits), `Confirm-Prompt` (y/N prompt).
  Every row is cut to the window width — a wrapped row shifts every row
  below it and breaks the in-place redraw.
  These have a specific ConPTY quirk workaround — see the comment above
  `Draw-Menu` in each function before changing cursor-position
  logic; Windows Terminal / VS Code's integrated terminal both report
  `BufferHeight == WindowHeight`, so rows must be reserved (blank lines
  written) before capturing `$top`, or Up/Down redraws break once the menu
  is taller than the visible window.
- `modules/MenuSearch.psm1` — `Find-MenuEntries -Groups -Query`, the
  offline "semantic" search behind the menu's type-to-search and
  `ztms <unknown target>`'s "Did you mean" list. Text is lowercased and
  accent-stripped (`ConvertTo-MenuSearchText`, so Vietnamese works with or
  without accents); query words are expanded through `$script:Concepts`
  (one `|`-separated synonym group per line, English + Vietnamese, greedy
  multi-word phrases like "khởi động lại") and scored against DisplayName
  (×3), group name (×2), Desc and Path (×1), synonyms at ×0.7. Entries must
  match every term; if none do, the ones matching the most terms come back
  flagged `Partial`. Typed words also prefix-match (narrowing while you
  type); synonyms only match whole words or inflections, so "check" doesn't
  hit "checkout". No model or network — keep it that way so it stays instant
  on every keystroke. The smoke test pins expected top results for a few
  queries; re-run it after touching concepts or Descs.
- `modules/Android.psm1` — Android emulator helpers built on top of
  `config.android.emulatorPath` (no separate config for `adb.exe`; it's
  derived as `<emulatorPath>/../platform-tools/adb.exe`, falling back to a
  bare `adb` on PATH): `Get-TmsAndroidEmulatorExe`/`Get-TmsAndroidAdbExe`
  resolve and guard-check the exes, `Get-TmsAndroidAvds` shells out to
  `emulator -list-avds`, and `Select-TmsAvd` wraps that with the
  `Show-Menu` picker (from `ProjectMenu.psm1`, which callers must also
  import) — shared by `android/start*.ps1` and `android/stop.ps1`.
  `Get-TmsAndroidDeployConfig` guard-checks `config.android.deploy.<env>`
  (`apiUrl`/`apiKey`/`appId`/`userActionId` per environment, e.g. `dev`/
  `stg` — each is a different host, AppId, and UserActionId against the
  internal deploy API; `apiKey`/`userActionId` here are identifiers the API
  expects in its request body, not login secrets, so they aren't routed
  through `Get-TmsSecret`). `Get-TmsAndroidRunningDevices`/
  `Select-TmsRunningAndroidDevice` resolve currently-running emulator
  serials to their AVD names via `adb devices` + `adb emu avd name`.
  `Invoke-TmsAndroidInstallLatest -Config -Environment` is the shared
  orchestrator behind `android/install-latest-dev.ps1` and
  `android/install-latest-stg.ps1` (each a thin wrapper naming its
  environment): it calls that environment's deploy API — dev's
  `GetAppInfoById` nests results under `.Data.Versions`, stg's
  `GetAppHistoryById` returns `.Versions` at the top level alongside an
  `IsError`/`ErrorMessage` pair, both handled — picks the newest
  `DEPLOY`-status version by `StartTime`, downloads the APK, `adb push`es +
  `pm install -r`s it onto the picked device, then deletes both the device
  and local copies.

- `modules/TmsConfig.psm1` also owns the **env var inventory**:
  `Get-TmsUserEnvVars -Config` derives every user-level env var ztms reads
  from config (every `database.*PasswordEnvVar`/`redis.*PasswordEnvVar`,
  `pms.dev.passwordEnvVar`) plus every key in `tms.env.local`
  (`Read-TmsEnvFile`). `setup/doctor.ps1`, `setup/export.ps1` and
  `setup/import.ps1` all go through it — when adding a new secret, add it as
  a `*PasswordEnvVar` config key (or a `tms.env.local` key) rather than
  reading a hardcoded env var name, or those three won't know about it.
- `modules/Backup.psm1` — `Protect-TmsBackup`/`Unprotect-TmsBackup`: the
  `.ztmsbak` format used by export/import ("ZTMS1" magic + salt + nonce +
  tag + AES-256-GCM ciphertext, PBKDF2-SHA256 600k key). Passphrase-based so
  it's portable across machines (DPAPI wouldn't be).
- `modules/HttpToolkit.psm1` — drives a custom HTTP Toolkit UI fork whose
  own `scripts\release.ps1` (exposed as `htk` via `scripts\htk.cmd`) does
  build/deploy/start/stop. ztms runs that `release.ps1` straight from
  `httptoolkit.repoPath` (not via PATH), and the whole HTTPTOOLKIT group is
  hidden unless `repoPath` is set. `Install-TmsHttpToolkit` clones/checks out
  `httptoolkit.branch` (never forcing over a dirty tree), adds
  `<repo>\scripts` to the user PATH via `Add-TmsUserPath` — which writes the
  registry value as REG_EXPAND_SZ directly and broadcasts WM_SETTINGCHANGE,
  because `Environment.SetEnvironmentVariable` would rewrite PATH as REG_SZ
  and break `%VAR%` entries — then runs `htk build`.
- `modules/Pms.psm1` — PMS desktop app helpers behind `pms/*.ps1`. The app
  updates itself into a new `<pms.dev.root>\<x.y.z>` folder per version, so
  everything resolves the newest folder containing `PMS.exe` at run time
  (`Get-TmsPmsLatestInstalled`). `Invoke-TmsPmsUpdate` mirrors the app's
  updater (`GetLastVersion` API → zip → unzip), staging to `.part`/`.partial`
  and renaming so a half-written build is never picked, guarded by a named
  mutex so the every-minute scheduled task and a manual run can't collide;
  it toasts via Windows PowerShell 5.1 (pwsh 7 can't load WinRT) and only
  re-toasts an error after a successful run. `Start-TmsPmsLatest` spawns a
  hidden pwsh running `Invoke-TmsPmsLoginAutofill` (skipped if PMS is
  already running — the app is single-instance), which waits for the login
  form and types the password with SendKeys. PMS exposes no control names to
  UI Automation and UIA `SetFocus` is refused on its Janus password box, so
  the box is found by `EM_GETPASSWORDCHAR` and reached with Tab from the
  username box. `Install-TmsPmsDev` creates the
  desktop shortcut via a temp `.lnk` in `$env:PUBLIC` because
  `WScript.Shell` can't save to a non-ASCII path (e.g. a Vietnamese username
  in the Desktop path).
- `modules/Hotkey.psm1` — Spotlight-style global hotkey (`hotkey.keys`,
  default `Ctrl+Space`) behind `setup/install-hotkey.ps1`/
  `uninstall-hotkey.ps1`. `Install-TmsHotkey` registers a "ztms Hotkey"
  scheduled task (at logon, `conhost --headless`, no time limit) running
  `setup/hotkey-listener.ps1`, which `RegisterHotKey`s on its own thread and
  blocks in `GetMessage`. Each press toggles the window it opened (focus /
  minimize), or opens a new `wt -w new` window running `ztms.ps1` if that's
  gone — launched as `ztms.ps1 --spotlight`: `Show-GroupedMenu -SearchOnly`
  (search line + as many results as fit, no grouped list, no header) in a
  window `hotkey.searchHeightPercent` tall; ztms.ps1 itself grows it to
  `heightPercent` before running a picked script and shrinks it back after
  (`Set-TmsSpotlightWindowSize` resizes the foreground window, i.e. itself,
  on its own monitor; Hotkey.psm1 is imported only at that point so its
  `Add-Type` compile doesn't delay the search box). It then waits until
  `[Console]::WindowHeight` actually changes — the resize reaches the
  console asynchronously, and redrawing before it lands lays the menu out
  for the old height, so after a shrink the search line scrolls off the top. The window is tracked by **handle** (the terminal window that
  appears after launch), not by title — Windows Terminal with
  `showTerminalTitleInTitlebar: false` titles every window "Terminal".
  It's launched as `wt -w new --focus`: focus mode hides the tab row and
  title bar (the Spotlight look, at no cost), and — unlike every other way
  of launching wt — it overrides the user's global `launchMode`, so a
  `maximized` setting doesn't apply (wt ignores the launch show-state, and
  `--size`/`--pos` don't beat `launchMode`). Side effect: tab titles aren't
  in the UI Automation tree, so identify the window by handle, not tab name.
  It runs with `-p` the hidden "ztms (hotkey)" profile that
  `Set-TmsHotkeyWtProfile` writes into the user's WT `settings.json` (fixed
  GUID; a copy of their default profile's look + `hotkey.fontSize`/
  `padding`/`opacity`/`acrylic` — opacity and useAcrylic are always written
  explicitly, since defaults may hold e.g. opacity 0 + acrylic, which is
  invisible without acrylic and solid when Windows transparency effects are
  off; one-time `settings.json.ztms-backup`; removed by uninstall). It
  must be in `settings.json`, not a JSON fragment: the user's
  `profiles.defaults` outrank fragment profiles, so a fragment can set
  padding but not a font size or color scheme that defaults already set.
  Editing goes through `Update-TmsWtSettings` (ConvertFrom-Json -AsHashtable
  keeps key order; WT reloads on the write by itself).
  `WaitForNewWindow` busy-polls from before launch, catches the window while
  wt still has it hidden (~100ms before it's shown) and `SetWindowPos`es it
  (no `SWP_SHOWWINDOW`) to `hotkey.widthPercent`/`searchHeightPercent` of the
  work area of the monitor under the cursor (per-monitor-DPI-aware pixels),
  so it first appears already in place; if it's shown maximized anyway
  (non-focus launch), it's re-placed with one `SetWindowPlacement` the
  instant it's visible (~5ms maximized). Polling with sleeps, or restore +
  `SetWindowPos` as two calls, brings back a visible flash.
  `Activate` falls back to `AttachThreadInput` because a plain
  `SetForegroundWindow` from the background listener is intermittently
  refused. Install waits until the hotkey is actually taken (the listener
  needs a moment for `Add-Type`) before reporting success. Errors from the
  headless listener go to `%TEMP%\ztms-hotkey.log`.

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
filesystem. Give it a `Desc` (a short English sentence with the words
people would search for): search matches on it, and the smoke test fails
on an entry without one. Entries may also carry `Args` (passed to the
script) and `Quick` (hotkey window: run in the small window and, on
success, go straight back to an empty search box — the window stays open —
instead of growing it + "press any key"). Config `hiddenMenuItems` only
trims the plain menu — with `--spotlight` it's ignored (search only shows
what you type for), while the automatic hides of unconfigured features
(httptoolkit/pms/install-latest) apply to both. With
`--spotlight`, ztms.ps1 appends generated "VS CODE" and "VISUAL STUDIO"
groups — one Quick entry per configured service whose repo folder exists,
running `common/open-vscode.ps1` / `common/open-vs.ps1 -Service <name>` —
so "order code" / "order vs" open that repo directly; they're not in the
plain menu (rows per service). `open-vs.ps1` opens the repo's `.sln`/`.slnx`
directly via its file association — deliberately not the repos'
`<Name>.sln.bat` wrappers; it picks the file by extension, not `-Filter
*.sln` (the 8.3 wildcard quirk also matches `.sln.bat`). MenuSearch reads a lone "vs" as "visual studio" — "vs
code" (or "vs c…" mid-typing) stays VS Code. This also means environment variables set by one menu pick
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

**`common/checkout-branch.ps1`** is `pull-all.ps1`'s sibling for switching
branches instead of pulling: same `reposRoot`/`pullIgnoreFolders`-derived
repo list and `ForEach-Object -Parallel` shape, but it prompts (`Read-Host`)
for a branch name typed once and applied to every repo, `git fetch`s each
repo before checkout so a remote-only branch resolves to a new local
tracking branch, and reports per-repo success/failure rather than aborting
the batch on the first miss (a repo without that branch, or one further
along in a rename/typo, just shows up as a FAILED line). It never force-
checks-out — a dirty repo whose local changes would be overwritten is left
alone and reported as failed rather than losing work.

**DB clone pipeline** is the most involved, and — like android's
install-latest and redis's clone/restore — is built as thin per-environment
wrappers (`db/clone-db-dev.ps1`/`db/clone-db-stg.ps1`,
`db/restore-db-dev.ps1`/`db/restore-db-stg.ps1`) around shared functions in
`modules/Db.psm1`. `Invoke-TmsDbClone -Config -Environment -ScriptsRoot`
terminates local connections (delegates to `terminate-connections.ps1`,
resolved via `-ScriptsRoot` since the module itself lives in `modules/`),
`pg_dump`s each configured database from `database.<env>Host/User/
PasswordEnvVar` (e.g. `devHost`/`stgHost`) in parallel (`ForEach-Object
-Parallel`, `ThrottleLimit 8`), splits the schema into pre-data (tables, no
indexes) and post-data (indexes/constraints) sections, then hands off to
`Invoke-TmsDbLaunchRestoreWorkers`, which writes `db_clone_worker.ps1` to
disk (via `Write-TmsDbWorkerScript` — gitignored, regenerated every run) and
launches one `powershell` process per database to drop/recreate/restore
data first and build indexes last (faster than restoring with indexes
already present) — each worker runs in its own visible window and writes a
`.status` file so progress is visible per-database. `Invoke-TmsDbRestore
-Config -Environment -ScriptsRoot` reuses the last downloaded
`.dump`/`-schema-pre.sql`/`-schema-post.sql` files from
`database.backupFolder` and reruns just the terminate + worker-launch
phases (same worker script, same drop/recreate/pre-schema/data/post-schema
order) — no remote connection, no remote password, and it guards up front
that all three files exist per configured database before launching
anything. Backup/schema/log/status file names for `dev` stay suffix-free
(unchanged from before per-environment support existed, so existing dev
backups keep working); every other environment's files get a
`-<environment>` suffix (`Get-TmsDbFileSuffix`) so they never collide with
dev's in the same `backupFolder`. Redis clone/restore follows the identical
shape but is simpler — two shared functions in `modules/Redis.psm1`:
`Invoke-TmsRedisClone -Config -Environment` exports an RDB from the remote
(`redis.<env>Host/Port/PasswordEnvVar`) via `docker exec redis-cli --rdb`,
copies it out, stops the local container, replaces the volume's dump file,
and restarts; `Invoke-TmsRedisRestore -Config -Environment` reuses the last
downloaded `dump-<env>.rdb` from `redis.backupFolder` and replays just the
stop/replace/restart steps — no remote connection, no password needed — for
re-applying a backup without re-syncing.

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
