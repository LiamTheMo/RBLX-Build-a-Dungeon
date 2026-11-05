# Phase 0 — Specification of the first playable experience

**Companions:** [GDD](GDD.md) · [Build phases](BUILD_PHASES.md) · [Development guide](DEVELOPMENT.md) · [Playtest checklist](PLAYTEST_CHECKLIST.md)

This document pins down what the GDD leaves open, so Phases 1–6 can be built and tested against something concrete. If this document and the GDD disagree, the GDD wins and this document must be corrected. Items marked **Assumption** were chosen here to keep work moving; the owner should confirm or change them.

## Owner-approved direction (2026-11-04)

- **The treasure room is optional.** It is a risk-for-reward choice, not a requirement. A player owns one from the start and may place it or not.
- **Rooms are small open squares** about the height of a player's avatar, with a doorway on every side. The dungeon is a miniature diorama with small adventurers walking through it.

These are recorded in the GDD change log. They also resolve a conflict in the earlier draft: with both the entrance and the treasure room fixed and one room apart, the tutorial had no space to add the spike hall.

## Grid and route

Values live in `src/shared/Definitions/Grid.luau`.

- 5 columns × 4 rows. Each cell is 6 × 6 studs and walls are 5 studs high, so a room is roughly avatar height. A plot's dungeon is about 30 × 24 studs.
- Cells are addressed (column, row). Row 1 is the front edge, where visitors arrive.
- The **entrance is fixed at (3, 1)**, front and centre, so routes can grow left, right or straight back.
- Every room has doorways on all four sides, so orthogonally adjacent rooms always connect. Diagonal cells do not touch.
- **A valid layout is one chain.** Starting from the entrance, each room touches exactly the room before it and the room after it; the last room touches only the one before it. Any extra contact is a branch or a loop and is rejected. Every placed room must be on the chain, so a disconnected room is rejected.
- The route ends at its last room. If a treasure room is placed, it must be that last room. At most one treasure room per plot.
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

### Sketch: valid and invalid layouts

```
Valid snake                Invalid: loop              Invalid: branch
row 4  .  .  T  .  .       row 4  .  .  .  .  .       row 4  .  .  .  .  .
row 3  S  K  G  .  .       row 3  .  .  .  .  .       row 3  .  .  .  .  .
row 2  K  .  .  .  .       row 2  .  .  S  K  .       row 2  .  K  S  G  .
row 1  S  G  E  .  .       row 1  .  .  E  G  .       row 1  .  .  E  .  .
```

- **Valid snake:** E(3,1) → G(2,1) → S(1,1) → K(1,2) → S(1,3) → K(2,3) → G(3,3) → T(3,4). Each room touches only its route neighbours. The empty cells at (2,2) and (3,2) keep the two runs apart, and the treasure room is last.
- **Loop:** G(4,1) touches both K(4,2) and the entrance.
- **Branch:** S(3,2) touches the entrance, K and G, so the route would split.

Because touching rooms always connect, snakes must leave a gap between parallel runs. The 5 × 4 grid fits a route of roughly 10–12 rooms. Phase 1 should check whether this feels cramped and whether the grid should grow.

## Encounter rules used for the placeholders

These are the rules the placeholder numbers assume. Phase 2 implements and tunes them.

- One visitor per plot at a time, walking the route from the entrance.
- In a **defender** room (Slime Nest, Guard Room), the visitor stops and fights the defender until one of them is knocked out. A knocked-out defender recovers after the encounter; defenders never die permanently.
- A **trap** (Spike Hall) does not stop the visitor. It flashes a warning, then strikes whoever is standing on it, on a fixed cycle.
- A slime hit slows the visitor's walk for a few seconds, so the next trap gets more hits in.
- The encounter ends when the visitor is defeated, or reaches the end of the route:
  - **Defeated:** the advertised reward is paid once. Without a treasure room it goes straight to banked coins; with one it goes to the vault, plus the vault bonus.
  - **Reaches the end, no treasure room:** the visitor leaves. No reward, no loss.
  - **Reaches the treasure room:** it steals its theft fraction of the current unbanked vault, rounded down. Banked coins and rooms are never affected. An empty vault loses nothing.
- **Assumption:** removing the treasure room while the vault holds gold banks that gold automatically. Banking is already allowed at any time, so this gives no extra advantage and nothing is ever lost on removal.
- **Assumption:** rewards and theft round down to whole coins; the vault bonus is `min(cap, floor(vault / 100) × 1%)`.

## Placeholder values

Values live in `src/shared/Definitions/Balance.luau`. All are hypotheses for playtesting.

| Visitor | Health | Attack | Walk speed | Reward | Theft |
| --- | ---: | ---: | ---: | ---: | ---: |
| Practice Adventurer (tutorial only) | 20 | 5 every 1.0 s | 4 studs/s | 10 | 0% |
| Novice (automatic) | 60 | 10 every 1.0 s | 4 studs/s | 20 | 10% |
| Armored Challenger (invited) | 160 | 14 every 1.0 s | 3.5 studs/s | 50 | 25% |

| Room | Values | Cost |
| --- | --- | ---: |
| Slime Nest | Defender 40 health, 6 damage every 1.0 s, each hit slows 50% for 3 s | Starter |
| Spike Hall | 15 damage per strike, 1.2 s cycle with a 0.4 s warning | Tutorial grant |
| Guard Room | Defender 80 health, 12 damage every 1.2 s | 100 coins |
| Treasure Room | Vault bonus +1% per 100 unbanked gold, capped at +20% | Starter (optional) |

| Economy and timing | Value |
| --- | ---: |
| Starting coins | 0 |
| Visitor interval, no treasure room | 30 s after the previous encounter |
| Visitor interval, treasure room placed | 20 s after the previous encounter |
| First upgrade | 60 coins (its effect is decided in Phase 3) |

Why these numbers (rough arithmetic, to be confirmed in Phase 2):

- **Practice vs slime:** the slime deals about 24 damage over four attacks and wins easily. The first encounter is a guaranteed, readable win.
- **Novice vs slime, then spikes:** the slime takes about 4 s to knock out and deals about 24 damage (36 health left). The slowed novice then needs about 3 s to cross the 6-stud spike hall, taking two or three strikes (30–45). It is usually defeated.
- **Novice vs spikes, then slime:** at full speed the novice crosses in about 1.5 s and takes one or two strikes (15–30), then about 24 from the slime. It usually escapes. This is the "order matters" lesson.
- **Guard Room at 100 coins:** with 10 + 20 from the tutorial, about four more novice wins. At roughly 45 s per visit, that is about 4–5 minutes without a treasure room, and less with one.

## First five minutes

| Time | What happens | Teaches |
| --- | --- | --- |
| 0:00 | Player joins and is assigned a plot. Overview camera shows the entrance and the slime nest. | This is your dungeon |
| ≤0:15 | Practice adventurer arrives; the slime knocks it out; +10 coins banked. | Encounters are automatic; defenders earn coins |
| ~0:30 | Tutorial grants a Spike Hall and highlights (3, 3) behind the slime. Player places it. | Building and the route |
| ~0:45 | A novice arrives, gets slowed by the slime and crosses the spikes slowly; +20 coins if defeated. Outcome text explains why. | Room order matters |
| ~1:15 | Tutorial offers the treasure room: faster visitors and a vault bonus, but theft. The player may place it at (3, 4) or skip. If placed, the next reward goes to the vault and the tutorial teaches **Bank**. | Optional risk |
| 1:30–4:30 | Automatic novices. Coins build toward the Guard Room. | The earn loop |
| ~4:30 | Tutorial points to the shop: buy the Guard Room and place it, which may mean moving rooms to keep one chain. | Shopping and rearranging |
| ~5:00 | The Armored Challenger invite unlocks, showing its reward and theft risk up front. | Optional stronger visitors |

The tutorial must recover from unexpected actions: removing the slime, skipping the treasure room, placing the spikes elsewhere. It must also be skippable on later visits.

## MVP scope

**In:** one plot per player; the 5 × 4 grid; Entrance, Slime Nest, Spike Hall, Guard Room and the optional Treasure Room; the Practice, Novice and Armored Challenger visitors; a single chain route; draft editing with commit/cancel; banking, vault bonus and theft; a guaranteed shop; at least one upgrade; tutorial; persistence; mouse and touch. Graybox art is fine.

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
| Initial room and visitor definitions | Done, in `src/shared/Definitions/` and checked by `tests/luau/definitions.spec.luau` |
| Rojo project repaired (missing `Loader` module) | Done |
| Naming conventions, asset ownership, source control, issue tracking | Done, in [DEVELOPMENT.md](DEVELOPMENT.md) |
| Repeatable playtest checklist | Done, in [PLAYTEST_CHECKLIST.md](PLAYTEST_CHECKLIST.md) |
| Private published test place | Place `78621805707922` ("Build a Dungeon!") exists. **Owner to confirm it is private** in the Creator Dashboard |
| Studio place synced with Rojo and run without errors | Done 2026-11-04: synced into place `78621805707922`, played in Studio, and both server and client required the definitions with no script errors. The only console output was an asset-type warning for `rbxassetid://203785492`, which no instance in the place references (Studio or plugin noise) |
| Definitions spec | 6/6 pass, run in Studio. It was also checked to fail on deliberately broken values |
| Exit check: another developer can sync and run the empty plot | Pending: needs a second person or a fresh clone |
