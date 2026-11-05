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
5. Press **Play**. The Output window should show no errors from `ServerScriptService.Server` or `StarterPlayerScripts.Client`. The server creates `Workspace.Plots` with one plot per slot (`Balance.Server.MaxPlots`, 6) and assigns you one.

## What Rojo owns

| Owner | Contents | How it reaches the place |
| --- | --- | --- |
| Git, `src/shared` | Definitions, balance, rules and contracts shared by server and client → `ReplicatedStorage.Shared` | Rojo sync |
| Git, `src/server` | Services, server rules and persistence → `ServerScriptService.Server` | Rojo sync |
| Git, `src/client` | Controllers, HUD and UI → `StarterPlayer.StarterPlayerScripts.Client` | Rojo sync |
| Studio | Lighting, the baseplate, `ReplicatedStorage.Art` (room, character and prop models), `Workspace.Map` and anything else not under `src/` | Saved and published from Studio. Rojo does not sync these, so they exist only in the place file |

Rojo mirrors the folders it maps: a module deleted in Git disappears from Studio on the next sync. Never edit synced scripts in Studio; those edits are overwritten.

## Running the specs

Pure-logic modules are checked by the 17 `tests/luau/*.spec.luau` files. The runner was adapted from RBLX-Flintborn. It bundles each spec with the game modules and a small Roblox stand-in (`prelude.luau`).

- **With the Luau CLI:** `python tests/luau/run.py` runs every spec and prints a summary.
- **In Studio (no CLI needed):**
  1. `python tests/luau/run.py --studio` writes one bundle per spec, plus `index.txt`, to `build/specs/` (git-ignored).
  2. Serve that folder on localhost, and keep the server running:
     `cd build/specs && python -m http.server 8765 --bind 127.0.0.1`.
     Do not use `--directory`: it returned HTTP 501 on Python 3.15 here.
  3. Paste the contents of `tests/luau/studio_runner.luau` into Studio's command bar and run it. The runner fetches each bundle from `http://127.0.0.1:8765/` with `HttpService:GetAsync`, so HTTP requests must be enabled for the place (Game Settings → Security). It changes nothing in the place. It prints one line per spec file and full detail only for failures. To run a subset, edit the pasted copy's `FILTER` to a spec-name prefix.
- **Single bundle:** `python tests/luau/run.py --bundle definitions` prints one spec's bundle to stdout.

Studio playtests save to a separate DataStore, `PlayerProfiles_v1_Studio`, so test progress never touches live profiles (`src/server/Services/ProfileService.luau`). If Studio cannot reach DataStores, the game uses an in-memory store and nothing is saved.

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
- **All art, icons, mockups, sounds and model exports** live in `C:\Users\asus\Projects\Assets\BuildADungeon\`, not in this repo. Its `README.md` lists every model, icon and sound with its source and status. Model exports are `models\<Name>.rbxmx`; the Studio copies are under `ReplicatedStorage.Art` and `Workspace.Map`.
- Studio-built art (`ReplicatedStorage.Art`, `Workspace.Map`) is owned by the place file. Save and publish the place from Studio to keep it. If it is lost, re-import the `.rbxmx` files; re-check weld and Motor6D offsets after import (per the Assets README).

| Item | Source | Status |
| --- | --- | --- |
| Room, character, prop and map models (`Art.*`, `Workspace.Map`) | Built for this game from Parts in Studio; exported to `Assets\BuildADungeon\models\` | Original, per the Assets README. Cleared for use as stated there |
| UI icons (`src/shared/UI/IconIds.luau`) | Cut from a ChatGPT-generated sheet (owner's account), `ui\mockups\05_icon_sheet_magenta.png` | **Rights to be confirmed by the owner before release** |
| Sounds (`src/shared/UI/SoundIds.luau`) | Creator Store audio, chosen from search metadata only, not listened to. Listed in the Assets README | **Each needs listening and a licence check before release.** Theft, SlimeAttack, Ambience and Music have no sound yet |
| UI mockups and reference images | ChatGPT-generated (owner's account), in `ui\mockups\` and `reference\` | Concept and reference only; not cleared; never uploaded to Roblox |
| `src/shared/Core/Loader.luau` | RBLX-Flintborn, same owner | Copied unchanged |
| `src/shared/Core/Signal.luau` | RBLX-Flintborn, same owner | Copied unchanged |
| `tests/luau/prelude.luau` | RBLX-Flintborn, same owner | Copied unchanged |
| `tests/luau/run.py` | RBLX-Flintborn, same owner | Adapted: no JSON modules or refusal-code scan; added `--bundle` and `--studio` |
| `tests/luau/studio_runner.luau` | Written for this repo (Flintborn has no Studio runner) | Not from another project |
| `src/server/Infrastructure/DataStoreGateway.luau`, `ProfileStore.luau` | RBLX-Flintborn persistence pattern, same owner | Adapted: not copied verbatim |
| `src/server/Rules/SessionLease.luau` | RBLX-Flintborn `Rules/Data/SessionLease`, same owner | Adapted |
| `src/server/Infrastructure/RemoteGuard.luau` | RBLX-Flintborn `Rules/Net/RemoteGuard`, same owner | Adapted |

## Source control and issues

- `main` is always syncable and runnable. Do the work on short branches named after the phase and topic (`phase1/route-validation`), and merge them into `main` once their checks pass.
- Commit messages describe the change in the imperative ("Add route validation").
- Track bugs, design questions and playtest findings as GitHub Issues on the repository. Suggested labels: `phase-0` … `phase-11`, `bug`, `security`, `design`, `playtest`, `ui`. **Assumption:** GitHub Issues is the tracker; change this if the owner uses another.
- Never commit secrets, API keys, cookies or place files (`.gitignore` excludes `*.rbxl(x)` for this project).

## Publishing

The test place is published from Studio (**File → Publish to Roblox**) after syncing `main`. Running servers keep the old version until they restart, so test in a new server. Keep the test place private until a phase's playtest calls for outside testers.
