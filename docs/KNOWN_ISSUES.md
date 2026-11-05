# Known issues

Current gaps, checked against the code and docs on 2026-11-05. Remove an entry when it is fixed and verified. Track bugs as GitHub Issues ([DEVELOPMENT.md](DEVELOPMENT.md)).

## Art, icons and sound

- **Icons blocked: wrong owner.** The experience belongs to group 33284082, but the 11 icons in `src/shared/UI/IconIds.luau` were uploaded through Studio to the owner's personal account (user 855002824). In game they fail with "not authorized" and fall back to text. Fix: re-upload them to the group (Open Cloud key with group asset write access; the files are in `Assets\BuildADungeon\ui\icons\`), or grant the experience use of each asset in Creator Hub, then update `IconIds.luau`.
- **Unknown asset warning.** `rbxassetid://203785492` logs "Asset type does not match requested type" at start. Nothing in `src/` or the place references it; it is probably Studio or plugin noise.

- **Icons reused for buttons.** The Loot, Collection and Keeper buttons use the Vault, Shield and Upgrade icons (`src/client/Controllers/HudController.luau`). The Support room kind also uses the Upgrade icon. There are no dedicated icons for these yet.
- **Icon rights unconfirmed.** The icons are cut from a ChatGPT-generated sheet. Do not release them until the owner confirms rights (`src/shared/UI/IconIds.luau`).
- **Four sound slots are empty.** Theft, SlimeAttack, Ambience and Music have no entry in `src/shared/UI/SoundIds.luau`.
- **Sounds not listened to.** Every sound was picked from Creator Store search metadata. Rise is a weak fit (per the Assets README).
- **Studio art only in the place file.** `ReplicatedStorage.Art` and `Workspace.Map` are not synced by Rojo. Weld and Motor6D offsets in the exported models are approximate and need a check after import (per the Assets README).

## UI and devices

- **Mobile layout not verified on devices.** `docs/UI_SPEC.md` says the layouts have not been validated in Studio on desktop or phone. Real-device testing is still open.
- **Phase 9 accessibility checks pending.** Audio-off comprehension, contrast and reduced-motion behaviour are not yet verified in play.

## Economy

- **Numbers are untuned.** Every value in `Balance.luau`, and the rates in `docs/PHASE0.md` and `docs/GDD.md`, is a hypothesis awaiting playtests.
- **Box overflow converts to coins.** When a box stack is full (999 of one type), a new box is converted to banked coins: 100 for a Dungeon Box and 300 for a Rare Box (`Balance.Loot.BoxOverflowCoins`). A notice is shown.
- **Scrapping refunds blueprints only.** Scrapping an unplaced room returns 2 blueprints of its type (`Balance.Loot.ScrapReturn`, `Rewards.Scrap`). It refunds no coins and no upgrade spending.
- **Economy not simulated with real sessions.** Phase 7 leaves economy tuning with real sessions open.

## Persistence and testing

- **Published-place failure tests not run.** Save failures, retries, shutdown and duplicate sessions still need testing on the published place ([RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)).
- **Studio saves are separate.** Studio playtests use `PlayerProfiles_v1_Studio`. If Studio cannot reach DataStores, progress is kept in memory only and is lost when the session ends.
- **Phase 7 Play-mode test pending.** The new loot and progression remotes need a Play-mode test.
- **Fresh-clone check pending.** The Phase 0 exit check (another developer syncs and runs the empty plot) has not been done ([PHASE0.md](PHASE0.md)).
- **Test place privacy not confirmed.** The owner must confirm the test place (`78621805707922`) is private in the Creator Dashboard.

## Tooling


## Not started

- **Separately collectible monsters** (Phase 7 prototype). Built-in defenders are the only option.
