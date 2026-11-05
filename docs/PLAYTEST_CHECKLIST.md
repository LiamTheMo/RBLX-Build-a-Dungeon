# Playtest checklist

Repeat this for every playtest, so results are comparable across phases. Copy the record template into the phase's GitHub issue or notes. Write down only what was actually observed; if a step was skipped, say so.

## Before the session

- [ ] `main` synced with Rojo; the build or commit is noted.
- [ ] Studio Output is clear of errors at server start and at player join.
- [ ] The tester uses a fresh profile (or the profile state is noted).
- [ ] Devices are noted: desktop (mouse), phone (touch, smallest available screen) and, where possible, a tablet.
- [ ] The tester has not been coached. Say only: "This is a game about building a dungeon. Play however you like and think out loud."

## Observe (do not help unless they are stuck for over 60 seconds)

| Measure | Record |
| --- | --- |
| Time to first encounter (target ≤15 s) | |
| Time to first room placement | |
| Did they place the treasure room? When, and why? | |
| Time to first bank (if a treasure room was placed) | |
| Time to first purchase | |
| Did they change the room order on their own? | |
| Did they invite the challenger? | |
| Moments of confusion (what and when) | |
| Errors seen (Output, on screen) | |

## Ask afterwards

1. Why did the last adventurer win or lose?
2. What does the treasure room do? Was it worth placing?
3. What is the difference between your coins and your vault?
4. Did moving rooms around help? How did you know?
5. What do you want to do next?

## Adversarial checks (developer, from Phase 1)

Run the ones that apply to the phase, and record pass or fail.

- [ ] Placing outside the grid, on an occupied cell, or a room you do not own is rejected with a clear reason.
- [ ] Layouts that branch, loop or disconnect cannot be committed; cancel restores the last valid layout.
- [ ] A treasure room that is not last, or a second treasure room, is rejected.
- [ ] Editing during an encounter is blocked.
- [ ] Repeated or replayed requests (place, bank, buy) do not duplicate rooms or currency.
- [ ] Altered remote arguments (wrong types, huge numbers, other players' ids) are rejected.
- [ ] Leaving mid-encounter cancels it with no reward and no theft, and cleans up the NPC.
- [ ] Two players on one server cannot affect each other's plot, balances or visitors.
- [ ] Rejoining restores balances and layout (from Phase 4).
- [ ] UI works on a small phone: touch targets, safe areas, readable text.

## Record template

```
Date / build:
Tester (anonymised) / device / input:
Phase:
Measures: (table above)
Answers: 1… 2… 3… 4… 5…
Adversarial checks run: pass/fail list
Issues filed:
```
