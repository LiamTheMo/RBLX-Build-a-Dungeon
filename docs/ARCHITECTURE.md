# Architecture contract

The interfaces every module agrees on. Change this document first when an interface changes. Gameplay rules are in [GDD.md](GDD.md) and [PHASE0.md](PHASE0.md); conventions in [DEVELOPMENT.md](DEVELOPMENT.md); security rules in [AGENTS.md](../AGENTS.md).

## Principles

- The server decides everything that matters. The client sends requests and renders replicated state.
- Mutations run **without yielding** between reading and writing a profile, so each request is atomic per player (Luau is single-threaded). DataStore calls happen only in ProfileService, on copies.
- Pure rules (no Instances) live in `Rules` modules and have specs in `tests/luau/`.
- Refusals are `return false, "ReasonCode"`. Every code has player text in `src/shared/UI/ReasonText.luau`.
- Art is optional at runtime: when `ReplicatedStorage.Art.<...>` is missing, code-built graybox models are used, so the game always runs.
- Assets (images, mockups, model exports, audio files) live in `C:\Users\asus\Projects\Assets\BuildADungeon\`, never in this repo.

## Plot geometry (`src/shared/Rules/PlotGeometry.luau`)

- Each plot has an anchor CFrame at the grid centre, on the floor's top surface. Local −Z is the back of the plot; +Z is the front, where visitors arrive and players stand.
- `PlotGeometry.CellLocal(column, row) -> Vector3`: `((column - 3) * CellSize, 0, (2.5 - row) * CellSize)` for the 5 × 4 grid (generalised from `Grid`).
- `PlotGeometry.LocalToCell(localPos) -> (column, row)?`: nil outside the grid.
- `PlotGeometry.SpawnLocal() -> Vector3`: one cell in front of the entrance cell (visitors appear here and walk in).
- Plot anchors: `Workspace.Map.PlotAnchors.Plot1..PlotN` (Studio-owned parts). Without them, PlotService uses `CFrame.new((i - 1) * 60 - 150, 0.5, 0)`.

## Shared rules

- `Rules/Route.luau`:
  - `Route.Key(column, row) -> "c,r"`, `Route.Parse(key) -> (column?, row?)`.
  - `Route.Build(cells: {[cellKey]: roomId}) -> (true, {cellKey}) | (false, reason, cellKey?)`. `cells` excludes the entrance. It returns the cells in route order, starting next to the entrance. An empty layout returns `true, {}`. Reasons: `BadCell`, `OutOfBounds`, `OnEntrance`, `UnknownRoom`, `NotPlaceable`, `TooManyOfRoom`, `Branch`, `Loop`, `Disconnected`, `TreasureNotLast`.
- `Rules/Economy.luau`:
  - `VaultBonus(vault, extraCap?) -> fraction` (`extraCap` from `Progression.VaultCapBonus`).
  - `WinPayout(visitorId, vault, hasTreasure, coinBonus?, extraCap?) -> (amount, "Bank" | "Vault")`: `floor(reward * (1 + coinBonus) * (1 + vaultBonus))`, the vault bonus only with a treasure room.
  - `Theft(visitorId, vault) -> stolen`.
  - `MaxLevel(rarity?) -> number`; `UpgradeCost(currentLevel, rarity?) -> cost?` (nil at the rarity's max; default Common).
  - `VisitorInterval(hasTreasure, reduction?) -> seconds` (Lure; never below 1 s).
- `Rules/Loot.luau` (pure; every roll takes an injected `rng` with `NextNumber()`; the server uses `Random.new()`):
  - `Odds(boxType, pity?, level?) -> {Rooms = {{Id, Chance}}, Rarities = {{Id, Chance}}, PityAfter, PityRarity}?` for `"Dungeon"`/`"Rare"`: exactly the distribution the NEXT roll uses (pity-adjusted: at pity >= PityAfter only PityRarity+; room list gate-filtered: only rooms with `Progression.ShopLevel <= level`, falling back to the lowest-gated rooms). `RollRarity`, `RollRoom(rng, level?)`, `RollBlueprint(rng, level?)` and `RollDrops(..., level?)` use the same lists. Pass `profile.BoxPity` and `profile.Level`.
  - `RollRarity(boxType, pity, rng)`, `NextPity(pity, rarity)`, `RollRoom(rng)`, `RollBlueprint(rng)`, `RollPerks(rarity, rng) -> {{Kind, Amount}}`, `PerkAmount(rarity, kind)`, `RarityRank(rarity)`, `Craftable(roomId)`, `DropChances(visitorId, lootBonus) -> {Box, Blueprint, BoxType}`, `RollDrops(visitorId, lootBonus, rng) -> {{Kind = "Box", Type} | {Kind = "Blueprint", RoomId}}`.
- `Rules/Progression.luau` (pure): `XpToNext(level)`, `XpFor(visitorId, xpBonus)`, `AddXp(level, xp, amount) -> (level, xp, levelsGained)`, `LevelReward(level) -> "Dungeon"|"Rare"`, `ShopLevel(roomId)`, `PermanentCost(id, level) -> cost?`, `PermanentEffect(profile, effect)`, `Bonuses(profile) -> {Coins, Loot, Xp}` (placed-room perks + permanents, then capped), `DefenderHealthBonus(profile)`, `IntervalReduction(profile)`, `VaultCapBonus(profile)` (placed Treasure Room level + Deep Vault).
- Server `Rules/Rewards.luau` (pure profile mutations returning `(ok, dataOrReason)`): `Defeat(profile, visitorId, rng, bonuses) -> {Drops, Xp, LevelUp}`, `GrantXp`, `OpenBox`, `Craft`, `Scrap`, `BuyPermanent`.
- `UI/ReasonText.luau`: `ReasonText.Get(code) -> string` (falls back to a generic line).
- `Net/Remotes.luau`: `Remotes.Kinds[name] = "Function" | "Event"` for the remotes below; the server creates `ReplicatedStorage.Remotes`.

## Profile (schema v3, `src/server/Rules/ProfileSchema.luau`)

```lua
{
  Version = 3,
  Coins = 0, Vault = 0,                 -- whole numbers ≥ 0
  NextSerial = 3,                       -- next room instance id number
  Rooms = { r1 = { Id = "SlimeNest", Level = 1, Rarity = "Common", Perks = {} }, ... },  -- Perks = {{Kind = "Coins"|"Loot"|"Xp", Amount}}
  Layout = { ["3,2"] = "r1" },          -- cellKey -> instance id (entrance not stored)
  Tutorial = { Step = "Welcome", Done = false },
  Settings = { ReducedMotion = false, MusicVolume = 0.5, SfxVolume = 0.8 },
  ChallengerUnlocked = false,
  Stats = { Encounters = 0, Wins = 0, Escapes = 0, Robberies = 0, Earned = 0 },
  Discovered = { SlimeNest = true, TreasureRoom = true },  -- room and visitor ids ever owned/met
  Xp = 0, Level = 1,                    -- keeper level; Xp < XpToNext(Level)
  Boxes = { Dungeon = 0, Rare = 0 },
  Blueprints = {},                      -- roomId -> count (craftable rooms only)
  Permanent = {},                       -- upgradeId -> level (absent = 0)
  BoxPity = 0,                          -- boxes in a row below Rare (0..9)
}
```

- `ProfileSchema.Default() -> profile`, `ProfileSchema.Migrate(stored) -> (profile?, problem?)`. Repair rules: drop unknown room ids; drop layout entries pointing at missing or duplicate instances; clamp money to whole numbers ≥ 0; reset an invalid layout (failed `Route.Build`) to empty, keeping the rooms; reject a newer schema version without touching it. **v1 -> v2** adds `Discovered`: filled from owned rooms, plus `Practice` if `Stats.Encounters >= 1` and `Novice` if `>= 2`; stored ids are kept only if they are real room/visitor ids. `RoomInventory.Add` and the visitor spawn record new entries. **v2 -> v3** keeps every field; rooms become Common with no perks; Xp is seeded from `Stats.Wins * 10` converted into levels (no retroactive boxes). Validation: unknown rarity becomes Common; level clamped to the rarity's max; perks kept only for known, distinct kinds up to the rarity's count, with `Amount` re-derived from `Balance` (never trusted); Level 1..100 and Xp below the next level; box and blueprint counts whole 0..999, blueprints only for craftable rooms; permanent levels 0..max for known ids; `BoxPity` 0..9. A newer version is still rejected.
- Persistence (`ProfileService`): session lease on the DataStore key, retries with backoff, autosave every 60 s, save on leave and `BindToClose`. A failed load **never** creates or saves a default profile; the player gets `LoadState = "Failed"` and every request is refused with `ProfileNotLoaded`.

## Remotes (`ReplicatedStorage.Remotes`)

RemoteFunctions return `(ok: boolean, reasonOrData)`. Every handler checks argument types, the rate limit (`Net` guard: about 8 requests/s per player and remote) and a loaded profile, then calls the owning service.

| Remote | Args | Service |
| --- | --- | --- |
| `SetBuilding` | `on: boolean` | BuildService. Refused with `EncounterActive` while a visitor is inside |
| `CommitLayout` | `layout: {[cellKey]: instanceId}` (≤ 19 entries) | BuildService: ownership, each instance once, `Route.Build`, no encounter running |
| `Bank` | — | EconomyService: vault → coins |
| `Buy` | `roomId: string` | EconomyService: only `Source = "Shop"` rooms; keeper level gate (`LevelLocked`); adds a Common instance |
| `Upgrade` | `instanceId: string` | EconomyService: up to the instance's rarity max level (`MaxLevel`) |
| `InviteChallenger` | — | EncounterService: queues the challenger as the next visitor (requires `ChallengerUnlocked`; `ChallengerQueued` if already queued; `ChallengerCooldown` for `Balance.Loot.ChallengerCooldown` = 120 s after a challenger encounter ends). `UpgradeRoom` is refused `EncounterActive` while the plot is in an encounter |
| `OpenBox` | `boxType: "Dungeon" \| "Rare"` | LootService: returns `{InstanceId, RoomId, Rarity, Perks}`. Refusals `NoBox`, `TooManyRooms` (box kept). Boxes earned at the 999 stack cap convert to `Balance.Loot.BoxOverflowCoins` banked coins with a "Box storage full" Notice |
| `CraftBlueprint` | `roomId: string` | LootService: spends 5 blueprints, returns the new instance id. `NotCraftable`, `NotEnoughBlueprints`, `TooManyRooms` |
| `ScrapRoom` | `instanceId: string` | LootService: unplaced rooms only, +2 blueprints, returns the new count. `NotOwned`, `RoomPlaced`, `NotScrappable` (Treasure Room), `LastDefender` (would leave no Defender-kind room), `BlueprintsFull` (stack at 999) |
| `BuyPermanent` | `upgradeId: string` | EconomyService: returns the new level. `UnknownUpgrade`, `MaxLevel`, `NotEnoughCoins` |
| `TutorialAction` | `action: "Next" \| "Skip" \| "DeclineTreasure"` | TutorialService |
| `SaveSettings` | `{ReducedMotion: boolean, MusicVolume: number, SfxVolume: number}` | ProfileService |

RemoteEvents:
- `State` (server → owner): the full private snapshot whenever it changes: `{LoadState, Coins, Vault, VaultBonus, VaultBonusCap, Rooms (each with Rarity, Perks), Layout, Tutorial, Settings, ChallengerUnlocked, ChallengerQueued, Building, Stats, Discovered, Xp, Level, XpToNext, Boxes, Blueprints, Permanent, BoxPity, Bonuses = {Coins, Loot, Xp}}` (Bonuses are effective, capped).
- `EncounterFx` (server → all clients): `{Plot = n, Kind = ..., ...}` for visuals only. Kinds: `Spawn`, `Attack {By = "Visitor"|"Defender", Index, Damage}`, `Trap {Index, Hit}`, `Slow {Index}` (never sent for a Sure-footed visitor), `DefenderDown {Index}`, `DenBoost {Index = boosted defender, Den = den index}` (right after `Spawn`, once per boosted defender), `Spored {Index = cavern}`, `Rise {Index}` (Restless Crypt stands up again), `Trap` also carries `Spored` (hit while spored), `End {Result = "Defeated"|"Escaped"|"Robbed", Amount, Destination, Drops = {{Kind = "Box"|"Blueprint", Type?, RoomId?, Source = "Visitor"|"LevelUp"}}, Xp, LevelUp = newLevel?}` (drops, XP and level-up boxes are applied in the same non-yielding step as the payout, once per encounter).
- `Notice` (server → owner): `{Text, Kind = "Info"|"Good"|"Bad"}` toasts.

## Replicated plot state (`Workspace.Plots.Plot<n>`, server-built)

Model attributes:
- `OwnerUserId` (number, 0 when free) and `Index`.
- `Route` (string, cell keys in order joined by `|`).
- `State` (`"Idle" | "Building" | "Encounter"`), `NextVisitorAt` (`workspace:GetServerTimeNow()` time).
- `VisitorId`, `VisitorHealth`, `VisitorMaxHealth`, `VisitorProgress` (studs along the route from the entrance centre, updated 10×/s), `VisitorFighting` (route index or 0), `VisitorSlowed` (bool), `VisitorSpored` (bool), `NextVisitorId` (id of the visitor that will arrive next; set when the timer starts, updated if an Armored Challenger is invited; look up traits in `Visitors`).

Children:
- `Base` (floor, grid lines, entrance arch).
- `Rooms` with one Model per placed room, named by cell key. Attributes: `RoomId`, `InstanceId`, `Level`, `Rarity` (`"Common"|"Uncommon"|"Rare"|"Mythic"`), `RouteIndex`, `DefenderHealth`, `DefenderMaxHealth` (rarity and Stout Defenders included, Monster Den boost not). The server builds these models; clients animate them.

## Encounter simulation (`src/server/Rules/EncounterSim.luau`)

`EncounterSim.new({route = {roomId...}, levels = {number...}?, rarities = {rarity...}?, healthBonus = number?, visitorId}) -> sim` (levels capped by rarity; the rarity multiplier scales defenders, traps, Den and Mushroom bonuses; `healthBonus` is Stout Defenders; `EncounterSim.DefenderHealth(roomId, level, rarity, healthBonus)` for idle attributes); `sim:Step(dt) -> {events}` (`Spawn` on the first step; `End` carries only `Result`, and EncounterService adds `Amount`/`Destination`). It exposes `sim.Time`, `Progress`, `Health`, `MaxHealth`, `Result` (nil while running), `Fighting` (route index or 0), `Slowed`, `Spored` and `sim.Defenders[i] = {Health, MaxHealth, Down, Damage}`. Simultaneous duel hits both land; if both are knocked out, the visitor counts as Defeated. Trap damage also scales with level. Rules are in PHASE0.md, "Encounter rules": defenders stop the visitor and duel; traps strike on a fixed cycle (a strike at `Telegraph` seconds into each cycle, timed from encounter start); slime hits slow; treasure as the last room means `Robbed`; reaching the end otherwise means `Escaped`. Levels scale defender damage and health by `Balance.Upgrades`. EncounterService steps it at 10 Hz and pays out in the same step that sets `Result` (exactly once per encounter id).

## Art contract (`ReplicatedStorage.Art`, Studio-owned)

- `Art.Rooms.<RoomId>`: Model, pivot at the cell centre on the floor top, footprint 6 × 6 studs, walls ≤ 5 studs. Doorway wall pieces named `Door_North`, `Door_East`, `Door_South` and `Door_West`; the client hides a side's piece when a neighbour connects. An optional `DefenderSpot` Attachment (a descendant, currently under `Floor`, so find it with `FindFirstChild("DefenderSpot", true)`) marks the defender position. The PrimaryPart is a transparent `Pivot` part.
- `Art.Characters.<Name>` for `Practice`, `Novice`, `ArmoredChallenger`, `Slime`, `Guard` (and later `Skeleton`). Model with `PrimaryPart` `Root` (anchored, at the feet), about 1.6–2.2 studs tall, with Motor6D joints named `Neck`, `LeftShoulder`, `RightShoulder`, `LeftHip` and `RightHip` where limbs exist. Clients animate the `Transform` of those joints procedurally.
- `Art.Props.*`: coins, the vault chest, banners.
- Each model built in Studio is also exported to `Assets\BuildADungeon\models\<Name>.rbxmx`.

## Module map

| Side | Module | Owns |
| --- | --- | --- |
| server | `Infrastructure/Net` | Creates remotes; type, rate-limit and profile-loaded guard |
| server | `Infrastructure/DataStoreGateway`, `ProfileStore` | Leased load and save with retries |
| server | `Services/ProfileService` | Lifecycle, `Get(player)`, `Changed(player)` (pushes `State`) |
| server | `Services/PlotService` | Plot assignment, base, room models, attributes |
| server | `Services/BuildService` | Build mode, layout commit |
| server | `Services/EncounterService` | Visitor timer, sim loop, payouts, theft, FX events |
| server | `Services/EconomyService` | Bank, buy, upgrade, permanent upgrades |
| server | `Services/LootService` | Open boxes, craft blueprints, scrap rooms; server RNG for loot |
| server | `Services/TutorialService` | Tutorial steps and grants |
| client | `Controllers/PlotViewController` | Visitors, defender and trap animation, FX, health bars |
| client | `Controllers/BuildController` | Build camera, inventory, ghost preview, route overlay, commit/cancel |
| client | `Controllers/HudController` | HUD, encounter panel, shop, settings, toasts |
| client | `Controllers/TutorialController` | Prompts and highlights |
| client | `Ui/*` | Small UI kit and theme tokens from the UI spec |
