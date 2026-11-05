# Build a Dungeon — Game Design Document

**Status:** Working design | **Platform:** Roblox, mobile and desktop | **Genre:** Relaxed dungeon management and collection

## Vision

Build a dungeon that attracts NPC adventurers, defeats them and earns treasure. Arrange collectible rooms, monsters and traps into combinations, then reinvest rewards to grow the dungeon. The player is the dungeon keeper: they build and manage rather than personally running through rooms or controlling tiny troops.

The experience is playful and mostly relaxing. Players may invite stronger visitors or leave treasure unbanked for better rewards. Failure causes a recoverable setback; it never destroys owned rooms, monsters, or permanent progress. Every dungeon should be satisfying to watch and feel personal enough to show friends.

### Pillars

1. **A satisfying machine:** Room interactions are visible and understandable. A slime slows an adventurer before a spike trap hits.
2. **Make it yours:** Layout, monster choices, themes and decorations shape an individual creation.
3. **A grind with decisions:** Players pursue useful building pieces, upgrades and collections. New content changes decisions, not just numbers.
4. **Cozy with optional risk:** Safe play remains viable. Stronger visitors and exposed treasure are voluntary choices.
5. **Easy to start, deep to arrange:** Players understand their first encounter quickly and discover combinations over time.

### Non-goals

No direct dungeon-crawler combat or player-controlled troop system in the core loop. No handcrafted map per run: reusable authored rooms snap onto a grid. No forced PvP or theft from another player's persistent account. Plans and tuning targets below are hypotheses, not promises of retention or revenue.

## Core loop and first session

**Place rooms and defenses → attract NPC adventurers → watch encounters → collect and bank rewards → acquire and improve dungeon pieces → rearrange and invite stronger visitors.**

A new player spawns at a plot with an entrance and a slime nest. A practice adventurer arrives, fights the slime and drops coins if defeated; without a treasure room, rewards go straight to banked coins. The tutorial guides the player to place a free spike hall after the slime. The next visitor demonstrates that a slowed adventurer stays on spikes longer. The tutorial then offers the treasure room as an optional upgrade in risk and reward: more frequent visitors and a growing vault bonus, at the cost of possible theft. The player earns enough for a guaranteed basic room, then learns that a stronger challenger is optional.

Aim for the first encounter within roughly 15 seconds; validate with playtests. Onboarding should recover from unexpected actions, be skippable on later visits, and explain why encounters succeed or fail.

Over longer sessions, players unlock rooms, develop layouts, pursue collections, improve their dungeon, and decorate their plot. Short-term goals are the next purchase; medium-term goals are synergies and visitor tiers; long-term goals are themed builds and rare finds. There is no mandatory rebirth in the initial design.

## Building

Each player owns an isolated plot. Start with a 5 × 4 grid as a tunable prototype and a fixed entrance. The dungeon is a miniature diorama: each room is a small open square about the height of a player's avatar, and scaled-down NPC adventurers walk through it. A room occupies one cell and has a doorway on all four sides, so orthogonally adjacent rooms always connect and no rotation is needed. The server computes traversable connections; the MVP supports one unambiguous path with no loops or branches. A valid layout is therefore one chain that starts at the entrance, where each room touches only the rooms before and after it on the route. The route ends at its last room. The **treasure room is optional**: a player may place at most one, and when placed it must be the last room on the route. Players can make temporarily disconnected edits in a draft layout between encounters; the server commits the draft only when it has a valid route. Invalid commits show a clear reason, and cancelling restores the last valid layout. Visitors pause during editing, so a player can rearrange a complete route without trapping themselves.

An angled overview camera makes the dungeon readable. In build mode, players select an inventory piece, preview its position and connections, then place, move or remove it. Rooms are not rotated in the MVP. A placed instance returns to inventory when removed. No instance can be placed twice.

### Initial room roster

| Room | Function | Availability |
| --- | --- | --- |
| Entrance | Fixed starting point for visitors | Free, permanent |
| Slime Nest | Defender attacks and briefly slows visitors | Starter |
| Spike Hall | Periodic damage while a visitor stands on the active trap | Free tutorial piece; basic shop |
| Treasure Room | Optional destination and unbanked vault: more frequent visitors and a vault bonus, but visitors who reach it steal | Free starter piece, optional, at most one |
| Guard Room | Reliable single-target defense with a distinct attack cadence | Guaranteed coin purchase, MVP |
| Monster Den | Support room, no monster of its own: each Defender room next to it on the route gets +20% damage and health (once per defender, however many Dens touch it). Not upgradable | Shop, 250 coins (Phase 7) |
| Mushroom Cavern | A visitor entering becomes Spored for 5 s and takes +50% trap damage. Place before spikes. Not upgradable | Shop, 200 coins (Phase 7) |
| Restless Crypt | Skeleton defender (60 health, 8 damage per 1.0 s) that rises once at 50% health the first time it is knocked out | Shop, 300 coins (Phase 7) |

Phase 7 visitors (automatic, after the tutorial is done and 8 wins): **Scout** (50 health, fast, Sure-footed: immune to slows; reward 25, steals 10%) and **Cleric** (70 health, Mender: heals 4 HP/s while walking, not while duelling; reward 30, steals 10%). The automatic visitor follows a fixed Novice-heavy rotation and the next one is shown with its traits before it enters. A collection index records the rooms owned and visitors met.

Each room has a role, visible state, cost and upgrade cap. Upgrades should preserve the room's identity. A common room must remain useful in combinations even after rare pieces appear.

For MVP, defenders belong to their rooms and recover automatically between encounters. They cannot die permanently. Separate collectible monster instances are a post-MVP experiment, with explicit compatible slots, placement limits and ownership checks. Traps telegraph activation and have cooldowns.

## Visitors and encounters

NPC adventurers automatically arrive at an understandable interval when a valid dungeon is ready; a placed treasure room shortens that interval. Only one visitor per plot is active in the MVP. The visitor follows the server-computed path, encounters defenses and either is defeated or reaches the end of the route. Without a treasure room, a visitor who reaches the end leaves with nothing and the player earns nothing from that visit.

- **Novice:** Low health and modest reward; the default safe visitor.
- **Armored challenger:** Tougher, higher reward and higher potential vault loss; explicitly invited after the tutorial.

Later visitors may resist poison, avoid traps or heal allies. Their traits and potential rewards should be visible before they enter. Strong visitors test a layout rather than relying on surprise punishment.

On victory, the server adds the advertised reward once: to unbanked vault gold when a treasure room is placed, otherwise straight to banked coins. If a visitor reaches the treasure room, it steals the advertised percentage of the *current unbanked balance*; banked coins and owned items are never affected. If the vault is empty, nothing is lost. Defenders recover for the next visit. A disconnected or interrupted encounter is cancelled without reward or robbery. Unique encounter IDs and server-side state prevent duplicate payouts.

## Economy and risk

- **Banked coins:** Persistent, safe currency for guaranteed rooms and upgrades.
- **Vault gold:** Persistent but exposed to NPC robbery. It only accumulates while a treasure room is placed. The player can bank it through an explicit action.

The treasure room is the optional risk. Without one, every reward is banked immediately and nothing can be stolen. With one, visitors arrive more often and stored gold raises win rewards, but a visitor who reaches it steals part of the unbanked vault.
- **Materials:** Optional later resource from specific visitors; add only after the coin loop works.

Leaving gold in the vault increases future win rewards by a capped amount. Initial test rule: +1% per 100 unbanked coins, capped at +20%. Show the current bonus and robbery risk. Players who bank immediately must still make worthwhile progress. Stored gold does not generate passive interest. Coin pickups are visual feedback; the server adds rewards automatically, so players are not forced to click every coin.

### Initial tuning hypotheses

| Action | Starting value |
| --- | ---: |
| Novice win | 20 vault gold |
| Novice theft | 10% of vault |
| Challenger win | 50 vault gold |
| Challenger theft | 25% of vault |
| Guard Room | 100 banked coins |
| First upgrade | 60 banked coins |
| Automatic visitor interval | 30 seconds after the previous encounter |
| Interval with a treasure room | 20 seconds after the previous encounter |

These are placeholders. Test time to first purchase and the value of safe versus risky play. Serialize banking, purchases and encounter resolution per player so simultaneous requests cannot duplicate or lose currency. Offline earnings are out of MVP and need their own cap and economy review.

## Collection and rarity

The MVP shop is guaranteed. Gameplay-earned boxes (see "Loot, rarity and progression") are the randomized route; as with any mystery chest, test with displayed contents and actual probabilities, duplicate conversion or a pity route, and a guaranteed path to essential functional rooms. Describe and test these rules before launch. Any future paid randomized reward requires a separate review of current Roblox rules and applicable regional requirements.

Tiers (lowest to highest): Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret, with more to come (data-driven). Rarity signals acquisition and discovery, not automatic superiority. Rare pieces should enable unusual combinations, not invalidate all starter pieces. A collection index shows owned items, their roles and sources, with silhouettes for undiscovered pieces.

## Loot, rarity and progression (owner-approved 2026-11-04)

All of this is earned through play. Boxes and blueprints are never sold for Robux. Every box shows its real odds before it is opened.

- **Drops:** a defeated adventurer may drop a **Dungeon Box** and/or a **Blueprint**. Stronger visitors drop more often. The base chance is multiplied by the player's loot bonus.
- **Boxes:** opening a Dungeon Box gives one random room instance (any shop room, weighted toward common roles) with a rolled **rarity**. A **Rare Box** (from level-ups and challengers) shifts the rarity odds upward. **Pity:** a box that would be the 10th in a row without Rare or better is guaranteed to be at least Rare.
- **Blueprints:** each blueprint belongs to one room type. 5 blueprints of a type craft that room at Common rarity. This is the guaranteed, non-random route to every room. Scrapping an unwanted room returns 2 of its blueprints (duplicate conversion).
- **Rarity variants (7 tiers, owner-approved 2026-11-05):** Common, Uncommon, Rare, Epic, Legendary, Mythic, Secret. Rarer rooms have higher stats (×1.00 / 1.10 / 1.25 / 1.40 / 1.60 / 1.85 / 2.20), a higher upgrade cap (3 / 4 / 5 / 6 / 7 / 8 / 10), and perks: extra **coins**, extra **loot chance** or extra **XP**, always different kinds. Uncommon and Rare get one perk, Epic and Legendary two, Mythic and Secret three (one of each kind). Secret is about 1 in 5,000 Dungeon Boxes and has a shimmering prismatic edge. Perk bonuses from all placed rooms add up, with a cap. Rarity signals discovery: a well-arranged Common layout must stay viable.
- **Room upgrades:** every placeable room can be upgraded with coins up to its rarity's cap. Defenders and traps hit harder and last longer. The Monster Den's boost grows. The Treasure Room raises its vault-bonus cap.
- **XP and keeper level:** every defeated adventurer gives XP. Levels unlock the rarer shop rooms and give a box at each level-up (a Rare Box every 5 levels).
- **Permanent upgrades:** account-wide keeper upgrades bought with banked coins, at rising costs: Golden Touch (more coins), Lucky Charm (more loot), Scholar (more XP), Stout Defenders (defender health), Lure (shorter visitor interval) and Deep Vault (higher vault-bonus cap). They never reset.

Starting numbers live in `Balance.luau` and are listed in [PHASE0.md](PHASE0.md); they are hypotheses to tune in playtests. The non-random routes (shop purchases, blueprint crafting) keep every functional room reachable without luck.

## Interface and onboarding

- **HUD:** banked coins, vault gold, current risk bonus, build access and next visitor status.
- **Build mode:** room inventory, touch/mouse placement, preview, connection indicators, remove/move, and plain-language errors.
- **Encounter panel:** visitor name, health, route, expected reward and vault risk; concise interaction feedback.
- **Shop:** role, cost, ownership and confirmation for consequential purchases.
- **Collection:** entries, source and owned count. Never imply odds that are not real.
- **Tutorial:** contextual prompts for practice encounter, placement, banking and first purchase; recover if the player takes unexpected actions.
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
- **Profile:** Schema version, banked coins, vault gold, stable inventory instance IDs, placements, upgrades, unlocks and onboarding state. Define defaults, migrations and repairs for invalid IDs, duplicate instances and broken layouts.
- **Persistence:** Server-side session ownership/locking strategy, retry/backoff, periodic and lifecycle saves, shutdown handling and published-place failure testing. A failed load is not a new profile: block progression and do not overwrite an inaccessible save with defaults. Document actual guarantees and limitations.
- **Security:** Validate ownership, costs, grid bounds, connectivity, encounter state and remote argument types. Rate-limit requests; serialize transactions; make encounter resolution idempotent. Clean up NPCs and connections on exit.
- **Performance:** Cap rooms and NPCs, clean up or pool effects, avoid per-frame simulation where possible, and profile multiple plots on representative mobile hardware.

## Milestones and success questions

**Playable MVP:** Persistent plot, valid placement and rearrangement, automatic visitors, correct win/loss and vault behavior, banking, guaranteed purchases/upgrades, onboarding and reconnect persistence. Mouse and touch work. Placeholder art is acceptable.

**Full release:** MVP plus a tested content roster, modular art, animation, VFX, audio, responsive UI, accessibility, stable persistence, performance testing and an operations process. Scope follows actual capacity and playtest outcomes.

Measure tutorial completion, time to first placement/purchase, layout edits, encounters, banking behavior, challenger participation, session length, returns and errors. Establish targets from an initial test instead of inventing success claims. Ask testers if they understand why they won or lost, what they want next, and whether rearranging helped.

Open questions: Is watching encounters engaging between edits? Is vault risk understandable or stressful? How often should visitors arrive? Are rooms or upgrades more motivating? How many rooms can a server support? Does branching improve play enough to justify complexity? Do players feel forced to place a treasure room, or is safe play still worthwhile? Fix readability and the core loop before adding more content.

## Change log

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
