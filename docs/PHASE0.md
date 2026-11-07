# Phase 0 — Specification of the first playable experience

**Companions:** [GDD](GDD.md) · [Build phases](BUILD_PHASES.md) · [Development guide](DEVELOPMENT.md) · [Playtest checklist](PLAYTEST_CHECKLIST.md)

This document pins down what the GDD leaves open, so Phases 1–6 can be built and tested against something concrete. If this document and the GDD disagree, the GDD wins and this document must be corrected. Items marked **Assumption** were chosen here to keep work moving; the owner should confirm or change them.

## Owner-approved direction (2026-11-04)

- **The treasure room is optional.** It is a risk-for-reward choice, not a requirement. A player owns one from the start and may place it or not.
- **Rooms are small open squares** about the height of a player's avatar, with a doorway on every side. The dungeon is a miniature diorama with small adventurers walking through it.

These are recorded in the GDD change log. They also resolve a conflict in the earlier draft: with both the entrance and the treasure room fixed and one room apart, the tutorial had no space to add the spike hall.

## Grid and route

Values live in `src/server/Definitions/Grid.luau`.

- 5 columns × 4 rows. Each cell is 6 × 6 studs and walls are 5 studs high, so a room is roughly avatar height. A plot's dungeon is about 30 × 24 studs.
- Cells are addressed (column, row). Row 1 is the front edge, where visitors arrive.
- The **entrance is fixed at (3, 1)**, front and centre, so routes can grow left, right or straight back.
- Every room has doorways on all four sides, so orthogonally adjacent rooms always connect. Diagonal cells do not touch.
- **Free placement (owner-approved 2026-11-05).** A room may go in any cell except the entrance, and a layout is never refused for its shape: branches, loops and disconnected rooms are allowed. Still refused: a cell out of bounds or on the entrance, an unowned or unknown instance, the same instance twice, a second treasure room, more than 19 rooms.
- **The route is computed by the server** (`Rules/Route.luau`): the longest simple path (most rooms) through orthogonally adjacent rooms, starting at a room next to the entrance. If the treasure room is placed and reachable, the route is the longest simple path that **ends** at the treasure room (it is never walked through). If it is not reachable, the route is the longest path overall and the treasure room is off the route. Ties go to the path whose sequence of cell keys sorts first, so `PreviewLayout`, `CommitLayout`, rendering and encounters always agree.
- **Idle rooms.** Rooms not on the route stay placed but do not fight and give no perks, event modifiers or bonuses. Vault effects (vaulted coins, theft, the vault bonus) need the treasure room on the route. A Monster Den boosts only defenders next to it on the route. If no room touches the entrance the route is empty and no visitor comes.
- **Search cost.** Longest simple path is a depth-first search in cell-key order with an upper bound (rooms still reachable, tightened by the grid's two-colour parity, and by the treasure's colour when the route must end there) and a hard cap of `Route.MaxVisits` = 4000 node visits; if the cap is ever hit, the best path found so far is used (or the first shortest path to the treasure), which is still deterministic. Timings are in `tests/luau/route.spec.luau`.
- Rooms are not rotated.

### Sketch: the starting plot and the first route

Row 4 is the back of the plot, drawn at the top. `E` entrance, `S` slime nest, `K` spike hall, `T` treasure room, `G` guard room, `.` empty.

```
            col 1  col 2  col 3  col 4  col 5
row 4 (back)  .      .      T      .      .      <- optional, offered by the tutorial
row 3         .      .      K      .      .      <- tutorial places the spike hall here
row 2         .      .      S      .      .      <- starter slime nest, already placed
row 1 (front) .      .      E      .      .      <- fixed entrance
                            ^ visitors arrive here
```

Route: E → S → K (→ T). Visitors meet the slime first, are slowed, then cross the spikes slowly.

### Sketch: routes in free layouts

```
Snake                      Loop                       Branch
row 4  .  .  T  .  .       row 4  .  .  .  .  .       row 4  .  .  .  .  .
row 3  S  K  G  .  .       row 3  .  .  .  .  .       row 3  .  .  .  .  .
row 2  K  .  .  .  .       row 2  .  .  S  K  .       row 2  .  K  S  G  G
row 1  S  G  E  .  .       row 1  .  .  E  G  .       row 1  .  .  E  .  .
```

- **Snake:** E(3,1) → G(2,1) → S(1,1) → K(1,2) → S(1,3) → K(2,3) → G(3,3) → T(3,4). Every room is on the route and the treasure room is last.
- **Loop:** the route walks around it: S(3,2) → K(4,2) → G(4,1), all three rooms on the route.
- **Branch:** the longer arm wins: S(3,2) → G(4,2) → G(5,2); K(2,2) is idle. With equal arms the arm whose cell key sorts first wins.
- A treasure room at (3,2) in front of other rooms ends the route immediately (E → T) unless another path reaches it; rooms behind it are idle.

A full grid (19 rooms) can be one route of all 19 rooms when nothing forces the end; a treasure room on a cell of the other checkerboard colour than the entrance's neighbours caps it at 18.

## Encounter rules used for the placeholders

These are the rules the placeholder numbers assume. Phase 2 implements and tunes them.

- One visitor per plot at a time, walking the route from the entrance.
- In a **defender** room (Slime Nest, Guard Room), the visitor stops and fights the defender until one of them is knocked out. A knocked-out defender recovers after the encounter; defenders never die permanently.
- A **trap** (Spike Hall) does not stop the visitor. It flashes a warning, then strikes whoever is standing on it, on a fixed cycle.
- A slime hit slows the visitor's walk for a few seconds, so the next trap gets more hits in.
- The encounter ends when the visitor is defeated, or reaches the end of the route:
  - **Defeated:** the reward is paid once, straight to coins: the base rolled at spawn in the visitor's coin range, times the threat, variant, coin-bonus and event multipliers, rounded down.
  - **Reaches the end, no treasure room:** the visitor leaves. No reward, no loss.
  - **Reaches the treasure room:** it steals its theft fraction of the vaulted coins (`floor(Coins × VaultPercent / 100)` at that moment), rounded down. Unvaulted coins and rooms are never affected. A 0% share loses nothing.
- **Vault:** changing the vault share is refused (`EncounterActive`) while an encounter is running on that plot, so a theft cannot be dodged at the last second. Threat can be changed during an encounter for the next visitor; build mode interrupts the current visit.
- **Assumption (owner review):** the tutorial's Skip is locked until the player has finished one encounter (`Stats.Encounters >= 1`; later sessions satisfy this), so the first session always sees the practice fight.
- **Assumption:** removing the treasure room puts nothing at risk (vaulted coins are 0 without it) and removes the spawn-rate bonus. While idle, the next-visitor time follows the current interval, so lowering the share or removing the treasure room after a fast timer was set makes the wait longer again.
- **Assumption:** rewards and theft round down to whole coins.
- **Assumption (owner review):** coins spent during an encounter (shop, upgrades) are no longer at risk; theft uses the vaulted coins when the visitor reaches the treasure.

## Placeholder values

Values live in `src/server/Definitions/Balance.luau`. All are hypotheses for playtesting.

| Visitor | Health | Attack | Walk speed | Coins | Theft |
| --- | ---: | ---: | ---: | ---: | ---: |
| Practice Adventurer (tutorial only) | 20 | 5 every 1.0 s | 4 studs/s | 8–12 | 0% |
| Novice | 60 | 10 every 1.0 s | 4 studs/s | 18–26 | 10% |
| Armored Challenger (threat 4+) | 160 | 14 every 1.0 s | 3.5 studs/s | 45–65 | 25% |

| Room (tier) | Values (level 1; +25% damage and health per level above 1) | Cost |
| --- | --- | ---: |
| Slime Nest (Common) | Defender 40 health, 6 damage every 1.0 s, each hit slows 75% for 6 s | Starter |
| Spike Hall (Common) | 15 damage per strike, 1.2 s cycle with a 0.4 s warning | Tutorial grant |
| Guard Room (Common) | Defender 80 health, 12 damage every 1.2 s | 100 coins |
| Coin Cache (Common, id `TreasureRoom`) | Vault exchange ×1.0 | Starter (optional) |
| Mushroom Cavern (Uncommon) | Spored 5 s, +50% trap damage (strikes and zones, not Burn); +10% per level | 200 coins, keeper level 3 |
| Bat Roost (Uncommon) | Defender 60 health, 6 damage every 0.4 s | 220 coins, keeper level 4 |
| Arrow Gallery (Uncommon) | 8 damage per volley, 0.8 s cycle (first after 0.3 s), anywhere in the room | 250 coins, keeper level 5 |
| Strongbox (Uncommon) | Vault exchange ×1.15 | 600 coins, keeper level 6 |
| Monster Den (Rare) | Adjacent defenders +20% damage and health (every unit), once each (strongest adjacent Den); +5% per level. Perk Xp +5% | Loot |
| Restless Crypt (Rare) | Defender 60 health, 8 damage every 1.0 s, rises once at 50%. Perk Loot +5% | Loot |
| Flame Vent (Rare) | 10 damage per strike, 1.5 s cycle (first after 0.6 s); a hit burns 5/s for 3 s (ticks every 0.5 s). Perk Coins +5% | Loot |
| Treasury (Rare) | Vault exchange ×1.3. Perk Coins +5% | Loot |
| Frost Chamber (Epic) | Zone: in this room and the next, chilled: 40% slower (not Sure-footed) and 3 damage/s. Perk Xp +10% | Loot |
| Goblin Barracks (Epic) | Two goblins in turn: 50 health, 9 damage every 1.0 s each; the second steps in 0.5 s after the first falls. Perk Loot +10% | Loot |
| Mimic Room (Epic) | Ambush 40 damage on arrival, then defender 70 health, 10 damage every 1.0 s. Perk Coins +10% | Loot |
| Royal Vault (Epic) | Vault exchange ×1.6. Perk Coins +10% | Loot |
| Golem Forge (Legendary) | Defender 220 health, 18 damage every 1.6 s. Perks Coins and Xp +10% | Loot |
| Lich Sanctum (Legendary) | Skeleton 40 health / 8 per 1.0 s first, then lich 110 health / 15 per 1.4 s. Perks Loot and Xp +10% | Loot |
| Dragon Hoard (Legendary) | Vault exchange ×2.0; rare-variant chances ×1.25. Perks Coins and Loot +10% | Loot |
| Dragon Lair (Mythic) | Defender 300 health, breath 30 damage every 2.0 s + Burn. Perks all +10% | Loot |
| Phoenix Nest (Mythic) | Defender 150 health, 16 damage every 1.2 s; once per encounter revives the first knocked-out route defender (itself included) at full health. Perks all +10% | Loot |
| Celestial Coffer (Mythic) | Vault exchange ×2.6. Perks Coins +20% (its +10% coins ability included), Loot and Xp +10% | Loot |
| Void Gate (Secret) | Zone 10 damage/s; once per encounter, a visitor reaching its centre is sent back to the entrance keeping its damage. Perks all +15% | Loot |
| Void Vault (Secret) | Vault exchange ×3.5; thefts ×0.5. Perks all +15% | Loot |
| Scout / Cleric (Phase 7) | Scout 50 health, 8 dmg, speed 6, 22–32 coins; Cleric 70 health, 8 dmg, speed 4, heals 4/s walking (not while duelling or burning), 26–36 coins; theft 10% | Threat 2+ (Scout), 3+ (Cleric) |

Statuses: slows don't stack (the strongest of Slime and Frost applies); Sure-footed visitors ignore slows but take chill damage. Burn refreshes its duration and keeps the stronger damage. Only one treasure room of any tier can be placed (`Rooms.KindLimit`).

| Economy and timing | Value |
| --- | ---: |
| Starting coins | 0 |
| Visitor interval | 30 s after the previous encounter, minus Lure, divided by (1 + vault bonus/100), × Swarm 0.5; never below 5 s |
| Room upgrade to level 2 / 3 / 4 / 5 / 6 | 60 / 150 / 350 / 800 / 1800 coins; each level above 1 gives +25% defender damage and health and trap damage |

### Loot, rarity and progression (owner-approved 2026-11-04)

All gameplay-earned; never sold. Values in `Balance.Rarities`, `Balance.Perks`, `Balance.Loot`, `Balance.Progression` and `Balance.Permanent`.

| Rarity | Dungeon Box weight | Rare Box weight | Max level | Craft cost | Scrap return | Rooms |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Common | 60 | 0 | 3 | 5 | 2 | Slime Nest, Spike Hall, Guard Room (Coin Cache never drops) |
| Uncommon | 25 | 45 | 4 | 6 | 3 | Mushroom Cavern, Arrow Gallery, Bat Roost, Strongbox |
| Rare | 10 | 32 | 5 | 8 | 4 | Monster Den, Restless Crypt, Flame Vent, Treasury |
| Epic | 3.5 | 14 | 6 | 10 | 5 | Frost Chamber, Goblin Barracks, Mimic Room, Royal Vault |
| Legendary | 1.2 | 6 | 7 | 12 | 6 | Golem Forge, Lich Sanctum, Dragon Hoard |
| Mythic | 0.28 | 2.5 | 8 | 15 | 8 | Dragon Lair, Phoenix Nest, Celestial Coffer |
| Secret | 0.02 | 0.5 | 10 | 20 | 10 | Void Gate, Void Vault |

Both weight columns sum to 100. **Item model (2026-11-05):** a room's rarity is fixed by its definition; an instance is `{Id, Level, Modifier?}`. A box rolls the tier, then a room of that tier with `Balance.Loot.RoomWeights` (default 1; treasure rooms 0.5; Coin Cache 0). Upgrade costs to reach levels 2 to 10: 60, 150, 350, 800, 1800, 3500, 6000, 10000, 16000 (`Balance.Upgrades.Costs`). There is no rarity stat multiplier any more.

Built-in perks (`Balance.RoomPerks`) are listed per room above; Common and Uncommon rooms have none. Cap (all sources): +100% each for Coins (win rewards), Loot (drop chances) and Xp.

**Bonus order:** built-in perks and event modifiers (Lucky, Golden) of every room *on the route* are summed, the matching permanent upgrade is added, then the total is capped. Coins paid: `floor(base × threat × variant × (1 + coins) × event)`.

Base chances below are at threat 1; the threat level, variant and Lucky Stars multiply them (see "Threat levels, variants, vault and events").

| Visitor | Box chance | Blueprint chance | XP |
| --- | ---: | ---: | ---: |
| Practice | 0 | 0 | 5 |
| Novice | 6% | 12% | 10 |
| Scout | 9% | 15% | 12 |
| Cleric | 9% | 15% | 14 |
| Armored Challenger | 25% (Rare Box) | 35% | 30 |

Chances are rolled independently on Defeated only and multiplied by (1 + loot bonus) × threat × variant × event, capped at 100%. XP is multiplied by the threat XP multiplier and (1 + XP bonus), rounded down.

- **Box room** (both box types): the room is picked inside the rolled tier (equal weights, treasure rooms half). Common and Uncommon rooms need their shop level gate; if none of the tier's rooms is unlocked, the lowest-gated one is used (at level 1-2 an Uncommon roll gives the Mushroom Cavern). Rare and rarer rooms are never gated. `State.BoxOdds` shows the tier chances and the chances inside each tier.
- **Pity:** after 9 boxes in a row below Rare, the next box is Rare or better (weights renormalised; rank comes from the list order). `BoxPity` counts the streak.
- **Blueprint type:** a tier with the Dungeon Box weights (no pity, no event boost), then a room of that tier like a box. Crafting costs the tier's craft cost; scrapping an unplaced room (not the Coin Cache) returns the tier's scrap return. The 30-room cap applies to opening and crafting (the box or blueprints are kept).
- **Keeper level:** XP to the next level = 50 + 25 * (level - 1); max level 100. Each level-up gives a Dungeon Box, every 5th level a Rare Box instead. Shop (Common and Uncommon only): Guard Room 100 coins; Mushroom Cavern 200 (level 3), Bat Roost 220 (level 4), Arrow Gallery 250 (level 5), Strongbox 600 (level 6). Monster Den and Restless Crypt are no longer sold.
- **Assumption (owner review):** v2 profiles are migrated with Xp = 10 * `Stats.Wins` (the Novice rate) converted into levels, so existing testers are not locked out of shop rooms; no retroactive level-up boxes.
- **Assumption:** stacks of boxes and of blueprints per room are capped at 999.
- **Assumption (owner review):** schema v5 clamps each saved room's level to its definition's tier cap (for example a saved Epic Slime Nest at level 6 becomes a level-3 Slime Nest). Upgrade coins spent above the new cap are not refunded, and saved instance rarities and perks are dropped.
- **Assumption:** the tier sanity duel (`encounter_rooms.spec`: one room at its tier's max level vs an unkillable T1 Armored Challenger) rises Common (Guard Room 126) → Uncommon (Bat Roost 189) → Rare → Epic → Legendary → Mythic. Secret has no duelling room (Void Gate scores 83, as its value is replaying the route), so it is skipped.
- **Assumption:** the tutorial Spike Hall grant now happens once ever (`Discovered.SpikeHall`), so scrapping it cannot farm new grants.

| Permanent upgrade | Effect per level | Max level | Base cost |
| --- | --- | ---: | ---: |
| Golden Touch | +5% coins | 10 | 200 |
| Lucky Charm | +5% loot | 10 | 200 |
| Scholar | +10% XP | 5 | 250 |
| Stout Defenders | +5% defender health | 10 | 200 |
| Lure | -1 s visitor interval (never below 5 s overall) | 5 | 400 |
| Deep Vault | +5% vault exchange rate | 5 | 300 |

Cost from level L to L + 1 = round(base * 1.6^L), paid from coins. Levels never reset.

### Threat levels, variants, vault and events (owner-approved 2026-11-05)

Values in `Balance.Threat`, `Balance.Variants`, `Balance.Vault`, `Balance.Timing` and `Balance.Events`; all starting values to tune.

| Threat | Keeper level | Health & damage | Coins | XP | Drop chances | Roster (weights) |
| ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 1 | ×1.00 | ×1.0 | ×1.0 | ×1.00 | Novice 100 |
| 2 | 4 | ×1.35 | ×1.5 | ×1.4 | ×1.25 | Novice 70, Scout 30 |
| 3 | 8 | ×1.70 | ×2.0 | ×1.8 | ×1.50 | Novice 50, Scout 30, Cleric 20 |
| 4 | 13 | ×2.05 | ×2.5 | ×2.2 | ×1.75 | Novice 35, Scout 30, Cleric 25, Armored Challenger 10 |
| 5 | 19 | ×2.40 | ×3.0 | ×2.6 | ×2.00 | Novice 20, Scout 30, Cleric 30, Armored Challenger 20 |
| 6 | 26 | ×2.75 | ×3.5 | ×3.0 | ×2.25 | Novice 10, Scout 25, Cleric 35, Armored Challenger 30 |

- The tutorial always uses threat 1 and the Practice visitor first. The player's choice is saved (`Threat`); it is refused above the unlocked tier (`ThreatLocked`) and during an encounter.
- **Assumption:** the next visitor is rolled from the roster when the timer starts (shown as `NextVisitorId`) and re-rolled when the threat level changes. The variant is a surprise, rolled at spawn.

| Variant | Base chance | Health | Coins | Drop chances | Extra |
| --- | ---: | ---: | ---: | ---: | --- |
| Elite | 5% | ×1.5 | ×2 | ×2 | |
| Shiny | 1% | ×1.2 | ×3 | ×1 | guaranteed Dungeon Box |
| Gilded | 0.2% | ×2 | ×10 | ×1 | guaranteed Rare Box |

Variant chances × (1 + 0.5 × vault bonus/100) × Rare Invasion 3. Practice never gets a variant. **Assumption:** variants scale health only (damage follows the threat level).

**Vault exchange:** `VaultPercent` 0–100 (whole). Vaulted = floor(Coins × percent / 100) while a Treasure Room is placed, else 0. Rate = 1.0 × the treasure room's Exchange (×1.0 Coin Cache … ×3.5 Void Vault) × (1 + 0.1 × (level − 1) + 0.05 × Deep Vault level). Bonus % = percent × rate. Example: 100% with a level-1 Coin Cache halves the 30 s interval to 15 s and makes variants 1.5× as likely. **Assumption:** the treasure room no longer shortens the interval by itself (the old 20 s), so a 0% share has no risk and no speed-up.

**Server events** (one at a time, 10 minutes, a random one every 35–50 minutes; off in Studio unless `RunInStudio`): Golden Hour coins ×2; Lucky Stars drop chances ×2; Rare Invasion variant chances ×3; Blessed Boxes Epic-and-rarer box weights ×2 (odds shown accordingly); Swarm visitor interval ×0.5 (still ≥ 5 s). A room from a box opened during an event gets a modifier with 25% chance (one at most): Blazing +15% damage, Lucky +10% loot chance, Golden +10% coins (Lucky and Golden count like perks, only while placed, under the same caps). **Assumption:** an event's effects apply when the reward is resolved, so an event that ends mid-encounter no longer counts.

Why these numbers (rough arithmetic, to be confirmed in Phase 2):

- **Practice vs slime:** the slime deals about 24 damage over four attacks and wins easily. The first encounter is a guaranteed, readable win.
- **Novice vs slime, then spikes:** the slime takes about 4 s to knock out and deals about 24 damage (36 health left). A visitor ends its walk at the centre of the last room, so the slowed novice (1 stud/s) spends about 3 s on the spike hall's inner half, taking three strikes (45) against 36 health. It is defeated (checked in `encounter_sim.spec`). The first tuning, 50% for 3 s, left it with only one strike and an escape, so the slow was strengthened.
- **Novice vs spikes, then slime:** at full speed the novice crosses in about 1.5 s and takes one or two strikes (15–30), then about 24 from the slime. It usually escapes. This is the "order matters" lesson.
- **Guard Room at 100 coins:** with about 30 from the tutorial, about four more novice wins. At roughly 45 s per visit, that is about 4–5 minutes without a treasure room, and less with one.

## First five minutes

| Time | What happens | Teaches |
| --- | --- | --- |
| 0:00 | Player joins and is assigned a plot. Overview camera shows the entrance and the slime nest. | This is your dungeon |
| ≤0:15 | Practice adventurer arrives; the slime knocks it out; +8–12 coins. | Encounters are automatic; defenders earn coins |
| ~0:30 | Tutorial grants a Spike Hall and highlights (3, 3) behind the slime. Player places it. | Building and the route |
| ~0:45 | A novice arrives, gets slowed by the slime and crosses the spikes slowly; +18–26 coins if defeated. Outcome text explains why. | Room order matters |
| ~1:15 | Tutorial offers the treasure room: choose a vault share for faster visitors and rarer variants, but theft. The player may place it at (3, 4) or skip. If placed, the tutorial teaches the **vault share** (step id `BankVault`, advanced by `SetVaultPercent`). | Optional risk |
| 1:30–4:30 | Automatic novices. Coins build toward the Guard Room. | The earn loop |
| ~4:30 | Tutorial points to the shop: buy the Guard Room and place it, which may mean moving rooms to keep one chain. | Shopping and rearranging |
| Later | Keeper level 4 unlocks threat level 2; the HUD's next goal shows what comes next. | Optional stronger visitors |

The tutorial must recover from unexpected actions: removing the slime, skipping the treasure room, placing the spikes elsewhere. It must also be skippable on later visits.

## MVP scope

**In:** one plot per player; the 5 × 4 grid; Entrance, Slime Nest, Spike Hall, Guard Room and the optional Treasure Room; the Practice, Novice and Armored Challenger visitors; a single chain route; draft editing with commit/cancel; vault share and theft; a guaranteed shop; at least one upgrade; tutorial; persistence; mouse and touch. Graybox art is fine.

**Out:** randomized rewards or gacha; paid randomized items; offline earnings; player raiding or theft between players; a separate monster inventory; branching paths, loops or a second floor; room rotation; materials; offline visitors; console/gamepad-specific UI; VR.

## Target inputs and devices

- **Desktop:** mouse and keyboard.
- **Mobile:** touch on phones and tablets, landscape. Test the smallest common phone (Studio device emulator, about 667 × 375) and a tablet.
- **Assumption:** gamepad and console UI are out of MVP scope. Nothing should block them later: no hover-only actions, and every action reachable by tap.
- Touch targets at least 44 px; text readable at phone size; respect safe areas.

## Phase 0 status

| Item | Status |
| --- | --- |
| GDD reviewed; grid and treasure-room conflict resolved with the owner | Done |
| Placeholder values selected | Done, in `Balance.luau` |
| Grid, first route and first five minutes sketched | Done, above |
| Initial room and visitor definitions | Done, in `src/server/Definitions/` and checked by `tests/luau/definitions.spec.luau` |
| Rojo project repaired (missing `Loader` module) | Done |
| Naming conventions, asset ownership, source control, issue tracking | Done, in [DEVELOPMENT.md](DEVELOPMENT.md) |
| Repeatable playtest checklist | Done, in [PLAYTEST_CHECKLIST.md](PLAYTEST_CHECKLIST.md) |
| Private published test place | Place `78621805707922` ("Build a Dungeon!") exists. **Owner to confirm it is private** in the Creator Dashboard |
| Studio place synced with Rojo and run without errors | Done 2026-11-04: synced into place `78621805707922`, played in Studio, and both server and client required the definitions with no script errors. The only console output was an asset-type warning for `rbxassetid://203785492`, which no instance in the place references (Studio or plugin noise) |
| Definitions spec | 6/6 pass, run in Studio. It was also checked to fail on deliberately broken values |
| Exit check: another developer can sync and run the empty plot | Pending: needs a second person or a fresh clone |

### Chest room progression, 2026-11-06

Chest rarity odds and room-pool changes are recorded in the GDD. Royal Guard uses 84 health and 12.3 damage per 1.2 seconds; Crystal Guard uses 88 health and 12.6 damage per 1.2 seconds. Crystal Sentry, Crystal Barricade, Prism Gallery, Prism Sentinel, Prism Sanctum and Prism Bastion use their matching Royal mechanics with modest stat increases; their numbers are in `Balance.luau`. These estimates need encounter and economy playtests.
