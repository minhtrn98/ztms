# ztms

A generalized, config-driven toolkit for running a multi-service .NET +
Postgres + Redis local dev environment — starting/stopping services,
publishing, pulling repos, and cloning data from a dev server. Not hardcoded
to any one machine's folder layout.

## Install

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

## Uninstall

```powershell
Remove-Item "$env:LocalAppData\Microsoft\WindowsApps\ztms.cmd"
```

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
| `db/terminate-connections.ps1` | Kill active local connections to configured databases |
| `db/drop-all.ps1` | **Destructive** — drops all configured local databases (asks to confirm) |
| `redis/clone-redis-dev.ps1` | Sync a Redis RDB dump from dev to the local docker container |

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
