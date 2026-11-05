# Development guide

How to set up, sync, run and test Build a Dungeon, and the conventions the code and assets follow. Read [AGENTS.md](../AGENTS.md) for the build rules and [GDD.md](GDD.md) for the design.

## Tools

| Tool | Version | Why |
| --- | --- | --- |
| [Aftman](https://github.com/LPGhatguy/aftman) | any | Installs the pinned tools in `aftman.toml` |
| Rojo | 7.7.1 (`aftman.toml`) | Syncs `src/` into Studio. Install the matching Rojo Studio plugin |
| Python | 3.10+ | Runs the Luau spec runner |
| Luau CLI | optional | Runs specs headlessly. `aftman add luau-lang/luau` once (Aftman asks you to trust it). Without it, run specs in Studio (below) |

## First-time setup

1. Clone `https://github.com/LiamTheMo/RBLX-Build-a-Dungeon`.
2. Run `aftman install` in the repository.
3. Open the test place in Studio: **Build a Dungeon!**, place `78621805707922`. For offline work, any baseplate also works.
4. Run `rojo serve` in the repository, then click **Connect** in the Rojo plugin.
5. Press **Play**. The Output window should show no errors from `ServerScriptService.Server` or `StarterPlayerScripts.Client`. Until Phase 1 adds a plot, the "empty plot" is the default baseplate.

## What Rojo owns

| Owner | Contents | How it reaches the place |
| --- | --- | --- |
| Git, `src/shared` | Definitions, balance, rules and contracts shared by server and client → `ReplicatedStorage.Shared` | Rojo sync |
| Git, `src/server` | Services, server rules and persistence → `ServerScriptService.Server` | Rojo sync |
| Git, `src/client` | Controllers, HUD and UI → `StarterPlayer.StarterPlayerScripts.Client` | Rojo sync |
| Studio | Lighting, the baseplate, imported meshes and anything else not under `src/` | Saved and published from Studio |

Rojo mirrors the folders it maps: a module deleted in Git disappears from Studio on the next sync. Never edit synced scripts in Studio; those edits are overwritten.

## Running the specs

Pure-logic modules are checked by `tests/luau/*.spec.luau`. The runner was adapted from RBLX-Flintborn and bundles the modules with a small Roblox stand-in (`prelude.luau`).

- With the Luau CLI: `python tests/luau/run.py`.
- Without it: `python tests/luau/run.py --bundle definitions > bundle.luau`, then run the bundle's text in Studio's command bar. It prints one `ok` or `FAIL` line per test.

Add a spec for every new rules module. Gameplay that touches Instances, remotes or DataStores still needs a Studio playtest; follow [PLAYTEST_CHECKLIST.md](PLAYTEST_CHECKLIST.md).

## Code layout and naming

- **Entry points** load every ModuleScript in `src/server/Services` and `src/client/Controllers`, calling `Init()` on all of them and then `Start()` (`src/shared/Core/Loader.luau`). Adding a service means adding a file; nothing else changes.
- **Files and modules:** PascalCase. Services end in `Service` (`PlotService`), controllers in `Controller` (`BuildController`).
- **Shared definitions:** `src/shared/Definitions/` holds identities and rules (`Rooms`, `Visitors`, `Grid`). Every tunable number goes in `Balance.luau`, keyed by the same id.
- **Ids:** PascalCase strings (`SlimeNest`). Ids are saved in player profiles, so **never rename or reuse one**. Retire an id with a migration.
- **Pure rules:** game rules that need no Instances go in plain modules (in `src/shared` if the client also needs them, otherwise `src/server/Rules`), so specs can test them.
- **Remotes:** one contract module in `src/shared` names every remote and its argument shapes. The server validates every argument; see AGENTS.md.
- **Studio instances:** PascalCase names. Group per-plot instances under one model per plot.

## Assets and reuse

- Record every asset that is not made in this repository in the table below: where it came from, and whether it is cleared for release.
- Reusable code and art may come from other projects under `C:\Users\asus\Projects` (`RBLX-Flintborn`, the `Assets` library). Copy only what is needed, and never modify the source project.

| Item | Source | Status |
| --- | --- | --- |
| `src/shared/Core/Loader.luau` | RBLX-Flintborn, same owner | Copied unchanged |
| `tests/luau/prelude.luau` | RBLX-Flintborn, same owner | Copied unchanged |
| `tests/luau/run.py` | RBLX-Flintborn, same owner | Adapted: no JSON modules or refusal-code scan; added `--bundle` |

## Source control and issues

- `main` is always syncable and runnable. Do the work on short branches named after the phase and topic (`phase1/route-validation`), and merge them into `main` once their checks pass.
- Commit messages describe the change in the imperative ("Add route validation").
- Track bugs, design questions and playtest findings as GitHub Issues on the repository. Suggested labels: `phase-0` … `phase-11`, `bug`, `security`, `design`, `playtest`, `ui`. **Assumption:** GitHub Issues is the tracker; change this if the owner uses another.
- Never commit secrets, API keys, cookies or place files (`.gitignore` excludes `*.rbxl(x)` for this project).

## Publishing

The test place is published from Studio (**File → Publish to Roblox**) after syncing `main`. Running servers keep the old version until they restart, so test in a new server. Keep the test place private until a phase's playtest calls for outside testers.
