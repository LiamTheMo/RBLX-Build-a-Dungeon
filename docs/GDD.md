# Build a Dungeon — Game Design Document

**Status:** Working design | **Platform:** Roblox, mobile and desktop | **Genre:** Relaxed dungeon management and collection

## Vision

Build a dungeon that attracts NPC adventurers, defeats them and earns treasure. Arrange collectible rooms, monsters and traps into combinations, then reinvest rewards to grow the dungeon. The player is the dungeon keeper: they build and manage rather than personally running through rooms or controlling tiny troops.

The experience is playful and mostly relaxing. Players may raise the threat level for tougher, better-paying visitors or keep part of their coins in the vault for faster visitors and rarer finds. Failure causes a recoverable setback; it never destroys owned rooms, monsters, or permanent progress. Every dungeon should be satisfying to watch and feel personal enough to show friends.

### Pillars

1. **A satisfying machine:** Room interactions are visible and understandable. A slime slows an adventurer before a spike trap hits.
2. **Make it yours:** Layout, monster choices, themes and decorations shape an individual creation.
3. **A grind with decisions:** Players pursue useful building pieces, upgrades and collections. New content changes decisions, not just numbers.
4. **Cozy with optional risk:** Safe play remains viable. Stronger visitors and exposed treasure are voluntary choices.
5. **Easy to start, deep to arrange:** Players understand their first encounter quickly and discover combinations over time.

### Non-goals

No direct dungeon-crawler combat or player-controlled troop system in the core loop. No handcrafted map per run: reusable authored rooms snap onto a grid. No forced PvP or theft from another player's persistent account. Plans and tuning targets below are hypotheses, not promises of retention or revenue.

## Core loop and first session

**Place rooms and defenses → attract NPC adventurers → watch encounters → collect rewards → acquire and improve dungeon pieces → rearrange and raise the threat level.**

A new player spawns at a plot with an entrance and a slime nest. A practice adventurer arrives, fights the slime and drops coins if defeated; without a treasure room, rewards go straight to coins. The tutorial guides the player to place a free spike hall after the slime. The next visitor demonstrates that a slowed adventurer stays on spikes longer. The tutorial then offers the treasure room as an optional upgrade in risk and reward: choose a share of coins to keep in the vault for more frequent visitors and rarer variants, at the cost of possible theft. The player earns enough for a guaranteed basic room, then unlocks higher threat levels as their keeper level grows.

Aim for the first encounter within roughly 15 seconds; validate with playtests. Onboarding should recover from unexpected actions, be skippable on later visits, and explain why encounters succeed or fail.

Over longer sessions, players unlock rooms, develop layouts, pursue collections, improve their dungeon, and decorate their plot. Short-term goals are the next purchase; medium-term goals are synergies and visitor tiers; long-term goals are themed builds and rare finds. There is no mandatory rebirth in the initial design.

## Building

Each player owns an isolated plot. Start with a 5 × 4 grid as a tunable prototype and a fixed entrance. The dungeon is a miniature diorama: each room is a small open square about the height of a player's avatar, and scaled-down NPC adventurers walk through it. A room occupies one cell and has a doorway on all four sides, so orthogonally adjacent rooms always connect and no rotation is needed. **Rooms may be placed in any cell except the entrance** (owner-approved 2026-11-05); a layout is never refused for its shape, so branches, loops and disconnected rooms are all allowed. The server still checks ownership, each room instance placed once, grid bounds and room limits (at most one treasure room). The server computes the visitors' **route**: the longest simple path (most rooms) through orthogonally adjacent rooms, starting at a room next to the entrance. The **treasure room is optional** (at most one). If it is placed and connected, the route is the longest path that ends at the treasure room. If it is not connected, the route is the longest path and the treasure room is off the route: nothing can be stolen and the vault allocation has no effect. Equal-length routes are decided by cell order, so the preview and the committed dungeon always show the same route. Rooms that are not on the route are **idle**: they stay placed and visible but do not fight and give no perks, modifiers or vault effects. A Monster Den only boosts defenders next to it on the route. The build preview marks the route and the idle rooms. Invalid commits show a clear reason, and cancelling restores the last committed layout. Visitors pause during editing, so a player can rearrange a complete route without trapping themselves.

An angled overview camera makes the dungeon readable. In build mode, players select an inventory piece, preview its position and connections, then place, move or remove it. Rooms are not rotated in the MVP. A placed instance returns to inventory when removed. No instance can be placed twice.

### Room roster (item model owner-approved 2026-11-05)

Every room type has **one fixed rarity**. A room's stats, perks and ability come from its type; an owned room only records its level (and an optional event modifier). Common and Uncommon rooms are sold in the shop for coins (with keeper-level gates); Rare and rarer rooms come only from boxes and blueprints. Only **one treasure room** (of any tier) can be placed. Numbers are starting values in `Balance.luau` ([PHASE0.md](PHASE0.md)).

| Room | Tier | Role | Function | Availability |
| --- | --- | --- | --- | --- |
| Entrance | — | Fixed | Where visitors arrive | Permanent |
| Slime Nest | Common | Defender | 40 HP, 6 dmg / 1.0 s; each hit slows 75% for 6 s | Starter |
| Spike Hall | Common | Trap | 15 dmg every 1.2 s after a warning flash | Tutorial grant |
| Guard Room | Common | Defender | 80 HP, 12 dmg / 1.2 s | Shop 100 |
| Coin Cache (id `TreasureRoom`) | Common | Treasure | Vault exchange ×1.0 | Starter, optional |
| Mushroom Cavern | Uncommon | Trap | Spored 5 s: +50% trap damage | Shop 200, level 3 |
| Bat Roost | Uncommon | Defender | 60 HP, 6 dmg / 0.4 s | Shop 220, level 4 |
| Arrow Gallery | Uncommon | Trap | 8 dmg volley every 0.8 s, anywhere in the room | Shop 250, level 5 |
| Strongbox | Uncommon | Treasure | Vault exchange ×1.15 | Shop 600, level 6 |
| Monster Den | Rare | Support | Adjacent route defenders +20% damage and health | Loot |
| Restless Crypt | Rare | Defender | 60 HP, 8 dmg / 1.0 s; rises once at 50% | Loot |
| Flame Vent | Rare | Trap | 10 dmg every 1.5 s, and Burn (5 dmg/s for 3 s) | Loot |
| Treasury | Rare | Treasure | Vault exchange ×1.3 | Loot |
| Frost Chamber | Epic | Trap (zone) | Chilled here and in the next room: 40% slower, 3 dmg/s | Loot |
| Goblin Barracks | Epic | Defender | Two goblins in turn, 50 HP / 9 dmg each | Loot |
| Mimic Room | Epic | Defender | Ambush first bite 40, then 70 HP / 10 dmg; looks like a chest | Loot |
| Royal Vault | Epic | Treasure | Vault exchange ×1.6 | Loot |
| Golem Forge | Legendary | Defender | Tank: 220 HP, 18 dmg / 1.6 s | Loot |
| Lich Sanctum | Legendary | Defender | Summons a skeleton (40 HP / 8) that fights first, then the lich (110 HP / 15) | Loot |
| Dragon Hoard | Legendary | Treasure | Vault exchange ×2.0, +25% rare-variant chance | Loot |
| Dragon Lair | Mythic | Defender | 300 HP; breath 30 dmg every 2 s + Burn | Loot |
| Phoenix Nest | Mythic | Defender | 150 HP / 16 dmg; once per encounter revives the first route defender knocked out, at full health (itself included) | Loot |
| Celestial Coffer | Mythic | Treasure | Vault exchange ×2.6, +10% coins | Loot |
| Void Gate | Secret | Trap (zone) | 10 dmg/s inside; once per encounter sends the visitor back to the entrance, keeping its damage | Loot |
| Void Vault | Secret | Treasure | Vault exchange ×3.5, thieves take half | Loot |

**Built-in perks** (coins, loot chance or XP; perks of rooms on the route add up, capped): Rare rooms one kind +5%, Epic one kind +10%, Legendary two kinds +10%, Mythic and Secret all three (+10% / +15%). Common and Uncommon rooms have none. **Statuses:** Burn ticks damage and stops Mender healing; slows don't stack (the strongest applies) and Sure-footed visitors ignore them but still take chill damage; Spored raises trap strikes and zone damage, not Burn.

Phase 7 visitors: **Scout** (50 health, fast, Sure-footed: immune to slows; 22–32 coins, steals 10%) and **Cleric** (70 health, Mender: heals 4 HP/s while walking, not while duelling; 26–36 coins, steals 10%). Since 2026-11-05 visitors come from the active threat level's roster (see "Threat levels, variants and the treasure vault"); the next one is shown with its traits before it enters. A collection index records the rooms owned and visitors met.

Each room has a role, visible state, cost and upgrade cap. Upgrades should preserve the room's identity. A common room must remain useful in combinations even after rare pieces appear.

For MVP, defenders belong to their rooms and recover automatically between encounters. They cannot die permanently. Separate collectible monster instances are a post-MVP experiment, with explicit compatible slots, placement limits and ownership checks. Traps telegraph activation and have cooldowns.

## Visitors and encounters

NPC adventurers automatically arrive at an understandable interval when a valid dungeon is ready; a treasure room on the route shortens that interval. Only one visitor per plot is active in the MVP. The visitor follows the server-computed path, encounters defenses and either is defeated or reaches the end of the route. Without a treasure room, a visitor who reaches the end leaves with nothing and the player earns nothing from that visit.

- **Novice:** Low health and modest reward; the default safe visitor.
- **Armored challenger:** Tougher, higher reward and higher potential vault loss; a regular visitor from threat level 4.

Later visitors may resist poison, avoid traps or heal allies. Their traits and potential rewards should be visible before they enter. Strong visitors test a layout rather than relying on surprise punishment.

On victory, the server adds the reward once, straight to coins: a whole number rolled in the visitor's coin range, times the threat, variant, coin-bonus and event multipliers. If a visitor reaches the treasure room, it steals its percentage of the *vaulted coins* (the share the player chose); unvaulted coins and owned items are never affected. With a 0% share, nothing is lost. Defenders recover for the next visit. A disconnected or interrupted encounter is cancelled without reward or robbery. Unique encounter IDs and server-side state prevent duplicate payouts.

## Economy and risk

- **Coins:** Persistent currency for guaranteed rooms and upgrades. Every reward goes here.
- **Vault share (since 2026-11-05):** while a treasure room is placed, the player chooses what percentage of their coins is vaulted (0–100%). Vaulted coins are exposed to NPC robbery; the rest is safe.

The treasure room is the optional risk. Without one, or with a 0% share, nothing can be stolen. With a share, visitors arrive more often and rare variants are more likely, but a visitor who reaches the treasure room steals part of the vaulted coins.
- **Materials:** Optional later resource from specific visitors; add only after the coin loop works.

The exchange (initial test rule): spawn-rate bonus % = vault share × rate, with rate = 1.0 × the placed treasure room's exchange (Coin Cache ×1.0 up to Void Vault ×3.5) × (1 + 10% per level above 1), +5% per Deep Vault level. The visitor interval is divided by (1 + bonus/100), never below 5 s, and rare-variant chances are multiplied by (1 + 0.5 × bonus/100). Show the current bonus and robbery risk. Players who vault nothing must still make worthwhile progress. Stored gold does not generate passive interest. Coin pickups are visual feedback; the server adds rewards automatically, so players are not forced to click every coin.

### Initial tuning hypotheses

| Action | Starting value |
| --- | ---: |
| Novice win | 18–26 coins |
| Novice theft | 10% of vaulted coins |
| Challenger win | 45–65 coins |
| Challenger theft | 25% of vaulted coins |
| Guard Room | 100 coins |
| First upgrade | 60 coins |
| Automatic visitor interval | 30 seconds after the previous encounter, divided by (1 + vault bonus/100), at least 5 s |

These are placeholders. Test time to first purchase and the value of safe versus risky play. Serialize vault changes, purchases and encounter resolution per player so simultaneous requests cannot duplicate or lose currency. Offline earnings are out of MVP and need their own cap and economy review.

## Collection and rarity

The MVP shop is guaranteed. Gameplay-earned boxes (see "Loot, rarity and progression") are the randomized route; as with any mystery chest, test with displayed contents and actual probabilities, duplicate conversion or a pity route, and a guaranteed path to essential functional rooms. Describe and test these rules before launch. Any future paid randomized reward requires a separate review of current Roblox rules and applicable regional requirements.

Tiers (lowest to highest): Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret, with more to come (data-driven). Rarity signals acquisition and discovery, not automatic superiority. Rare pieces should enable unusual combinations, not invalidate all starter pieces. A collection index shows owned items, their roles and sources, with silhouettes for undiscovered pieces.

## Loot, rarity and progression (owner-approved 2026-11-04)

All of this is earned through play. Boxes and blueprints are never sold for Robux. Every box shows its real odds before it is opened.

- **Drops:** a defeated adventurer may drop a **Dungeon Box** and/or a **Blueprint**. Stronger visitors drop more often. The base chance is multiplied by the player's loot bonus.
- **Boxes (item model of 2026-11-05):** opening a box first rolls a **tier** with the tier odds (and pity), then a **room of that tier** (equal weights per room; rarer treasure rooms count half, and the starter Coin Cache never drops). Common and Uncommon rooms follow the shop level gates; rarer rooms are never gated. The box shows both the tier chances and the room chances inside each tier, exactly as rolled. A **Rare Box** (from level-ups and challengers) shifts the tier odds upward. **Pity:** a box that would be the 10th in a row without Rare or better is guaranteed to be at least Rare.
- **Blueprints:** each blueprint belongs to one room type; a blueprint drop picks a tier with the Dungeon Box odds, then a room. Crafting cost depends on the room's tier: Common 5, Uncommon 6, Rare 8, Epic 10, Legendary 12, Mythic 15, Secret 20. This is the guaranteed, non-random route to every room. Scrapping an unwanted room returns 2 / 3 / 4 / 5 / 6 / 8 / 10 blueprints by tier (duplicate conversion).
- **Rarity (7 tiers):** Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret. A room's tier is fixed by its type (see "Room roster"). Higher tiers have stronger mechanics, a higher upgrade cap (3 / 4 / 5 / 6 / 7 / 8 / 10) and built-in perks (Rare and up). Secret is about 1 in 5,000 Dungeon Boxes and has a shimmering prismatic edge. Rarity signals discovery: a well-arranged Common layout must stay viable.
- **Room upgrades:** every placeable room can be upgraded with coins up to its tier's cap. Defenders and traps hit harder and last longer (+25% per level). The Monster Den's boost grows. Treasure rooms raise their vault exchange rate (+10% per level).
- **XP and keeper level:** every defeated adventurer gives XP. Levels unlock the rarer shop rooms and give a box at each level-up (a Rare Box every 5 levels).
- **Permanent upgrades:** account-wide keeper upgrades bought with coins, at rising costs: Golden Touch (more coins), Lucky Charm (more loot), Scholar (more XP), Stout Defenders (defender health), Lure (shorter visitor interval) and Deep Vault (+5% vault exchange rate per level). They never reset.

Starting numbers live in `Balance.luau` and are listed in [PHASE0.md](PHASE0.md); they are hypotheses to tune in playtests. The non-random routes (shop purchases, blueprint crafting) keep every functional room reachable without luck.

## Threat levels, variants and the treasure vault (owner-approved 2026-11-05)

- **Threat levels:** attackers the keeper unlocks for better loot. Threat 1–6 unlock at keeper levels 1, 4, 8, 13, 19 and 26; the player chooses the active level (not during an encounter). Per level above 1: visitor health and damage +35%, coins +50%, XP +40%, drop chances +25%. Each level has its own visitor roster: T1 Novices, T2 adds Scouts, T3 Clerics, T4 and up the Armored Challenger as a regular visitor, with higher levels weighted toward tougher visitors. This replaces the challenger invite.
- **Rare variants**, rolled when a visitor spawns: Elite 5% (×1.5 health, ×2 coins, ×2 drop chances), Shiny 1% (×1.2 health, ×3 coins, guaranteed Dungeon Box), Gilded 0.2% (×2 health, ×10 coins, guaranteed Rare Box). The vault bonus and events raise these chances.
- **Coin ranges:** each visitor pays a range (Practice 8–12, Novice 18–26, Scout 22–32, Cleric 26–36, Armored Challenger 45–65), rolled once per encounter on the server, then multiplied.
- **Treasure vault:** see "Economy and risk". Bank and the separate vault balance are gone; existing vault gold was added to coins.
- **Server events:** about every 35–50 minutes a random 10-minute event runs for everyone: Golden Hour (×2 coins), Lucky Stars (×2 drop chances), Rare Invasion (×3 variant chances), Blessed Boxes (Epic and rarer box weights ×2), Swarm (visitors twice as often, still at least 5 s apart). During an event a room from a box has a 25% chance of one modifier: Blazing (+15% damage), Lucky (+10% loot chance) or Golden (+10% coins).
- **Drop tables:** every visitor shows its coin range, XP and the chance of every possible drop (each box and each blueprint room), plus the variant chances, at the player's current threat level, bonuses and event. Shown numbers are the ones rolled.
- **Next goal:** the HUD can show the next threat level, the next level-gated shop room and the cheapest permanent upgrade. Level-ups still grant boxes.
- **Admin tools:** listed developers and group staff (rank 254+) can start and stop events and grant coins, boxes, XP or every threat level through chat commands, for testing and live events. Every use is logged.

All numbers are starting values in `Balance.luau` (see [PHASE0.md](PHASE0.md)), to tune in playtests.

## Interface and onboarding

- **HUD:** coins, vault share and vaulted coins, current vault bonus, threat level, active server event, build access, next visitor status and the next goal (next threat level, shop room or upgrade).
- **Build mode:** room inventory, touch/mouse placement, preview, connection indicators, remove/move, and plain-language errors.
- **Encounter panel:** visitor name and variant, health, route, coin range and vault risk; concise interaction feedback.
- **Shop:** role, cost, ownership and confirmation for consequential purchases.
- **Collection:** entries, source and owned count. Never imply odds that are not real.
- **Tutorial:** contextual prompts for practice encounter, placement, choosing a vault share and first purchase; recover if the player takes unexpected actions. The tutorial always uses threat level 1.
- **Accessibility:** readable contrast, large touch targets, icons plus text, reduced camera motion/effects and adjustable audio. Test safe areas and small phones.

## Visual, animation and audio direction

A playful toy-dungeon style with chunky silhouettes, warm treasure lighting and recognizable rooms at overview zoom. The dungeon reads as a miniature diorama beside the player's full-size avatar: rooms about avatar height, with small adventurers and defenders inside. Avoid gore. Use a modular kit with consistent wall, floor and doorway dimensions. Color can communicate room roles, but state must not rely on color alone.

MVP may use graybox parts. For release, create entrance, vault, room modules and props, monsters and visitor models. Defenders need idle, attack and defeat/recovery animations; visitors need idle, walk, attack, hit and win/defeat states. Traps need anticipation and activation. Add restrained hit flashes, coin trails, vault feedback and clear telegraphs. Pool/cap effects and support reduced effects. Audio covers ambience, placement, attacks, traps, rewards, theft and interface; separate music and effects volume. Critical information must remain clear with sound off.

## Social and future direction

At release, allow read-only plot viewing if server layout permits. Viewing cannot change another player's economy. Player raiding is a later proposal: owners opt in and publish a versioned dungeon snapshot; visitors interact with an isolated simulated copy. Owners never lose persistent gold or items. Rewards are game-funded, capped and protected against self-farming. Whether a visitor controls their avatar or interacts in another way requires a separate prototype; it is not yet decided.

## Technical and data design

The existing Rojo configuration maps `src/shared`, `src/server` and `src/client`; no framework is assumed.

- **Shared:** Versioned room/visitor definitions, balance data, grid rules and message contracts. The server still validates all requests.
- **Server:** Plot assignment, ownership, inventory, placement and path validation, encounter state machine, combat, currency, shop and persistence.
- **Client:** Camera, input, build preview, UI, animations and effects. The client requests actions; it cannot grant currency or decide results.
- **Profile:** Schema version, coins, vault share, threat level, stable inventory instance IDs, placements, upgrades, unlocks and onboarding state. Define defaults, migrations and repairs for invalid IDs, duplicate instances and broken layouts.
- **Persistence:** Server-side session ownership/locking strategy, retry/backoff, periodic and lifecycle saves, shutdown handling and published-place failure testing. A failed load is not a new profile: block progression and do not overwrite an inaccessible save with defaults. Document actual guarantees and limitations.
- **Security:** Validate ownership, costs, grid bounds, connectivity, encounter state and remote argument types. Rate-limit requests; serialize transactions; make encounter resolution idempotent. Clean up NPCs and connections on exit.
- **Performance:** Cap rooms and NPCs, clean up or pool effects, avoid per-frame simulation where possible, and profile multiple plots on representative mobile hardware.

## Milestones and success questions

**Playable MVP:** Persistent plot, valid placement and rearrangement, automatic visitors, correct win/loss and vault behavior, guaranteed purchases/upgrades, onboarding and reconnect persistence. Mouse and touch work. Placeholder art is acceptable.

**Full release:** MVP plus a tested content roster, modular art, animation, VFX, audio, responsive UI, accessibility, stable persistence, performance testing and an operations process. Scope follows actual capacity and playtest outcomes.

Measure tutorial completion, time to first placement/purchase, layout edits, encounters, vault-share behavior, threat-level choices, session length, returns and errors. Establish targets from an initial test instead of inventing success claims. Ask testers if they understand why they won or lost, what they want next, and whether rearranging helped.

Open questions: Is watching encounters engaging between edits? Is vault risk understandable or stressful? How often should visitors arrive? Are rooms or upgrades more motivating? How many rooms can a server support? Does branching improve play enough to justify complexity? Do players feel forced to place a treasure room, or is safe play still worthwhile? Fix readability and the core loop before adding more content.

## Change log

- **2026-11-05 (owner-approved, item model):** Each room type has one fixed rarity; room instances no longer roll a rarity, a stat multiplier or perks (perks are built into Rare and rarer rooms). Boxes roll a tier, then a room of that tier; odds show both. Blueprint costs and scrap returns depend on the tier. The shop sells only Common and Uncommon rooms; Monster Den and Restless Crypt became Rare (box/blueprint only), Mushroom Cavern Uncommon. A treasure line (Coin Cache, Strongbox, Treasury, Royal Vault, Dragon Hoard, Celestial Coffer, Void Vault) replaces the treasure room's rarity; only one treasure can be placed. New rooms: Arrow Gallery, Bat Roost, Flame Vent, Frost Chamber, Goblin Barracks, Mimic Room, Golem Forge, Lich Sanctum, Dragon Lair, Phoenix Nest, Void Gate. Profile schema v5 drops instance rarity and perks and clamps levels to the room's tier cap.

- **2026-11-05 (owner-approved, free placement):** Rooms may be placed in any cell except the entrance; layouts are no longer refused for branches, loops, disconnected rooms or a treasure room that is not last. The server computes the route as the longest simple path from the entrance (ending at the treasure room when it is connected; ties broken by cell order). Rooms off the route are idle and give no perks or bonuses; an off-route treasure room has no vault effect and cannot be robbed. Saved layouts are no longer reset for their shape.
- **2026-11-05 (owner-approved):** Threat levels T1–T6 (unlocked by keeper level, chosen by the player) replace the invited Armored Challenger and the fixed visitor rotation. Rare Elite/Shiny/Gilded variants. Coin ranges per visitor. The treasure vault allocation (a chosen share of coins at risk for faster visitors and rarer variants) replaces Bank, the vault balance and the vault reward bonus (profile schema v4 adds the vault balance to coins). Server events with room modifiers, admin chat commands, full drop tables and next-goal data.

- **2026-11-05 (owner-approved):** 7 tiers, data-driven: Epic, Legendary and Secret added to Common, Uncommon, Rare and Mythic. Existing Mythic rooms keep their rarity; their max level rises to 8.
- **2026-11-04 (Phase 7 systems depth):** Monster Den, Mushroom Cavern and Restless Crypt (shop rooms), Scout and Cleric visitors with traits, a deterministic automatic-visitor rotation, a `Discovered` collection index (profile schema v2). Numbers in `Balance.luau`; no loot boxes in this step.
- **2026-11-04 (owner-approved):** Added loot drops (Dungeon/Rare Boxes with shown odds and pity, room blueprints with crafting and scrapping), rarity variants with coin/loot/XP perks, upgrades for every room, keeper XP and levels, and permanent coin upgrades. No paid randomized rewards. See "Loot, rarity and progression".
- **2026-11-04 (Phase 0, owner-approved):** The treasure room is optional (at most one, and it must end the route). Without it, rewards go straight to banked coins and nothing can be stolen. With it, visitors arrive more often and rewards go to the vault with a bonus, but visitors can steal from it. Rooms are small open squares about avatar height with a doorway on every side (no rotation), and visitors are miniature adventurers. This resolves a conflict in the earlier draft, where a fixed entrance and a fixed treasure room one room apart left no space to add the tutorial's spike hall. Derived details are in [PHASE0.md](PHASE0.md).


## Central room shop and upgrader

**Lobby layout:** Plan for six player plots around a shared central plaza. Put a clearly signposted Room Shop and Room Upgrader on the plaza so players can reach them from any plot. Their exact placement and six-plot server performance need prototyping. Players can browse without interrupting another player's dungeon. Keep shop and upgrade interactions accessible on mobile.

**Room Shop:** Offer a rotating or fixed selection of guaranteed basic rooms purchased with banked coins, alongside room boxes earned or purchased using gameplay currency once that system has been tested. The guaranteed selection must include the essentials needed to build a functional dungeon. A box shows its actual possible contents and probabilities before purchase, and its contents are awarded by the server. Define duplicate conversion or a pity path before boxes ship. A rare room should enable a distinct strategy rather than simply outclass every basic room. The MVP launches with guaranteed purchases; boxes are a post-MVP addition.

**Room Upgrader:** Select an owned room instance and preview its current stats, next upgrade, cost and maximum level before confirming. The server validates ownership, balance, upgrade cap and encounter/build state, deducts the cost and updates the instance atomically. The upgrade applies to that instance whether stored or placed; if placed, apply gameplay changes between encounters. A visible station supports discovery, while a future remote upgrade shortcut can be evaluated for convenience.

**Rare visitor drops:** As a working assumption, rare drops come from defeated NPC adventurers, not the accounts of other players. A visitor may drop a room blueprint, room-box token, cosmetic or upgrade material in addition to its regular vault-gold reward. Show the source and actual chance in a collection or visitor panel once probabilities are defined. Permanent item drops are awarded to inventory by the server exactly once on encounter victory; an NPC stealing vault gold does not remove them. Duplicate blueprints need a defined conversion or guaranteed-progress route. In the MVP, use a scripted tutorial reward or no rare drops; introduce random drops after persistence and baseline balance have been validated.

**Future player raids:** If other-player raids are added, the game may award capped rare rewards for completing a raid against an opted-in snapshot. Rewards must be generated by the game; never remove another player's rooms, items or banked money. Determine anti-farming, odds and reward limits during the raid prototype.
