# Build a Dungeon — Build Phases and Update Roadmap

**Companion:** [Game Design Document](GDD.md)  
**Status:** Working plan. Phases 0–6 deliver a playable MVP. Phases 7–11 lead to full release. Later updates are proposals and should respond to testing and player feedback.

**Current phase (updated 2026-11-05):** Phases 1–5 and 7 systems are implemented in code and covered by automated specs (17 spec files, run in Studio). Phase 8 art is part-built as Studio models. Phase 9 UI, icons and sounds are implemented. No phase is marked exited: exit criteria need human playtests. Still open before release: real-device mobile testing, playtests with fresh players, balance tuning, audio and icon licensing review, published-place persistence failure testing, and the release checklist ([RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)). Known gaps are in [KNOWN_ISSUES.md](KNOWN_ISSUES.md). The Phase 0 spec is in [PHASE0.md](PHASE0.md).

## Production rules

- Build a complete vertical slice with placeholder assets before producing a large content set. Each phase has an explicit exit check.
- Balance values in the GDD are hypotheses. Keep definitions data-driven and record meaningful changes.
- Test desktop and mobile interaction from the first UI. Keep gameplay, ownership and economy authoritative on the server.
- The current Rojo project maps `src/shared`, `src/server` and `src/client`; document the asset workflow when Studio-managed assets are introduced.
- Address blocking defects and confusing interactions before expanding the scope. Estimates and final content counts depend on capacity and playtests.

# MVP phases

## Phase 0 — Prepare and specify

**Goal:** Agree on a testable first experience.

**Build:** Review the GDD and select placeholder values. Sketch the grid, the first route and the first five minutes. Connect a Studio place to the existing Rojo project; establish source control, a private published test place, naming conventions, asset ownership and issue tracking. Decide target inputs and devices. Create initial room/visitor definitions and a repeatable playtest checklist.

**Exit:** Another developer can sync and run the empty plot. MVP scope, first-session flow and exclusions are written down.

## Phase 1 — Grid and building graybox

**Goal:** Make room arrangement satisfying and reliable before adding combat.

**Build:** Create an isolated plot, a fixed entrance cell and a server-owned 5 × 4 prototype grid. Define one-cell open rooms (doorways on all sides), placement in any cell except the entrance, a server-computed route (the longest path from the entrance, ending at the treasure room when it can be reached), off-route rooms that stay placed but idle, and starter ownership. Implement build camera, inventory, touch/mouse placement, preview, move/remove and useful rejection messages. Validate bounds, ownership and occupancy on the server. Show the route overlay and dim off-route rooms. Cancel restores the last committed layout. Pause visitor spawning while editing; entering build mode cancels any active visitor without payout or theft, then allows edits. Use simple blocks with obvious doors.

**Verify:** Placements in every cell, longest-route selection (branches, loops, islands, a reachable and an unreachable treasure room), off-route rooms giving no bonuses, overlaps, removals, separate plots and malformed requests. Check a small phone screen.

**Exit:** Players can create a valid route and explain why an invalid placement is rejected.

## Phase 2 — One complete encounter

**Goal:** Prove the dungeon is fun to watch and ordering rooms matters.

**Build:** Add a server state machine: idle → spawn → traverse → resolve → cleanup. Spawn one novice visitor on the validated path and show health. Add a slime defender, slow effect and telegraphed spike trap. Prevent layout changes during the encounter. Handle victory, treasure arrival, missing targets, player exit and NPC cleanup. Use temporary feedback and animation.

**Verify:** Compare slime before spikes versus reversed order. Check independent plots, route correctness and encounter cleanup. Ask an uncoached player why the visitor won or lost.

**Exit:** A player understands the encounter and can improve its outcome by changing the layout. Fix visual clarity and pacing before adding content if this fails.

## Phase 3 — Economy and optional risk

**Goal:** Complete the earn, bank, spend and risk loop.

**Build:** Add server-owned bank and vault balances, one-time win rewards (banked directly without a treasure room, into the vault with one), banking, capped vault bonus, percentage robbery and the shorter visitor interval for the optional treasure room. Add a HUD, clear encounter result and guaranteed Guard Room purchase. Add an explicitly invited armored challenger with visible reward and theft risk. Give each encounter a unique resolution ID and serialize balance operations per player. Tune the first purchase for a short session.

**Verify:** Wins, losses, empty vault, play with and without a treasure room, removing the treasure room while the vault holds gold, banking near resolution, duplicate requests, insufficient funds and disconnects. Confirm banked coins and owned rooms cannot be stolen. Observe a 10–15 minute playtest.

**Exit:** Players make a purchase and understand the choice between safe banking and optional risk. Safe progression remains worthwhile.

**Superseded (owner-approved 2026-11-05):** the separate vault balance, Bank and the invited challenger were replaced by the treasure vault allocation (a share of Coins at risk in exchange for faster visitors and rarer variants) and threat levels. See GDD "Threat levels, variants and the treasure vault".

## Phase 4 — Persistence and security

**Goal:** Make progress dependable enough for external testing.

**Build:** Versioned profile with balances, stable inventory IDs, placements, upgrades, unlocks and tutorial state. Implement validation, defaults and migration/repair rules. Use server persistence with a session ownership strategy, retries/backoff, periodic saves and shutdown handling. A failed load must not be treated as a new profile or overwritten with defaults. Cancel interrupted encounters without win or robbery. Validate and throttle all client requests; clean up on exit. Document guarantees and known limits.

**Verify:** Rejoin with balances/layout intact; published-place save failures, retries and shutdown; duplicate sessions; old schema; invalid IDs; duplicate instances; disconnect around a purchase or encounter result. Verify no duplication or lost room in tested cases.

**Exit:** No known reproducible critical duplication or save-overwrite issue. Failed loads block progression safely and explain the problem.

## Phase 5 — Onboarding and basic presentation

**Goal:** A new player can learn the game without a developer explaining it.

**Build:** Guided practice visitor, free spike placement, first bank and guaranteed purchase. Support tutorial recovery from unexpected actions and skipping on later visits. Add short room descriptions, outcome text, placement highlights and basic sounds. Make HUD, build and shop responsive for mouse and touch. Add text/icon contrast, reduced camera motion and basic settings.

**Verify:** Watch fresh players without coaching. Record time to first placement and purchase, confusion around bank versus vault, and whether they change room order. Test small-phone UI and desktop controls.

**Exit:** Testers independently finish the basic loop and understand a loss. Fix major confusion before the MVP gate.

## Phase 6 — Stabilize and ship the playable MVP

**MVP content:** Entrance, optional treasure room, Slime Nest, Spike Hall and purchasable Guard Room; novice and optional armored challenger; one connected route; banking, vault risk, guaranteed shop, at least one upgrade, tutorial and persistence. Placeholder art is fine. No gacha, offline earnings, player raiding or separate monster inventory required.

**Build:** Fix playtest issues, add settings, reasonable room/NPC caps, event/error logging and a known-issues list. Profile several plots and limit effects. Tune a 15–30 minute session around meaningful purchases and layout changes without forcing unsafe play. Prepare a private multiplayer build.

**Acceptance:** A new player joins, builds, watches visitors, sees correct win/loss and vault math, banks, buys, upgrades, rearranges and reconnects with progress intact. Touch and mouse work. Invalid requests are rejected. No known critical save, economy or progression bugs remain. Multiplayer is stable at the tested target count.

**Decision:** If players do not enjoy watching and improving a dungeon, return to Phases 1–3. More rooms or polish alone do not solve a weak loop.

# Full release phases

## Phase 7 — Systems depth and collection

**Status (2026-11-04, client UI added 2026-11-05):** Rules and data done and spec-tested: Monster Den, Mushroom Cavern, Restless Crypt, Scout and Cleric with traits, visitor rotation, `Discovered` index (schema v2). The collection panel is in code (`Ui/PanelsCollection`). Not started: separately collectible monsters. Pending: economy simulation with real sessions.

**Goal:** Add strategic variety without obscuring the basic loop.

**Build:** Add Monster Den, Mushroom Cavern and Restless Crypt with identifiable interactions and counters. Add two visitor traits, capped upgrades and a collection index. Prototype separately collectible monsters with compatibility slots; retain built-in defenders if two inventories feel confusing. If adding free gameplay-earned mystery chests, specify and display probabilities, duplicate conversion or pity, and guaranteed routes to useful rooms. Test economy growth, rarity value, interactions and migrations.

**Loot and progression status (2026-11-04):** server rules, schema v3, remotes and specs done (`Rules/Loot`, `Rules/Progression`, server `Rules/Rewards`, `LootService`; 17 spec files pass in Studio). Client UI is in code (`Controllers/LootController`, `Ui/PanelsLoot`: box opening with shown odds, blueprints and crafting, scrapping, keeper level and XP, permanent upgrades; rarity badges in `Ui/Kit`). Pending: a Play-mode test of the new remotes, and economy tuning with real sessions.

**Owner addition (2026-11-04):** loot drops (Dungeon and Rare Boxes with shown odds and pity, blueprints with crafting and scrapping), Common to Mythic room variants with coin, loot and XP perks, upgrades for every room up to a rarity cap, keeper XP and levels, and permanent coin upgrades (GDD "Loot, rarity and progression").

**Owner addition (2026-11-05):** threat levels T1–T6 (keeper levels 1/4/8/13/19/26, chosen by the player) replace the challenger invite and the fixed visitor rotation; rare Elite/Shiny/Gilded variants; coin ranges per visitor; the treasure vault allocation (`VaultPercent`, schema v4) replaces Bank; server events with room modifiers and admin chat commands; full drop tables and "next goal" data in State. **Status:** server rules, schema v4, remotes and specs done (see [KNOWN_ISSUES.md](KNOWN_ISSUES.md) for the spec run). Pending: client UI for the new State/Catalog fields and remotes, a Play-mode test of SetThreat, SetVaultPercent, events and admin commands, and economy tuning.

**Owner addition (2026-11-05, item model):** each room type has one fixed rarity (instances are `{Id, Level, Modifier?}`, schema v5); boxes roll a tier then a room; tier-based craft/scrap costs; shop sells Common/Uncommon only; treasure line of seven tiers; eleven new rooms with Burn, Chill, units, ambush, summon, revive and void mechanics. **Status:** server rules, schema v5 and specs done. Pending: client UI and FX for the new fields and events, room and creature art, a Play-mode test and tuning (see KNOWN_ISSUES).

**Exit:** Players can deliberately build at least two effective combinations, and a rare room is not required for a viable dungeon. Box odds are shown before opening, and every room is reachable without luck.

## Phase 8 — Models, environment and animation

**Goal:** Replace placeholders with a coherent toy-dungeon identity.

**Status (2026-11-05):** Part-built. Room, support-room, character and prop models exist as Studio-built primitive models under `ReplicatedStorage.Art` and `Workspace.Map`, exported to `Assets\BuildADungeon\models\` (see that folder's README). Not yet done: the full exit check (readability at default zoom, mobile profiling).

**Build:** Produce art reference, palette, scale and doorway guide, then a reusable floor/wall/door kit. Model entrance, vault, slime nest, spikes, guard room, den, mushroom cavern, crypt and props. Model novice and armored visitors, slime, guard and skeleton defenders. Animate idle, walk, attack, hit and defeat/recovery as applicable, plus trap anticipation/activation and vault opening. Keep collision and paths consistent with graybox logic. Document source assets, attribution, export and versioning.

**Exit:** Critical states are readable at default zoom, art does not break placement or navigation, and memory/rendering are profiled on representative mobile hardware.

## Phase 9 — VFX, audio, UI and accessibility

**Goal:** Make actions satisfying and outcomes clear.

**Status (2026-11-05):** UI, icons and sounds are implemented in code: `src/client/Ui/*`, `src/client/Ui/IconIds.luau` and `SoundIds.luau`, with reduced-motion and sound settings. Four sound slots are unfilled (see [KNOWN_ISSUES.md](KNOWN_ISSUES.md)). Not yet verified: the exit check, on real devices.

**Build:** Add placement confirmation, damage/slow indicators, trap warnings, monster recovery, theft and banking feedback. Create restrained discovery VFX; pool and cap particles. Add ambience and distinct sounds with music/effects controls. Polish HUD, build inventory, room details, collection, shop, onboarding and results in one visual system. Support safe-area layouts, readable text, icons plus color, reduced motion/effects and sound settings. UI animation must not delay actions.

**Exit:** Players can understand results with audio off. Critical controls are usable on small phones and effects stay readable during busy encounters.

## Phase 10 — Release content, balance and social viewing

**Goal:** Provide a complete initial experience and clear longer-term goals.

**Build:** Finalize a modest roster informed by Phase 7. Every room needs a role, source, icon and upgrade curve. Add a few cosmetic themes, collection milestones and read-only plot visits if the server layout permits. Tune new and experienced progression using observed sessions and telemetry; explain visitor traits and help players recover from weak layouts. If monetization is considered, conduct a separate ethical design and current-platform-policy review; paid randomized rewards are not a release dependency.

**Exit:** Multiple viable builds exist, players can identify a next goal, and visits cannot modify another player's inventory or economy. Set exact release content quantities against actual capacity.

## Phase 11 — Hardening and full release

**Goal:** Ship a stable game and be able to operate it.

**Build:** Run closed then broader tests. Validate save migration, remote security, purchase/placement bounds, reconnect and failure behavior. Profile target server load and mobile devices. Review accessibility, licenses and current Roblox policies. Prepare accurate store copy and thumbnails from actual play. Set up telemetry, issue triage, rollback/versioning, save recovery procedures and update checklists. Stage the release and monitor save failures, progression blockers and economy anomalies.

**Release gate:** No known critical progression, data-loss or duplication defects; acceptable device performance at measured target load; complete onboarding and settings; documented incident owner and rollback path. Delay or reduce scope if a gate fails.

# Future update proposals

Each update needs a prototype, balance and migration plan, security review, device/performance pass, release notes and rollback plan. Reorder based on real feedback.

## Update A — The Living Crypt

Add a skeleton theme, cursed library and lantern hall, plus two visitor traits and themed cosmetics. Rare room idea: **Bone Orchard**, where defeated skeletons leave temporary bone piles that improve an adjacent crypt room, with a strict cap. Provide a non-random route to gameplay-relevant content. Test synergy caps and interaction with existing rooms.

## Update B — Caverns and Curious Creatures

Add glowing cavern rooms, mushroom variants and a burrowing visitor. Rare room idea: **Crystal Grotto**, which stores limited charge from adjacent traps and releases a visible burst on a cooldown. Add themed collection goals and decorations. Test effect readability, performance and continued usefulness of common rooms.

## Update C — Raiding other dungeons

Prototype what the visitor actually does before committing: personally navigate a copy, interact indirectly, or another short activity. Owners opt in to publish a versioned, validated snapshot and can unpublish it. A visitor interacts with an isolated copy; the owner never loses persistent gold or items. Display difficulty, expected duration and rewards. Pay capped rewards from the game, with cooldowns and self-farming safeguards. Add privacy, reporting and server validation; filter user-generated text as required by Roblox. Handle disconnects, stale snapshots and incompatible versions. Stress-test abuse and economy exploits before release.

## Update D — Deeper building

Prototype branching paths or a second floor after single-path routing is stable. Define route selection, unreachable rooms, validation, room caps and reward rules that prevent empty-loop farming. Add a layout save slot and risk-free test mode. Preserve existing routes through migration; keep starter building readable.

## Update E — Seasonal expeditions

Add limited-time visitor modifiers, a themed room set and cosmetic objectives. Give gameplay-affecting items a clear return or alternate acquisition path; avoid mandatory daily streaks. Test event start/end, time zones, stale clients, rewards and rollback. Make event currency and expiry explicit.

## Ongoing operations

Monitor onboarding, first purchases, layout edits, safe/risky choices, session and return behavior, crashes and save errors. Combine telemetry with observation; do not optimize for one metric alone. Review confusion, unfair risk and repetitive encounters before increasing grind. Keep migrations, security checks, staged rollout and rollback part of every update.


## Lobby shop and rare-drop implementation notes

- **MVP, Phases 1–6:** Graybox a six-plot lobby and shared plaza when practical; test player capacity and plot isolation. Provide a discoverable Room Shop with guaranteed basic purchases and a simple Room Upgrader. Validate all costs and ownership on the server. The first MVP may use a basic interaction or UI rather than finished shop models. Do not require randomized boxes or drops.
- **Phase 7:** Prototype gameplay-earned room boxes, displayed contents and odds, duplicates/guaranteed progression, and rare drops from NPC visitors. Persist each award transaction safely, avoid duplicate grants and simulate the economy. Define actual probabilities only after tuning and display those exact values in-game. Review applicable platform requirements before any paid randomized offering.
- **Phases 8–10:** Model and animate the shared plaza shop and upgrader; add signage, interaction prompts, icons, box-opening presentation, drop feedback, audio and responsive shop/upgrade UI. Test six active plots, NPC limits, visibility and performance on desktop and mobile.
- **Post-launch raid update:** Explore game-funded, capped raid rewards only after the opt-in snapshot and anti-farming systems are validated. Never take items or persistent currency from another player.
