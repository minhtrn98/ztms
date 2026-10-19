# ztms

A generalized, config-driven toolkit for running a multi-service .NET +
Postgres + Redis local dev environment — starting/stopping services,
publishing, pulling repos, and cloning data from a dev server. Not hardcoded
to any one machine's folder layout.

## Install

> Setting up a new machine (or moving from an old one)? See the step-by-step
> guide in [SETUP.md](SETUP.md) (Vietnamese).

Requires [git](https://git-scm.com/downloads) and
[PowerShell 7+](https://aka.ms/powershell). From any terminal (cmd.exe,
PowerShell, or pwsh):

```powershell
irm https://raw.githubusercontent.com/minhtrn98/ztms/master/install.ps1 | iex
```

This clones the repo locally and installs a global `ztms` command. Open a
**new** terminal, anywhere, and type `ztms` — it lists every script below and
runs whichever you pick, then returns to the menu.

Prefer to set it up by hand? Clone the repo yourself, then run
`.\install-ztms.ps1` — see "Global `ztms` command" below for what that does.

## Setup

1. Run the interactive wizard once, from anywhere, to generate your local config:

   ```powershell
   .\900_init-config.ps1
   ```

   This writes `tms.config.json` next to the scripts — **not committed to
   git** (see `.gitignore`). It asks for your repos root, deploy root,
   service list/ports, and DB/Redis connection info. Re-run it any time to
   regenerate, or hand-edit the JSON afterward.

2. Set secrets as **Windows user environment variables** (never stored in
   the config file):

   | Variable | Used by |
   |---|---|
   | `DEV_DB_PASSWORD` | `db/clone-db-dev.ps1` |
   | `DEV_REDIS_PW` | `redis/clone-redis-dev.ps1` |
   | `TMS_LOCAL_DB_PASSWORD` | db scripts, local Postgres (defaults to `postgres` if unset — override only if you changed your local docker password) |

   Any script that needs one of these will prompt for it (hidden input) if
   it isn't set, so setting them ahead of time is a convenience, not a
   requirement.

3. If your services need runtime config (JWT signing key, Redis/Kafka/RabbitMq
   connection info, third-party API keys, cross-service URLs), copy the
   template and fill in real values:

   ```powershell
   copy tms.env.example tms.env.local
   # edit tms.env.local with real values
   .\901_set-env.ps1
   ```

   `tms.env.local` is gitignored. `901_set-env.ps1` loads it into the
   **current terminal session** (so run it before `001_run-services.ps1` /
   `002_run-published.ps1` in that same window) and offers to also persist
   the values at the Windows user level so new terminals get them without
   re-running the script.

4. (Optional) Install the global `ztms` command so you can open any terminal
   (cmd.exe, PowerShell, or pwsh), from any directory, and just type `ztms`:

   ```powershell
   .\install-ztms.ps1
   ```

   This drops a small `ztms.cmd` shim into
   `%LocalAppData%\Microsoft\WindowsApps` — a per-user folder that's on PATH
   by default on Windows 10/11 (the same mechanism winget/uv use), so it
   needs no admin rights and no PATH edits. Open a **new** terminal and run
   `ztms` — it lists every script below and runs whichever you pick, then
   returns to the menu. Each pick runs as its own process, so cancelling or
   hitting a "not configured" guard clause in one script never kills the
   menu. To uninstall, just delete that one file.

   Because each menu pick is a separate process, env vars loaded by
   `901_set-env.ps1` from inside the menu don't carry over to a different
   script picked afterward in the same `ztms` session — persist them at the
   user level when `901_set-env.ps1` asks, or run `901_set-env.ps1` then the
   target script directly (not through `ztms`) in the same terminal when you
   need that.

## Check / move a setup (doctor, export, import)

Not sure what this machine still needs? Run **SETUP > doctor** — it lists
every tool the configured features need (git, dotnet, psql/pg_dump, docker,
node/yarn, ...), checks the folders in `tms.config.json`, and every
user-level env var ztms reads (derived from the config's `*PasswordEnvVar`
keys, `pms.dev.passwordEnvVar`, and every key in `tms.env.local` — including
whether `tms.env.local` values were persisted or are out of date).
Read-only; exits 1 only on a FAIL.

To set up a second machine with the same config and secrets:

1. On the old machine: **SETUP > export** → one `.ztmsbak` file containing
   `tms.config.json`, `tms.env.local`, and the values of those env vars,
   encrypted with a passphrase you choose (AES-256-GCM, PBKDF2 key). It holds
   secrets — move it by USB/private share, never git/chat, and delete it after.
2. On the new machine: install ztms (see Install), then **SETUP > import** →
   asks for the passphrase, lets you adjust machine-specific paths
   (`reposRoot`, `deployRoot`, ...), writes both files (keeping `*.bak` of any
   existing ones), sets the env vars, then runs doctor.
3. If PMS is configured: **PMS > [dev] install**.

## Custom HTTP Toolkit (optional)

The HTTPTOOLKIT menu group drives a custom fork of the HTTP Toolkit UI
(`scripts\release.ps1` / `htk` in the fork) and only shows once
`httptoolkit.repoPath` is configured.

| Menu | What it does |
|---|---|
| HTTPTOOLKIT > install | Clones `httptoolkit.gitUrl` into `repoPath` if needed, checks out `httptoolkit.branch` (or fast-forwards it; never forces over local changes), adds `<repo>\scripts` to the user PATH so `htk` works anywhere, then `htk build`. Re-run to update. Needs Node.js >= 20 |
| HTTPTOOLKIT > build | `htk build` — rebuild, redeploy, restart after code changes |
| HTTPTOOLKIT > start / stop / restart | `htk start` / `stop` / `restart` |

## PMS desktop app (optional)

The PMS app updates itself into a new `<pms.dev.root>\<version>` folder per
release, which breaks fixed shortcuts. With `pms.dev` configured:

| Menu | What it does |
|---|---|
| PMS > [dev] install | Downloads the latest build if none, creates a "PMS Dev" desktop shortcut that always opens the newest build, and registers a "PMS Dev Auto Update" scheduled task (every minute, headless). Re-run safely. |
| PMS > [dev] start | Opens the newest build and copies the login password (`pms.dev.passwordEnvVar` user env var) to the clipboard |
| PMS > [dev] update | Downloads + unzips the latest build now; toasts on install/error; keeps the 2 newest version folders |

## Searching

The hotkey window (see "Global hotkey" below) is a search box: type and the
best matches by name, group and description show up, so you don't need to
know the exact script name. (The regular `ztms` menu has no search — it's
the grouped list with Up/Down and 1–9.) It understands synonyms in English and Vietnamese, accents optional —
e.g. `tắt service` → BACKEND stop-all, `kéo db dev` → DATABASE [dev]
clone-restore, `toa do buu cuc` → ANDROID set-location. Each configured
service also gets a "VS CODE" and a "VISUAL STUDIO" entry there: `order
code`, `vs code order` or `order vs code` → Enter opens the TMS.OrderService
repo in VS Code; `order vs`, `order visual studio` or `order sln` → its
solution in Visual Studio (through the repo's `<Name>.sln.bat` when it has
one, so the dev env vars from `config.bat` apply; else the `.sln`). Either
way it opens right away (no picker) and you're back at an empty search box.
A lone `vs` means Visual Studio; `vs code` means VS Code. Up/Down + Enter to
run, Backspace (Ctrl+Backspace for a whole word) to edit, Esc clears the
search (Esc again closes it).

The same search runs for `ztms <words>` when the words aren't an exact
script name: it prints "Did you mean" with the top matches.

## Global hotkey (optional)

Spotlight-style: press **Ctrl+Space** anywhere in Windows to open a ztms
search box in its own Windows Terminal window (short, centered on the
screen under the mouse, no tab row or title bar — Windows Terminal's focus
mode) — no full menu, just type what you
want to do (see "Searching") and Enter. The window grows while the
script runs and shrinks back to the search box afterwards. Press the hotkey
again to hide it (minimize), again to bring it back; Escape closes it.

| Menu | What it does |
|---|---|
| SETUP > install-hotkey | Registers a "ztms Hotkey" scheduled task that starts a headless listener at logon, and starts it now. Re-run after changing `hotkey.keys`. |
| SETUP > uninstall-hotkey | Stops the listener, removes the task and the Windows Terminal profile |

install-hotkey also adds one hidden profile, "ztms (hotkey)", to your Windows
Terminal `settings.json` — a copy of your default profile's look with a
bigger font and more padding, used only by the hotkey window. (It has to live
in `settings.json`: your `profiles.defaults` would override the font size of
anything else.) Your settings from before ztms first touched them are kept
as `settings.json.ztms-backup` next to it.

The hotkey is global, so it takes Ctrl+Space away from every other app
(e.g. VS Code's "trigger suggest"). Pick another combo with `hotkey.keys`
in `tms.config.json` (e.g. `"Ctrl+Alt+Space"`, `"Win+Shift+Z"`). Listener
errors go to `%TEMP%\ztms-hotkey.log`.

## Uninstall

```powershell
Remove-Item "$env:LocalAppData\Microsoft\WindowsApps\ztms.cmd"
```

(If you installed the global hotkey, run **SETUP > uninstall-hotkey** first —
it removes the "ztms Hotkey" scheduled task.)

That's the only thing `install-ztms.ps1` puts outside this repo — deleting
it removes the global `ztms` command (open a new terminal to confirm it's
gone). To remove the scripts entirely, also delete the folder you cloned
into — note `tms.config.json` and `tms.env.local` live there too, and
aren't recoverable once deleted (they're gitignored, never pushed anywhere).

## Updating

`ztms.cmd` points at `ztms.ps1` by absolute path — it doesn't copy anything.
So pulling the latest scripts is enough; no reinstall needed:

```powershell
git pull
```

...or just pick **"Update these scripts (git pull)"** from the `ztms` menu
itself (`902_update.ps1`). Only re-run `install-ztms.ps1` if you move this
repo to a different path.

## Scripts

| Script | Purpose |
|---|---|
| `ztms.ps1` | Interactive menu listing every script below — run directly or via the global `ztms` command |
| `install.ps1` | Bootstrap installer (clone + install-ztms.ps1) — see Install above |
| `install-ztms.ps1` | Installs the global `ztms` command (see step 4 above) |
| `902_update.ps1` | `git pull` this repo |
| `900_init-config.ps1` | Interactive setup — creates/updates `tms.config.json` |
| `901_set-env.ps1` | Load `tms.env.local` into the session (+ optionally persist at user level) |
| `001_run-services.ps1` | `dotnet run` selected services (dev mode) |
| `002_run-published.ps1` | Run selected services from `dotnet publish` output |
| `003_run-frontend.ps1` | Build (optional) and run the frontend — blocks in this terminal, not a new window |
| `010_pull-all.ps1` | Parallel `git pull` across all repos under `reposRoot` |
| `090_publish.ps1` | `dotnet publish` selected services to `deployRoot` |
| `800_stop-services.ps1` | Stop all processes tagged with `processTag` |
| `db/clone-db-dev.ps1` | Clone configured Postgres databases from a dev server to local |
| `db/restore-db-dev.ps1` | Re-apply the last downloaded dumps (no dev connection) onto local Postgres |
| `db/terminate-connections.ps1` | Kill active local connections to configured databases |
| `db/drop-all.ps1` | **Destructive** — drops all configured local databases (asks to confirm) |
| `redis/clone-redis-dev.ps1` | Sync a Redis RDB dump from dev to the local docker container |
| `redis/restore-redis-dev.ps1` | Re-apply the last downloaded dump (no dev connection) to the local docker container |

All scripts assume they're run with your services' `reposRoot` as the
working directory, e.g.:

```powershell
.\010_pull-all.ps1
```

## Config reference (`tms.config.json`)

| Field | Meaning |
|---|---|
| `reposRoot` | Folder containing your service repos as direct subfolders |
| `deployRoot` | Folder `dotnet publish` output goes to / is run from |
| `processTag` | String used to tag/find windows & processes started by these scripts (shown in window titles, matched by `800_stop-services.ps1`) |
| `services[]` | `{ name, port, enabled }` — repo folder name (must contain `src/<Name>.Api/*.csproj`) and the port to run it on. `enabled: false` keeps a service configured (still publishable, still listed) but unchecked by default in `001_run-services.ps1`/`002_run-published.ps1`'s selection menu — useful for services you rarely run locally. `090_publish.ps1` always offers every configured service regardless of `enabled`. Omitting the field defaults to enabled. |
| `pullIgnoreFolders` | Folder names under `reposRoot` to skip in `010_pull-all.ps1` |
| `database.*` | Local/dev Postgres connection info + list of database names to manage |
| `database.excludeTableDataPattern` | Optional `pg_dump --exclude-table-data` pattern (e.g. a job-scheduler table like `qrtz_*`) to skip row data for during clone |
| `redis.*` | Dev Redis host/port + local docker container/volume names |
| `frontend.*` | `{ path, buildCommand, startCommand }` for `003_run-frontend.ps1` — `path` is absolute or relative to `reposRoot`; `buildCommand` is optional (skipped if blank), `startCommand` is required |
| `httptoolkit.*` | Optional `{ repoPath, gitUrl, branch, deployDir }` for the HTTPTOOLKIT menu group — `repoPath` is an existing clone or where to clone `gitUrl`; `branch` is checked out by install; `deployDir` (optional) is persisted as `HTK_DEPLOY_DIR`. Entries are hidden when `repoPath` is blank |
| `pms.dev.*` | Optional `{ root, updateUrl, product, passwordEnvVar }` for the PMS menu group — `root` is the PMS install folder (e.g. `D:\PMS\PMSDev`), `updateUrl` the update server (the `NewUpdateUrl` in `PMSSetup.exe.config`), `product` defaults to `PMSx64`. PMS entries are hidden when `root` is blank |
| `hotkey.keys` | Optional global hotkey for SETUP > install-hotkey, e.g. `"Ctrl+Space"` (default when missing), `"Ctrl+Alt+Z"`, `"Win+Shift+F1"` — modifiers `Ctrl`/`Alt`/`Shift`/`Win` plus one key; at least one modifier required |
| `hotkey.widthPercent` / `hotkey.heightPercent` / `hotkey.searchHeightPercent` | Optional size of the hotkey's ztms window as a percentage of the screen's work area, clamped to 20–100: width (default `50`), height while a script runs (`80`), and height of the search box it opens as (`35`).
| `hotkey.fontSize` / `hotkey.padding` | Optional font size (default `14`, clamped 6–48) and padding in px (default `16`, 0–64) of the hotkey window's Windows Terminal profile. Re-run SETUP > install-hotkey after changing them |
| `hotkey.opacity` / `hotkey.acrylic` | Optional background opacity of the hotkey window in % (default `85` — see-through; `100` = solid) and whether to blur what's behind it (`acrylic`, default `false`; needs Windows Settings > Personalization > Colors > *Transparency effects* on, otherwise the background shows solid). Re-run SETUP > install-hotkey after changing them | The window is always centered on the screen under the mouse and never maximized, whatever Windows Terminal's `launchMode` says |
| `hiddenMenuItems` | Optional array of script paths (e.g. `"backend/run.ps1"`, matched against each menu entry's `Path`, `\`/`/` and case insensitive) to hide from the `ztms` menu — the scripts still exist and run directly, they're just left off the picker |

Nothing sensitive belongs in this file — only paths, names, ports, and
hostnames. Passwords always come from environment variables or an
interactive prompt (see Setup above).

## Testing before packaging

```powershell
.\tests\smoke-test.ps1
```

Runs entirely against an isolated temp copy with a synthetic, intentionally
incomplete config — checks that every script parses cleanly and that each
one's guard clauses (missing services/databases/devHost) fail gracefully,
without touching your real Docker/dotnet/Postgres/Redis. It does **not**
replace actually running a service, cloning a real DB, or exercising the
interactive prompts in `900_init-config.ps1` / `901_set-env.ps1` — do that
manually, once, against your real setup before a release.
