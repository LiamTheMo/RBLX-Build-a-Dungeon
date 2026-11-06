# Release checklist

Pre-release gates for the first full release. They come from the Phase 11 release gate in [BUILD_PHASES.md](BUILD_PHASES.md) and the rules in [AGENTS.md](../AGENTS.md). Tick a box only when the check was run on the release build and the result was recorded. Record results in the release issue. Playtest steps follow [PLAYTEST_CHECKLIST.md](PLAYTEST_CHECKLIST.md).

Release build: ______ (git commit) · Published place version: ______ · Incident owner: ______

## Build and specs

- [ ] `main` is synced with Rojo at the release commit, with no Studio edits to synced scripts.
- [ ] All 17 spec files pass in Studio (`tests/luau/studio_runner.luau`) on the release commit.
- [ ] Studio Output shows no errors on server start, on player join, or during a full encounter and a purchase.
- [ ] Lint (`selene.toml`) passes on `src/` and `tests/`.

## Persistence on the published place

Run these on the published place in a private test server, not in Studio.

- [ ] A failed load shows `LoadState = "Failed"`, refuses every request with `ProfileNotLoaded`, and leaves the stored save unchanged (checked in the DataStore).
- [ ] Failed saves are retried with backoff, and the player's state is not lost or reset after a later successful save.
- [ ] Autosave (every 60 s) and save-on-leave both persist balances, layout, rooms, boxes, blueprints and permanent upgrades.
- [ ] Shutdown (`BindToClose`) saves every profile with players in the server. Test by stopping a server that holds players.
- [ ] Rejoining restores balances, layout and rooms.
- [ ] A failed or interrupted save never writes a default profile over a real one.

## Sessions and concurrency

- [ ] The same user joining two servers at once does not corrupt the profile (session lease holds; one session writes).
- [ ] Disconnect during a purchase, a box opening, a craft or a scrap: no duplicate room, no lost currency.
- [ ] Disconnect mid-encounter: no reward, no theft, NPC cleaned up.
- [ ] Replayed `Bank`, `Buy`, `Upgrade`, `OpenBox`, `CraftBlueprint` and `ScrapRoom` requests do not duplicate anything.
- [ ] Two players on one server cannot affect each other's plot, balances or visitors.

## Schema migration (real saves)

Use copies of real saves. Never migrate or test on the only copy.

- [ ] A real v1 save migrates to v3 without losing rooms, coins or the vault. `Discovered` is filled as described in [ARCHITECTURE.md](ARCHITECTURE.md).
- [ ] A real v2 save migrates to v3. `Xp` is seeded from `Stats.Wins * 10`, with no retroactive boxes.
- [ ] A real v3 save loads unchanged.
- [ ] A save with a newer schema version is rejected and left untouched.
- [ ] Invalid saved data (unknown room ids, broken layout, negative money) is repaired as ARCHITECTURE.md describes.

## Remote security

Check every remote in `src/shared/Net/Remotes.luau`, from a test client that sends altered values.

- [ ] Wrong types, `nan`, huge numbers and unknown ids are rejected with a reason.
- [ ] Another player's instance ids are rejected.
- [ ] `CommitLayout` rejects more than 19 entries and any layout that fails `Route.Build`.
- [ ] Insufficient coins, blueprints or boxes are refused.
- [ ] Requests above about 8 per second per player and remote are rate-limited.
- [ ] Requests during an encounter are refused where the design says so (building, bank, upgrade, challenger invite).

## Performance and devices

- [ ] Six plots (`Balance.Server.MaxPlots`) each with an active visitor: server frame time and memory measured and recorded.
- [ ] Client frame rate and memory measured on a low-end phone with six plots visible.
- [ ] Effects (particles, sparkles, spores, FX) stay capped, and the caps hold during busy encounters.
- [ ] The place's Max players setting in the game settings is **6**, to match `Balance.Server.MaxPlots`.

## Mobile UI and accessibility

- [ ] Phone landscape (Studio emulator about 667 × 375 and one real phone): touch targets are at least 44 px, safe areas are respected, and HUD and encounter panel do not overlap.
- [ ] Tablet checked.
- [ ] Desktop mouse and keyboard checked for build mode, shop and settings.
- [ ] Reduced motion removes pops, slides and looping effects. Music and SFX sliders work and persist.
- [ ] Every status has text or an icon, not colour alone.
- [ ] Text contrast checked against [UI_SPEC.md](UI_SPEC.md) tokens.
- [ ] Audio off: a new tester can say why a visitor won or lost.

## Assets and rights

Sources are listed in the table in [DEVELOPMENT.md](DEVELOPMENT.md) and in `Assets\BuildADungeon\README.md`.

- [ ] Owner confirms rights and usage terms for the AI design assistant-generated icons (`IconIds.luau`), or the icons are replaced.
- [ ] Owner confirms rights and usage terms for the AI design assistant-generated mockups and reference images. They are not used in the game or store page unless confirmed.
- [ ] Every Creator Store sound in `SoundIds.luau` is listened to, its licence is checked, and weak fits (such as Rise) are replaced.
- [ ] Theft, SlimeAttack, Ambience and Music are filled or the features are dropped.
- [ ] Studio-built art is saved in the place file, and weld and Motor6D offsets are re-checked after import.
- [ ] Code reused from RBLX-Flintborn (Loader, Signal, prelude, persistence patterns) carries any required notice.

## Monetization and policy

- [ ] No boxes, blueprints or rooms can be bought with Robux. Boxes and blueprints are gameplay-earned only.
- [ ] Current Roblox policies are reviewed for the store page, user-facing text and data handling.

## Privacy and publishing

- [ ] The place is private until the release decision. Its privacy setting is checked in the Creator Dashboard.
- [ ] Data stored per player is listed: profile fields in [ARCHITECTURE.md](ARCHITECTURE.md). Nothing else is stored.
- [ ] No user-generated text is shown to other players, or it is filtered as Roblox requires.

## Store page

- [ ] Description and screenshots show features that exist in the release build.
- [ ] Thumbnails and screenshots are taken from actual play, not from mockups.
- [ ] Odds for boxes are described only as shown in the game.

## Operations

- [ ] Rollback: the previous published place version number is recorded (from the place's version history) before publishing, so it can be restored.
- [ ] An incident owner is named, with a contact and an escalation path written in the release issue.
- [ ] Save-failure, progression-blocker and economy-anomaly monitoring is set up, and someone is assigned to watch it after release.
- [ ] [KNOWN_ISSUES.md](KNOWN_ISSUES.md) is reviewed and updated for the release.
- [ ] The playtest checklist was run with fresh players, and the results are recorded.
- [ ] Balance values changed after playtests are recorded in `Balance.luau` and the change log.
