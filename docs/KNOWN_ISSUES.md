# Known issues

Current gaps, checked against the code and docs on 2026-11-05. Remove an entry when it is fixed and verified. Track bugs as GitHub Issues ([DEVELOPMENT.md](DEVELOPMENT.md)).

## Art, icons and sound

- **Icons awaiting moderation.** The 11 icons in `src/client/Ui/IconIds.luau` are now uploaded to group 33284082 with `Assets\BuildADungeon\tools\roblox_upload.py`. On 2026-11-05, Coin, Upgrade, Shield, Sword and Vault still failed to load, probably because moderation hadn't finished yet. Re-check them in Studio, and confirm they are approved in Creator Hub.
- **Unknown asset warning.** `rbxassetid://203785492` logs "Asset type does not match requested type" at start. Nothing in `src/` or the place references it; it is probably Studio or plugin noise.

- **Sprite fallback untested live.** `src/client/Ui/Sprites.luau` preloads the 70 UI sprites and falls back to code-drawn UI for any that fail. In Studio Play, `PreloadAsync` reports Failure even for sprites that render, so the fallback switch only acts on real servers. Check on the published place that the sprites show and the fallback doesn't trigger by mistake.
- **Desktop layout unseen.** The last checks ran in a 1175×599 window, which uses the phone layout. Check the desktop layout and real phones.
- **Image and model rights unconfirmed.** The icons, sprites and concept references come from ChatGPT through the owner's account. The models were made in Blender from those references. Confirm rights before release (see the Assets README).
- **Minor UI rough edges.** Shop cards have a small notch at the top-right corner, and the build-card count pill sits tight against the frame.
- **Four sound slots are empty.** Theft, SlimeAttack, Ambience and Music have no entry in `src/client/Ui/SoundIds.luau`.
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
