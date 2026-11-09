# Architecture contract

The interfaces every module agrees on. Change this document first when an interface changes. Gameplay rules are in [GDD.md](GDD.md) and [PHASE0.md](PHASE0.md); conventions in [DEVELOPMENT.md](DEVELOPMENT.md); security rules in [AGENTS.md](../AGENTS.md).

## Principles

- The server decides everything that matters. The client sends requests and renders replicated state.
- **Code split.** `src/shared` (`ReplicatedStorage.Shared`) holds only `Net/Remotes` (this contract) and the generic `Core/Loader` and `Core/Signal`. Definitions, balance and every rule are server-only (`src/server/Definitions`, `src/server/Rules`). The client runs no game rules: it gets display data from `GetCatalog`, per-player numbers from the `State` snapshot, encounter values and cell tiles from the plot, and layout checks from `PreviewLayout`. Client-only presentation data (`IconIds`, `SoundIds`, `RarityColors`, `ReasonText`) lives in `src/client/Ui`.
- Mutations run **without yielding** between reading and writing a profile, so each request is atomic per player (Luau is single-threaded). DataStore calls happen only in ProfileService, on copies.
- Pure rules (no Instances) live in `Rules` modules and have specs in `tests/luau/`.
- Refusals are `return false, "ReasonCode"`. Every code has player text in `src/client/Ui/ReasonText.luau` (the server only sends codes).
- Art is optional at runtime: when `ReplicatedStorage.Art.<...>` is missing, code-built graybox models are used, so the game always runs.
- Assets (images, mockups, model exports, audio files) live in `C:\Users\asus\Projects\Assets\BuildADungeon\`, never in this repo.

## Plot geometry (`src/server/Rules/PlotGeometry.luau`, server only)

- Each plot has an anchor CFrame at the grid centre, on the floor's top surface. Local −Z is the back of the plot; +Z is the front, where visitors arrive and players stand.
- `PlotGeometry.CellLocal(column, row) -> Vector3`: `((column - 3) * CellSize, 0, (2.5 - row) * CellSize)` for the 5 × 4 grid (generalised from `Grid`).
- `PlotGeometry.LocalToCell(localPos) -> (column, row)?`: nil outside the grid.
- `PlotGeometry.SpawnLocal() -> Vector3`: one cell in front of the entrance cell (visitors appear here and walk in).
- Plot anchors: `Workspace.Map.PlotAnchors.Plot1..PlotN` (Studio-owned parts). Without them, PlotService uses `CFrame.new((i - 1) * 60 - 150, 0.5, 0)`.
- Clients never use these functions: they read the plot's cell tiles (`Base.Cells`, see "Replicated plot state").

## Server rules (`src/server/Rules`, pure, with specs)

- `Rules/Route.luau`:
  - `Route.Key(column, row) -> "c,r"`, `Route.Parse(key) -> (column?, row?)`.
  - `Route.Build(cells: {[cellKey]: roomId}) -> (true, routeCells, offRouteCells) | (false, reason, cellKey?)`. `cells` excludes the entrance. Any shape is valid (rule of 2026-11-05): `routeCells` is the longest simple path of adjacent rooms in visiting order, starting next to the entrance, ending at the Treasure Room (`EndsRoute`) when it is reachable; `offRouteCells` are the idle rooms in key order. Ties: the path whose cell-key sequence sorts first. An empty layout returns `true, {}, {}`. Reasons (per cell, first in key order): `BadCell`, `OutOfBounds`, `OnEntrance`, `UnknownRoom`, `NotPlaceable`, `TooManyOfRoom`. `Branch`, `Loop`, `Disconnected` and `TreasureNotLast` are no longer produced.
  - `Route.CellProblem(key, roomId) -> reason?` (the per-cell checks, used by the profile repair). `Route.MaxVisits` (4000) caps the DFS; `Route.LastVisits` is a spec diagnostic.
- `Rules/LayoutRules.luau`: `Validate(profile, layout) -> (true, routeCells, cells, offRouteCells) | (false, reason, cellKey?)` with `cells = {[cellKey]: roomId}` for every placed room: `BadArgs`, `TooManyRooms` (> 19), `NotOwned`, `DuplicateInstance`, then `Route.Build`.
- `Rules/Economy.luau`:
  - `RewardRange(visitorId) -> (min, max)`; `RollReward(visitorId, rng) -> base` (whole, in [Min, Max], rolled once per encounter at spawn).
  - `CoinMultiplier({ThreatCoins?, VariantCoins?, CoinBonus?, EventCoins?}) -> number`; `WinPayout(base, multiplier) -> floor(base * multiplier)`. Rewards go straight to Coins.
  - `Vaulted(coins, percent, hasTreasure) -> floor(coins * percent / 100)` (0 without the Treasure Room on the route).
  - `VaultRate(roomId, level, deepVault) -> RatePerPercent * Exchange * (1 + LevelBonus * (level - 1) + 0.05 * deepVault)` (`Exchange` from `Balance.Rooms[roomId]`, 1 if absent); `VaultBonus(vaulted, rate) -> 25 * log10(1 + vaulted / 100) * rate` (a percentage).
  - `Theft(visitorId, vaulted, snapshot?, scale?) -> floor(min(vaulted, snapshot) * TheftFraction * scale)` (`scale` = the treasure's `TheftScale`, Void Vault 0.5).
  - **Item model (2026-11-05).** Each room definition (`Definitions/Rooms`) has one fixed `Rarity` (a `Balance.Rarities` Id), built-in `Perks` (from `Balance.RoomPerks`) and a short `Ability` line; a saved room instance is only `{Id, Level, Modifier?}`. `Rooms.Rarity(id)`, `Rooms.IsTreasure(id)`, `Rooms.KindLimit = {Treasure = 1}` (one treasure of any tier per plot, checked by `Route.Build` and the profile repair). **Rarity tiers** live in one ordered list, `Balance.Rarities` (`{Id, Weight, RareWeight, MaxLevel, CraftCost, ScrapReturn}`; index is rank; `Balance.RarityById[id]`). There is no stat multiplier: only the level (and a Blazing modifier) scales a room. **To add a tier:** insert one entry (keep both weight columns at 100 and the order low to high), give it at least one room, add an upgrade cost if its MaxLevel exceeds 10, and add its colour in the client's `src/client/Ui/RarityColors.luau`. Ids are saved, so never rename one.
  - `MaxLevel(rarity?) -> number`; `UpgradeCost(currentLevel, rarity?) -> cost?` (nil at the rarity's max; default Common).
- `Rules/Threat.luau` (pure): `Count()`, `Unlocked(level, all?) -> tier`, `Valid(tier)`, `Scale(tier) -> {Health, Damage, Coins, Xp, Drops}` (`1 + PerTier * (tier - 1)`), `Roster(tier) -> {{Id, Chance}}`, `PickVisitor(tier, rng)`, `VariantMultiplier(vaultBonus, eventVariants, treasureBonus?)` (treasureBonus = Dragon Hoard's 0.25), `VariantChances(visitorId, mult) -> {{Id, Chance}}` (rarest first, total capped at 1, Practice always 0), `RollVariant(visitorId, mult, rng) -> id?`, `Variant(id)`.
- `Rules/Events.luau` (pure): `Get(id)`, `Modifier(id)`, `Effects(id?) -> {Coins, Drops, Variants, BoxRarity, Xp}` (all 1 without an event), `BoxTiers(effects) -> tiers?` (Epic and rarer weights multiplied; pass to `Loot.Odds`/`RollRarity`), `RollModifier(eventId?, rng) -> id?` (25% during an event, uniform), `NextGap(rng)`, `RollEvent(rng)`.
- `Rules/Admin.luau` (pure): `IsAdmin(userId, config, rank?)` (listed UserId or rank >= `MinRank`), `Parse(text) -> command | (nil, usage)`, `EventIds()`.
- `Rules/Loot.luau` (pure; every roll takes an injected `rng` with `NextNumber()`; the server uses `Random.new()`):
  - `Odds(boxType, pity?, level?, tiers?) -> {Rarities = {{Id, Chance}}, TierRooms = {[tier] = {{Id, Chance}}}, Rooms = {{Id, Rarity, Chance}}, PityAfter, PityRarity}?` for `"Dungeon"`/`"Rare"`: exactly the distribution the NEXT open uses. A box rolls a tier (pity-adjusted: at pity >= PityAfter only PityRarity+; event-boosted via `tiers`; tiers with no rooms are skipped), then a room of that tier (`TierRooms`: chance inside the tier, by `Balance.Loot.RoomWeights`, default 1). Common/Uncommon rooms are gate-filtered (`Progression.ShopLevel <= level`, falling back to the tier's lowest-gated rooms); Rare+ are never gated. `Rooms` = tier chance × share, summing to 1. Pass `profile.BoxPity` and `profile.Level`.
  - `RollRarity(boxType, pity, rng, tiers?)`, `NextPity(pity, rarity)`, `TierRooms(tier, level?)`, `RollRoom(tier, rng, level?)`, `RollBox(boxType, pity, rng, level?, tiers?) -> (tier, roomId)`, `BlueprintOdds(level?) -> {{Id, Rarity, Chance}}` (tier by Dungeon weights, no pity/event, then a room), `RollBlueprint(rng, level?)`, `RarityRank(rarity)`, `Craftable(roomId)` (placeable with a room weight > 0: never the Coin Cache), `CraftCost(roomId)` / `ScrapReturn(roomId)` (the tier's), `DropChances(visitorId, lootBonus, scale?) -> {Box, Blueprint, BoxType}` (`base * (1 + loot) * scale`, capped at 1), `DropTable(visitorId, lootBonus, scale?, level?) -> {{Kind = "Box", Type, Chance} | {Kind = "Blueprint", RoomId, Rarity, Chance}}` (a blueprint's chance = blueprint chance × that room's `BlueprintOdds` share), `RollDrops(visitorId, lootBonus, rng, level?, scale?)` (same chances).
- `Rules/Progression.luau` (pure): `XpToNext(level)`, `XpFor(visitorId, xpBonus, threatXp?, eventXp?)`, `AddXp(level, xp, amount) -> (level, xp, levelsGained)`, `LevelReward(level) -> "Dungeon"|"Rare"`, `ShopLevel(roomId)`, `PermanentCost(id, level) -> cost?`, `PermanentEffect(profile, effect)`, `Bonuses(profile) -> {Coins, Loot, Xp}` (the definitions' built-in perks and Lucky/Golden modifiers of rooms ON THE ROUTE only + permanents, then capped; idle rooms count for nothing), `DefenderHealthBonus(profile)`, `VariantChanceBonus(profile)` (Rare Lure: fraction added to Elite/Shiny/Gilded chances), `Treasure(profile)` (the treasure-kind room on the route, any tier, else nil, so an off-route treasure has no vault effect), `VaultRate(profile)`, `VariantBonus(profile)` (route treasure's `VariantBonus`, else 0), `TheftScale(profile)` (route treasure's `TheftScale`, else 1), `VaultBonus(profile)` (percent, a luck source), `Vaulted(profile)`, `ThreatUnlocked(profile, all?)`, `ActiveThreat(profile, all?)` (1 until the tutorial is done, else the selection clamped to the unlocked tier).
- Server `Rules/Rewards.luau` (pure profile mutations returning `(ok, dataOrReason)`): `Context(profile, eventId?, unlockAll?) -> {Threat, Scale, Bonuses, Effects, EventId, VariantMult}`, `CoinMultiplier(ctx, variant?)`, `DropScale(ctx, variant?)`, `CoinRange(visitorId, ctx, variant?) -> {Min, Max}`, `Table(profile, visitorId, ctx) -> {Coins, Xp, Drops, Variants}` (what the player sees), `Defeat(profile, visitorId, rng, ctx, base, variant?) -> {Amount, Drops, Xp, LevelUp}` (pays coins, rolls with the same numbers as `Table`, adds a variant's guaranteed box), `GrantXp`, `GiveBoxes` (admin), `OpenBox(profile, boxType, rng, eventId?) -> {InstanceId, RoomId, Rarity, Perks, Modifier?}` (tier then room; event box boost and modifier roll; Perks = copy of the definition's), `Craft` (the tier's CraftCost), `Scrap` (the tier's ScrapReturn), `BuyPermanent`.
- `Rules/Catalog.luau`: `Catalog.Build() -> catalog` (deeply frozen; see "Catalog").
- `Rules/StateView.luau`: `StateView.Derived(profile, world?) -> {VaultPercent, Vaulted, VaultRisk, VaultRate, VaultBonus, VaultLuck, VariantChance, Threat, ThreatActive, ThreatUnlocked, ActiveEvent, XpToNext, Bonuses, Rooms, BoxOdds, PermanentNextCost, DropChances, DropTables, NextUnlocks}` with `world = {EventId?, UnlockAll?}`, the server-computed part of the `State` snapshot. Never mutates the profile (rooms are copies).
- Client `Ui/ReasonText.luau`: `ReasonText.Get(code) -> string` (falls back to a generic line).
- Shared `Net/Remotes.luau`: `Remotes.Kinds[name] = "Function" | "Event"` for the remotes below; the server creates `ReplicatedStorage.Remotes`.

## Catalog (`GetCatalog`)

Static display data, the same for every player, built once by `CatalogService` from the server definitions. The client fetches it on start (`Ui/Catalog`: retry with backoff, then cached) before building UI. It holds only what the UI shows. Since 2026-11-05 (owner request) that includes coin ranges, XP, theft shares, base drop tables, threat multipliers and variant chances; defender/visitor health and damage and box weights still never leave the server (box odds go per player in `State.BoxOdds`).

```lua
{
  Rooms = { [roomId] = { Id, DisplayName, Kind, Description, Source = "Permanent"|"Starter"|"Tutorial"|"Shop"|"Loot", Cost?, ShopLevel,
                         Upgradable, MaxPlaced?, EndsRoute, Placeable, Craftable, TrapCycle?, TrapTelegraph?,  -- strike traps' warning timing
                         Rarity, Tier (rank), MaxLevel, Perks = { { Kind, Amount } }, Ability (short line),
                         Exchange? (treasure rooms), CraftCost?, ScrapReturn? } },
  RoomOrder = { roomId... },                     -- display order (Rooms.Order)
  Visitors = { [visitorId] = { Id, DisplayName, Description, Arrival, Traits = { { Id, Name, Text } },
                               Reward = { Min, Max }, Xp, Theft,          -- base coins, base XP, share of vaulted coins stolen
                               Drops = { { Kind = "Box", Type, Chance } | { Kind = "Blueprint", RoomId, Chance } } } },  -- threat 1, no bonuses, ungated
  Rarities = { { Id, MaxLevel, CraftCost, ScrapReturn, Rooms = { roomId... } } },  -- ordered, index = rank; Rooms = placeable rooms of that tier
  Permanent = { { Id, Name, MaxLevel, PerLevelText, EffectText = { [level + 1] = text } } },  -- shop order
  Grid = { Columns, Rows, CellSize, EntranceCell = { Column, Row }, EntranceKey },
  Loot = { BoxTypes, CraftCost = { [tier] = n }, ScrapReturn = { [tier] = n }, SaleCoins = { [tier] = n } },
  MaxKeeperLevel = 100,
  Variants = { { Id, Chance, Health, Coins, Drops, GuaranteedBox? } },        -- rarest first: Gilded, Shiny, Elite; multipliers
  Threat = { [tier] = { Tier, UnlockLevel, Health, Damage, Coins, Xp, Drops, Roster = { { Id, Chance } } } },
  Events = { { Id, Name, Text } },
  Modifiers = { { Id, Name, Effect = "Damage"|"Loot"|"Coins", Amount, Text } },
}
```

## Profile (schema v5, `src/server/Rules/ProfileSchema.luau`)

```lua
{
  Version = 5,
  Coins = 0,                            -- whole number ≥ 0 (includes the vaulted share)
  VaultPercent = 0,                     -- 0..100: share of Coins at risk while a Treasure Room is placed
  Threat = 1,                           -- selected threat tier (clamped to the unlocked tier on load)
  NextSerial = 3,                       -- next room instance id number
  Rooms = { r1 = { Id = "SlimeNest", Level = 1 }, r2 = { Id = "TreasureRoom", Level = 1 }, ... },  -- {Id, Level, Modifier?}; rarity and perks come from the definition; Modifier = "Blazing"|"Lucky"|"Golden"|nil
  Layout = { ["3,2"] = "r1" },          -- cellKey -> instance id (entrance not stored)
  Tutorial = { Step = "Welcome", Done = false },
  Settings = { ReducedMotion = false, MusicVolume = 0.5, SfxVolume = 0.8 },
  ChallengerUnlocked = false,           -- legacy: the challenger invite was removed in v4; kept, unused
  Stats = { Encounters = 0, Wins = 0, Escapes = 0, Robberies = 0, Earned = 0 },
  Discovered = { SlimeNest = true, TreasureRoom = true },  -- room and visitor ids ever owned/met
  Xp = 0, Level = 1,                    -- keeper level; Xp < XpToNext(Level)
  Boxes = { Dungeon = 0, Rare = 0 },
  Blueprints = {},                      -- roomId -> count (craftable rooms only)
  Permanent = {},                       -- upgradeId -> level (absent = 0)
  BoxPity = 0,                          -- boxes in a row below Rare (0..9)
}
```

- `ProfileSchema.Default() -> profile`, `ProfileSchema.Migrate(stored) -> (profile?, problem?)`. Repair rules: drop unknown room ids; drop layout entries pointing at missing or duplicate instances; clamp money to whole numbers ≥ 0; drop layout entries, one by one in key order, whose cell fails `Route.CellProblem` (malformed, out of bounds, entrance, unplaceable) or that exceed `MaxPlaced` (a second Treasure Room); the layout's shape is never repaired (any shape is valid since 2026-11-05); reject a newer schema version without touching it. **v1 -> v2** adds `Discovered`: filled from owned rooms, plus `Practice` if `Stats.Encounters >= 1` and `Novice` if `>= 2`; stored ids are kept only if they are real room/visitor ids. `RoomInventory.Add` and the visitor spawn record new entries. **v2 -> v3** keeps every field; rooms become Common with no perks (the rarity list grew to 7 tiers without a version bump: ids are validated against `Balance.Rarities`, and saved levels are only ever clamped to the cap, which only rose); Xp is seeded from `Stats.Wins * 10` converted into levels (no retroactive boxes). Validation: unknown rarity becomes Common; level clamped to the rarity's max; perks kept only for known, distinct kinds up to the rarity's count, with `Amount` re-derived from `Balance` (never trusted); Level 1..100 and Xp below the next level; box and blueprint counts whole 0..999, blueprints only for craftable rooms; permanent levels 0..max for known ids; `BoxPity` 0..9. A newer version is still rejected. **v3 -> v4** (2026-11-05): `Coins += Vault` (capped at `MAX_MONEY`), `Vault` dropped, `VaultPercent = 0`, `Threat = 1`; every other field kept. v4 validation: `VaultPercent` whole 0..100; `Threat` a whole tier, clamped to the tier the saved level unlocks; room `Modifier` kept only if it is a known modifier id. A stray `Vault` on a v4 profile is ignored. **v4 -> v5** (2026-11-05 item model): instance `Rarity` and `Perks` are dropped (they belong to the definition) and `Level` is clamped to the definition's tier cap (no refund for levels above it); every other field kept; v6+ rejected. Layout repair also enforces `Rooms.KindLimit` (a second treasure of any tier is dropped, key order).
- Persistence (`ProfileService`): session lease on the DataStore key, retries with backoff, autosave every 60 s, save on leave and `BindToClose`. A failed load **never** creates or saves a default profile; the player gets `LoadState = "Failed"` and every request is refused with `ProfileNotLoaded`.
- Room instance serials are bounded to the saved ID format. An unsafe saved serial fails the profile load without overwriting it; exhausted serial capacity returns `RoomIdsExhausted` before a purchase, craft or chest batch spends anything.
- Coin rewards and full-chest conversions stop at the existing saved balance cap; feedback reports the amount actually credited and warns when an encounter reward is capped.

## Remotes (`ReplicatedStorage.Remotes`)

RemoteFunctions return `(ok: boolean, reasonOrData, extra?)`. Every handler checks argument types, the rate limit (`Net` guard: about 8 requests/s per player and remote) and a loaded profile (except `GetCatalog`, registered with `Net.HandleOpen`), then calls the owning service.

| Remote | Args | Service |
| --- | --- | --- |
| `GetCatalog` | — | CatalogService: returns the frozen catalog (above). No loaded profile needed, so the load-failure screen still works |
| `PreviewLayout` | `layout: {[cellKey]: instanceId}` (≤ 19 entries, same check as `CommitLayout`) | BuildService: `LayoutRules.Validate` without applying anything (no build-mode or cooldown check). Returns `(true, routeCells, offRouteCells)` or `(false, reason, cellKey?)`; idle (off-route) rooms are in `offRouteCells`. The client calls it about 0.15 s after each draft change and shows "Checking route..." meanwhile; `CommitLayout` re-validates |
| `SetBuilding` | `on: boolean` | BuildService. Starting build mode cancels an active visitor without payout or theft; spawning pauses until the player exits build mode. |
| `CommitLayout` | `layout: {[cellKey]: instanceId}` (≤ 19 entries) | BuildService: ownership, each instance once, `Route.Build` (any shape), no encounter running. Returns `(true, routeCells, offRouteCells)` |
| `SetVaultPercent` | `percent: integer 0..100` | EconomyService: sets `VaultPercent`; returns the percent. `EncounterActive` while a visitor is inside (no dodging a theft). Rate limit is the `Net` guard; the client should debounce a slider. Advances the tutorial's BankVault step (`VaultSet`) |
| `SetThreat` | `tier: integer 1..6` | EncounterService: selects `Threat` for the next visitor; returns the tier. `ThreatLocked` above the unlocked tier. A running encounter keeps its original tier; an idle plot re-rolls the announced next visitor |
| `Buy` | `roomId: string` | EconomyService: only `Source = "Shop"` rooms of tier Common or Uncommon (`NotForSale` otherwise); keeper level gate (`LevelLocked`); adds a level-1 instance |
| `Upgrade` | `instanceId: string` | EconomyService: up to the max level of the room definition's tier (`MaxLevel`) |
| `OpenBox` | `boxType: "Dungeon" \| "Rare"` | LootService: rolls a tier, then a room of that tier; returns `{InstanceId, RoomId, Rarity, Perks (the definition's), Modifier?}` (during an event: boosted tier weights for Blessed Boxes and a 25% modifier roll). Refusals `NoBox`, `TooManyRooms` (box kept). Boxes earned at the 999 stack cap convert to `Balance.Loot.BoxOverflowCoins` banked coins with a "Box storage full" Notice |
| `CraftBlueprint` | `roomId: string` | LootService: spends the room tier's craft cost (5 / 6 / 8 / 10 / 12 / 15 / 20), returns the new instance id. `NotCraftable`, `NotEnoughBlueprints`, `TooManyRooms` |
| `ScrapRoom` | `instanceId: string` | LootService: unplaced rooms only, + the tier's scrap return (2 / 3 / 4 / 5 / 6 / 8 / 10), returns the new count. `NotOwned`, `RoomPlaced`, `NotScrappable` (the Coin Cache), `LastDefender` (would leave no Defender-kind room), `BlueprintsFull` (stack at 999) |
| `OpenBoxes` | `boxType: string, count: integer` | Opens 1–30 owned chests if there is room for the entire batch. Pity advances after each roll; returns all rewards. |
| `SellRooms` | `instanceIds: string[]` | Sells 1–30 distinct owned, unplaced, craftable rooms for server-defined rarity values; protects the last defender and rejects the whole request if invalid. |
| `BuyPermanent` | `upgradeId: string` | EconomyService: returns the new level. `UnknownUpgrade`, `MaxLevel`, `NotEnoughCoins` |
| `TutorialAction` | `action: "Next" \| "Skip" \| "DeclineTreasure"` | TutorialService |
| `SaveSettings` | `{ReducedMotion: boolean, MusicVolume: number, SfxVolume: number}` | ProfileService |

RemoteEvents:
- `State` (server → owner): the full private snapshot whenever it changes: `{LoadState, Coins, VaultPercent, Vaulted, VaultRisk, VaultRate, VaultBonus (percent), VaultLuck (x), VariantChance (x, all rare-visitor boosts), Threat (selected), ThreatActive (what visitors use: 1 during the tutorial), ThreatUnlocked, ThreatUnlockAll? (admin override, transient), ActiveEvent (id or nil), Rooms (copies `{Id, Level, Modifier?}` plus, from the definition, `Rarity`, `Perks` and `MaxLevel`, and `NextUpgradeCost`: nil at the tier's max or when not upgradable), Layout, Tutorial, Settings, Building, Stats, Discovered, Xp, Level, XpToNext, Boxes, Blueprints, Permanent, BoxPity, Bonuses = {Coins, Loot, Xp}, BoxOdds = {Dungeon = odds, Rare = odds} (`Loot.Odds`: `Rarities`, `TierRooms`, `Rooms`), PermanentNextCost = {[upgradeId] = cost (absent at max)}, DropChances = {[visitorId] = {Box, Blueprint, BoxType}}, DropTables = {[visitorId] = {Coins = {Min, Max}, Xp, Drops = {{Kind, Type?, RoomId?, Rarity?, Chance}}, Variants = {{Id, Chance, Coins = {Min, Max}, Drops, GuaranteedBox?}}}}, NextUnlocks = {Threat = {Tier, Level}?, ShopRoom = {RoomId, Level}?, Permanent = {Id, Cost, Affordable}?}}` (Bonuses are effective, capped; `BoxOdds[box]` is exactly the distribution the next open rolls, event boost included; `DropChances` and `DropTables` are for a normal visitor at `ThreatActive` with the loot bonus and the event; `Vault`, `VaultBonusCap`, `ChallengerUnlocked` and `ChallengerQueued` were removed in v4). Computed by `Rules/StateView`. Shop level gates: the client compares `Catalog.Rooms[id].ShopLevel` with `Level` (the server enforces `LevelLocked`).
- `EncounterFx` (server → all clients): `{Plot = n, Kind = ..., ...}` for visuals only. Kinds: `Spawn {VisitorId, Variant = "" | "Elite" | "Shiny" | "Gilded", Threat}`, `Attack {By = "Visitor"|"Defender", Index, Damage}`, `Trap {Index, Hit}`, `Slow {Index}` (never sent for a Sure-footed visitor), `DefenderDown {Index}`, `DenBoost {Index = boosted defender, Den = den index}` (right after `Spawn`, once per boosted defender), `Spored {Index = cavern}`, `Rise {Index}` (Restless Crypt stands up again), `Trap` also carries `Spored` (hit while spored) and `Burn = true` (a Flame Vent hit that ignites); `Attack` from a defender carries `Burn = true` for Dragon Lair breath. New in the 2026-11-05 roster: `Burn {Index = room that set the fire, Damage}` (one per burn tick, every 0.5 s), `Chill {Index = Frost Chamber}` (visitor enters a chill zone: that room or the next), `Unit {Index, Unit = n, Name = "Goblin"|"Lich"}` (the next unit steps in), `Summon {Index, Name = "Skeleton"}` (Lich Sanctum, on arrival), `Ambush {Index, Damage}` (Mimic Room, on arrival), `Revive {Index = revived defender, By = Phoenix Nest index}`, `Void {Index}` (the visitor is sent back to the entrance: `VisitorProgress` drops to 0, so snap, don't tween). The arrow volley and flame strike reuse `Trap`. `End {Result = "Defeated"|"Escaped"|"Robbed", VisitorId, Variant, Threat, Amount (the actual coins won or stolen), Destination = "Bank" (won, to Coins) | "Vault" (stolen from Coins) | "None", Drops = {{Kind = "Box"|"Blueprint", Type?, RoomId?, Source = "Visitor"|"LevelUp", Guaranteed? (variant box), Overflow?}}, Xp, LevelUp = newLevel?}` (drops, XP and level-up boxes are applied in the same non-yielding step as the payout, once per encounter).
- `Notice` (server → owner, or all for events): `{Text, Kind = "Info"|"Good"|"Bad"}` toasts.
- `ServerEvent` (server → all): `{Kind = "Start", Id, EndsAt}` / `{Kind = "End", Id}` when a server event starts or ends. The current event is also on Workspace attributes `ActiveEvent` (id, `""` when none) and `EventEndsAt` (`workspace:GetServerTimeNow()` time, 0 when none); names and texts in `Catalog.Events`.

## Admin commands (`Services/AdminService`, `Config/Admins.luau`)

TextChatCommands `/event`, `/give`, `/threat` are created by the server (`AutocompleteVisible = false`) and handled in the server's `Triggered`; no remote. A player is an admin if their UserId is in `Config/Admins.UserIds` (855002824) or their rank in group 33284082 is ≥ 254 (looked up once per player and cached; a failed lookup is retried, not cached). Non-admins get no response. Every admin action is printed with the admin's UserId. Syntax: `/event start <id> [minutes 1..240]`, `/event stop`, `/event list`, `/give coins <n> [player]`, `/give box <Dungeon|Rare> <n ≤ 999> [player]`, `/give xp <n> [player]`, `/threat unlockall [player]` (session-only `ThreatUnlockAll` transient). `[player]` is a name, display name or unique name prefix; default is the admin.

## Replicated plot state (`Workspace.Plots.Plot<n>`, server-built)

Model attributes:
- `OwnerUserId` (number, 0 when free) and `Index`.
- `Route` (string, cell keys in order joined by `|`).
- `State` (`"Idle" | "Building" | "Encounter"`), `NextVisitorAt` (`workspace:GetServerTimeNow()` time).
- `VisitorId`, `VisitorHealth`, `VisitorMaxHealth` (threat and variant included), `VisitorProgress` (studs along the route from the entrance centre, updated 10×/s), `VisitorFighting` (route index or 0), `VisitorSlowed` (bool), `VisitorSpored` (bool), `VisitorBurning` (bool), `VisitorChilled` (bool), `VisitorVariant` (`""` | `"Elite"` | `"Shiny"` | `"Gilded"`), `NextVisitorId` (rolled from the selected tier's roster between encounters; re-rolled when the tier changes while idle; names and traits in `Catalog.Visitors`; the variant is not announced), `Threat` (the current visitor's tier during an encounter, otherwise the selected tier for the next visitor).
- `VisitorRewardMin` / `VisitorRewardMax` (the coin range if defeated now: threat, variant, coin bonus and event applied; the base roll stays hidden until `End.Amount`) and `VisitorTheft` (what it would steal on reaching the treasure now: TheftFraction of the vaulted coins; 0 without a Treasure Room). Set at spawn, before `VisitorId`, and refreshed every step; display only, `finish()` computes the real payout.
- `NextVisitorAt` is a fixed delay only: the server sets it to "now" when an encounter ends (the next visitor spawns at once after a defeat, escape or robbery), to now + 3 s / 10 s for the first visitor, and to now + the resume delay when build mode ends (a later time is only ever pushed later). The HUD shows a countdown only while it is in the future.

Children:
- `Base` (floor, grid lines, entrance arch) and `Base.Cells` (Model, `ModelStreamingMode = Persistent`): one tile per grid cell named by its cell key (`Art.Rooms.EmptyCellTile` when present, its visible parts lifted 0.04 studs and hidden under placed rooms and the entrance; otherwise an invisible thin part). Each tile's pivot is the cell centre on the floor top; attributes `CellKey`, `Column`, `Row`, `Placeable` (false on the entrance). Also `Base.Cells.VisitorSpawn` (invisible, `CanQuery` false): where visitors appear. The client raycasts the tiles (include list) to pick cells and uses their pivots for ghosts, the route overlay and the visitor path; in build mode it hides tile art under draft rooms locally.
- `Rooms` with one Model per placed room, named by cell key. Attributes: `RoomId`, `InstanceId`, `Level`, `Rarity` (the definition's fixed tier), `Modifier` (`""` or a modifier id), `RouteIndex` (1-based place on the route, 0 for an idle room), `OnRoute` (bool), `DefenderHealth`, `DefenderMaxHealth` (current unit; level and Stout Defenders included, Monster Den boost not until an encounter), `DefenderUnit` (1-based unit for Goblin Barracks / Lich Sanctum). The server builds these models; clients animate them.

## Encounter simulation (`src/server/Rules/EncounterSim.luau`)

`EncounterSim.new({route = {roomId...}, levels = {number...}?, modifiers = {modifierId...}?, healthBonus = number?, visitorId, visitorHealth = number?, visitorDamage = number?}) -> sim` (levels capped by the definition's tier; no rarity multiplier; a Blazing modifier adds 15% damage to that room; `healthBonus` is Stout Defenders; `visitorHealth`/`visitorDamage` are the threat and variant multipliers; `EncounterSim.DefenderHealth(roomId, level, healthBonus)` (first unit) for idle attributes); `sim:Step(dt) -> {events}` (`Spawn` on the first step; `End` carries only `Result`, and EncounterService adds `Amount`/`Destination`). It exposes `sim.Time`, `Progress`, `Health`, `MaxHealth`, `Result` (nil while running), `Fighting` (route index or 0), `Slowed`, `Spored`, `Burning`, `Chilled` and `sim.Defenders[i] = {Health, MaxHealth, Down, Damage, Interval, Unit, Units, Name}`. Simultaneous duel hits both land; if both are knocked out, the visitor counts as Defeated. Trap damage also scales with level. Rules are in PHASE0.md, "Encounter rules": defenders stop the visitor and duel; traps strike on a fixed cycle (a strike at `Telegraph` seconds into each cycle, timed from encounter start); slime hits slow; treasure as the last room means `Robbed`; reaching the end otherwise means `Escaped`. Levels scale defender damage and health by `Balance.Upgrades`. EncounterService steps it at 10 Hz and pays out in the same step that sets `Result` (exactly once per encounter id). Room mechanics (data in `Balance.Rooms`): defenders with `Units` fight in sequence (next unit 0.5 × its interval after the previous falls), `AmbushDamage` strikes on arrival, `Summon` emits `Summon`, `Burn` hits ignite, `Revives` (Phoenix Nest) revive the first knocked-out route defender at full health; strike traps (`Cycle`) may `Burn`; zone traps (`ZoneDamage`/s) may chill (`SlowFraction`, `ChillsNextRoom`) or `SendsBack` once at the room's centre (progress 0). Slows: the strongest applies; Sure-footed ignores slows only. Burn ticks every 0.5 s, refreshes, keeps the stronger damage and blocks Mender healing. Spores raise trap strikes and zone damage, not burn.

## Art contract (`ReplicatedStorage.Art`, Studio-owned)

- `Art.Rooms.<RoomId>`: Model, pivot at the cell centre on the floor top, footprint 6 × 6 studs, walls ≤ 5 studs. Doorway wall pieces named `Door_North`, `Door_East`, `Door_South` and `Door_West`; the client hides a side's piece when a neighbour connects. An optional `DefenderSpot` Attachment (a descendant, currently under `Floor`, so find it with `FindFirstChild("DefenderSpot", true)`) marks the defender position. The PrimaryPart is a transparent `Pivot` part.
- `Art.Characters.<Name>` for `Practice`, `Novice`, `ArmoredChallenger`, `Slime`, `Guard` (and later `Skeleton`). Model with `PrimaryPart` `Root` (anchored, at the feet), about 1.6–2.2 studs tall, with Motor6D joints named `Neck`, `LeftShoulder`, `RightShoulder`, `LeftHip` and `RightHip` where limbs exist. Clients animate the `Transform` of those joints procedurally.
- **Rooms and creatures of the 2026-11-05 roster (art not made yet; graybox until then):** `Art.Rooms.` `ArrowGallery`, `BatRoost`, `Strongbox`, `FlameVent`, `Treasury`, `FrostChamber`, `GoblinBarracks`, `MimicRoom` (a chest that opens into a mouth), `RoyalVault`, `GolemForge`, `LichSanctum`, `DragonHoard`, `DragonLair`, `PhoenixNest`, `CelestialCoffer`, `VoidGate`, `VoidVault` (`TreasureRoom` art is the Coin Cache). `Art.Characters.` `Bat`, `Goblin`, `Mimic`, `Golem`, `Skeleton` (Restless Crypt and the lich's summon), `Lich`, `Dragon`, `Phoenix`. Treasure graybox uses the chest prop for every treasure room.
- `Art.Props.*`: coins, the vault chest, banners.
- Each model built in Studio is also exported to `Assets\BuildADungeon\models\<Name>.rbxmx`.

## Module map

| Side | Module | Owns |
| --- | --- | --- |
| shared | `Net/Remotes`, `Core/Loader`, `Core/Signal` | Remote contract; module lifecycle; in-process signals |
| server | `Definitions/*` (`Balance`, `Grid`, `Rooms`, `Visitors`) | Identities and every tunable number |
| server | `Config/Admins` | Admin UserIds and group rank |
| server | `Rules/*` | Pure rules (Route, Economy, Loot, Progression, Threat, Events, Admin, PlotGeometry, LayoutRules, EncounterSim, Rewards, ProfileSchema, Catalog, StateView, ...) |
| server | `Infrastructure/Net` | Creates remotes; type, rate-limit and profile-loaded guard (`Handle`, `HandleOpen`) |
| server | `Infrastructure/DataStoreGateway`, `ProfileStore` | Leased load and save with retries |
| server | `Services/ProfileService` | Lifecycle, `Get(player)`, `Changed(player)` (pushes `State`) |
| server | `Services/CatalogService` | `GetCatalog` |
| server | `Services/PlotService` | Plot assignment, base, cell tiles, room models, attributes |
| server | `Services/BuildService` | Build mode, layout preview and commit |
| server | `Services/EncounterService` | Visitor timer, threat roster, variant and reward rolls, sim loop, payouts, theft, preview attributes, FX events, `SetThreat` |
| server | `Services/EconomyService` | Vault share, buy, upgrade, permanent upgrades |
| server | `Services/EventService` | Server event schedule, start/stop, Workspace attributes, broadcasts |
| server | `Services/AdminService` | Admin chat commands (server-side TextChatCommands) |
| server | `Services/LootService` | Open boxes, craft blueprints, scrap rooms; server RNG for loot |
| server | `Services/TutorialService` | Tutorial steps and grants |
| client | `Controllers/PlotViewController` | Visitors, defender and trap animation, FX, health bars |
| client | `Controllers/BuildController` | Build camera, inventory, ghost preview, route overlay from `PreviewLayout`, commit/cancel |
| client | `Controllers/HudController` | HUD, encounter panel, shop, settings, toasts |
| client | `Controllers/TutorialController` | Prompts and highlights |
| client | `Ui/Catalog`, `Ui/Cells`, `Ui/State` | Cached catalog; cell tiles (pick, positions); latest State snapshot |
| client | `Ui/*` | Small UI kit, theme tokens, icons, sounds, rarity colours, refusal text |
