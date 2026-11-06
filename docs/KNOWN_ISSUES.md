# Known issues

Current gaps, checked against the code and docs on 2026-11-05. Remove an entry when it is fixed and verified. Track bugs as GitHub Issues ([DEVELOPMENT.md](DEVELOPMENT.md)).

## Art, icons and sound

- **Icons awaiting moderation.** The 11 icons in `src/client/Ui/IconIds.luau` are now uploaded to group 33284082 with `Assets\BuildADungeon\tools\roblox_upload.py`. On 2026-11-05, Coin, Upgrade, Shield, Sword and Vault still failed to load, probably because moderation hadn't finished yet. Re-check them in Studio, and confirm they are approved in Creator Hub.
- **Unknown asset warning.** `rbxassetid://203785492` logs "Asset type does not match requested type" at start. Nothing in `src/` or the place references it; it is probably Studio or plugin noise.

- **Sprite fallback untested live.** `src/client/Ui/Sprites.luau` preloads the 70 UI sprites and falls back to code-drawn UI for any that fail. In Studio Play, `PreloadAsync` reports Failure even for sprites that render, so the fallback switch only acts on real servers. Check on the published place that the sprites show and the fallback doesn't trigger by mistake.
- **Desktop layout unseen.** The last checks ran in a 1175×599 window, which uses the phone layout. Check the desktop layout and real phones.
- **Image and model rights unconfirmed.** The icons, sprites and concept references come from AI design assistant through the owner's account. The models were made in Blender from those references. Confirm rights before release (see the Assets README).
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
- **Scrapping refunds blueprints only.** Scrapping an unplaced room returns its tier's scrap return in blueprints of its type (2 Common up to 10 Secret; `Balance.Rarities`, `Rewards.Scrap`). It refunds no coins and no upgrade spending.
- **Economy not simulated with real sessions.** Phase 7 leaves economy tuning with real sessions open.
- **Threat, vault and event numbers untuned (2026-11-05).** Threat scaling, rosters, variant chances, the vault exchange rate and event effects are starting values. The vault bonus now scales logarithmically with actual vaulted coins; check progression at low and high balances and confirm that top treasures are not mandatory.
- **Secret tier has no duelling room.** Void Gate (Secret) scores 83 in the tier duel because its value is sending the visitor back through the route; the duel spec skips Secret. Bat Roost was raised to 60 HP / 6 damage so Uncommon out-duels Common.
- **Schema v5 clamps levels without refunds.** Rooms saved with a rarity above their new fixed tier lose levels above the tier cap (e.g. an Epic Slime Nest at level 6 becomes level 3), and the upgrade coins are not refunded. Saved instance rarities and rolled perks are gone. Monster Den and Restless Crypt are no longer sold (owned ones are kept).
- **Uncommon box rolls at keeper level 1–2.** Every Uncommon room is level-gated (3–6), so the gate falls back to the lowest-gated room: an Uncommon box or blueprint at level 1–2 is always a Mushroom Cavern.
- **Spending during an encounter lowers a theft.** Theft takes TheftFraction of the vaulted coins when the visitor reaches the treasure, so coins spent on rooms or upgrades during the encounter are no longer at risk. The vault share itself is locked during encounters.
- **Event effects apply at resolution.** Coins, drops and variant chances use the event running when the encounter ends (variants: when it spawns). An event that ends mid-encounter no longer counts.

## Persistence and testing

- **Published-place failure tests not run.** Save failures, retries, shutdown and duplicate sessions still need testing on the published place ([RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)).
- **Studio saves are separate.** Studio playtests use `PlayerProfiles_v1_Studio`. If Studio cannot reach DataStores, progress is kept in memory only and is lost when the session ends.
- **2026-11-05 roster play-tested in Studio (client FX).** Creatures, trap art and every new `EncounterFx` kind are wired in `PlotViewController` and were watched in a solo Play session (dragon breath, goblins, mimic ambush puff, lich, phoenix, frost, void snap measured at one frame, arrows, flame vent, chest lid). Not seen live: the lich's skeleton rising (event flow and logic checked only), phoenix revive on a real knock-out, burn tick numbers on screen; the tutorial bubble tail at SliceScale 0.4, route dots/ghost overlay, level-up banner and load-fail panel were not re-checked this pass. Wing flap direction, lid/jaw hinge angles and the chest-lid hinge are inferred from the art and may need a tweak.
- **Phase 7 Play-mode test pending.** The new loot and progression remotes need a Play-mode test.
- **2026-11-05 server changes not play-tested.** `SetThreat`, `SetVaultPercent`, the visitor roster and variants, the next-visitor retiming, server events (schedule, Workspace attributes, `ServerEvent`) and the admin chat commands passed specs and a compile check only; Studio was in use for UI testing, so no Play session was run for them. Admin commands rely on the server-side `TextChatCommand.Triggered` (Roblox's own custom-command example connects it from a server Script); confirm in Play that `/event list` answers an admin and stays silent for others. Automatic events are off in Studio (`Balance.Events.RunInStudio`); use `/event start` there.
- **Client updated for schema v4 (2026-11-05).** Threat picker, vault slider, event banner, variants, drop cards, next-goal chip, modifier badges, free build camera and the rolling box reel are in; the old entry follows for history: **Client not yet updated for schema v4.** Until the client pass, the HUD still calls the removed `Bank` and `InviteChallenger` remotes, reads the removed `Vault`, `VaultBonus` (now a percentage), `VaultBonusCap`, `ChallengerUnlocked`/`ChallengerQueued` and `VisitorReward`/`VisitorRewardDestination`, and the tutorial's BankVault step still says "Tap Bank" (it now advances on `SetVaultPercent`).
- **Admin group rank lookup.** `GetRankInGroup` failures are not cached (retried on the next command); while it fails, only the listed UserIds are admins.
- **Fresh-clone check pending.** The Phase 0 exit check (another developer syncs and runs the empty plot) has not been done ([PHASE0.md](PHASE0.md)).
- **Test place privacy not confirmed.** The owner must confirm the test place (`78621805707922`) is private in the Creator Dashboard.

## Client UI (2026-11-05)

- **9-slice clipping.** Sliced sprite frames lose their right/bottom slices at some scales (reveal card at SliceScale 0.92, PanelSmall tiles at 0.41, Mythic frame at small sizes). Mitigations in `Kit.fit`: uniform scale capped at 0.5, a delayed SliceScale re-assignment, Small panel cap 9. New 9-slice-ready frames are expected in `SpriteIds4.Frames` (hooks in `Kit`); check every frame again then.
- **Waiting on sprites (SpriteIds4, looked up with `Sprites.Get`).** Reel pointer/window/slot/burst/spin button, panel frames, pills, tooltips, toasts, tutorial bubble and arrow, nameplate health bars, owner sign, cell highlights and route markers, off-route tag, modifier chips (drawn circle plus an icon), HUD bars.
- **Admin chat path** was not verified through typed chat in Studio; commands parse and `EventService.Begin` works.

## Tooling


## Not started

- **Separately collectible monsters** (Phase 7 prototype). Built-in defenders are the only option.

## UI and admin pass (2026-11-05)

- Admin panel access uses the existing server-side allowlist/group rank (`Config/Admins`), with server authorization on each rate-limited request. Online, loaded players can receive coins, XP, chests and session threat unlocks; the Events tab can start or stop events for this server or all servers using server-defined IDs and duration limits; coins can be set, and a full profile reset requires typing RESET and a short-lived, one-use token bound to the selected user. Reset is rejected while the target is building or in an encounter, retains persistence metadata, and takes effect in the loaded profile. It is saved by the normal persistence cycle, not guaranteed durable at the instant the button returns. Test authorization, altered values, reset replay, disconnect/save failures and multiplayer in a private Studio/published environment before live use.
- Chest cards show the current pity-adjusted rarity chances and disclose individual chances by hovering or tapping a rarity. Dungeon and Royal use separate room pools; Royal has six new rooms. Existing pity, crafting and guaranteed shop remain the progression safety net. Economy balance requires playtest evidence before changing rates or rewards.
- Room catalog cards expose server-provided base stats (not upgraded or event-adjusted); special abilities remain available in the role tooltip. Permanent upgrades use existing stat icons. Treasury access now uses any placed Treasure kind, including disconnected rooms (the vault panel communicates whether it affects the route).
- Existing v4 purple row art replaces the orange sign; existing room/upgrade and reward icons are reused. Defeated-visitor feedback uses cosmetic capped coin trails and rarity-coloured item orbs, with no client-side rewards. Damage numbers and defender bars are compact; room rarity labels and floor circles are removed. Desktop, phone, reduced-motion, item identity, mobile tooltip access, sign readability and multi-unit health bars still require in-game visual testing. Visitor and defender health bars now share a style and a model-bounds anchor; verify placement for animated/flying and multi-unit characters in Studio and on phones. Tap-to-inspect now exposes a placed room's role, base stats and treasure Vault button; verify mouse and touch selection, scrolling and mobile layouts in a fresh Play session. No rare-drop cutscene is implemented.

- **New admin art needs live verification.** The generated admin icons in `Assets/BuildADungeon/ui/sprites/admin/` were cropped, uploaded to the group and connected to the panel. Check moderation, small-size readability and fallback rendering in the published place; confirm rights before release.

- **Release validation pending:** The new Royal room icons and chest art require moderation, rights and in-game checks. Royal rooms reuse existing 3D room models and tinted defender models as placeholders. Verify visual differentiation, balance, mobile layout, badge rendering and animated Secret UI in Studio.
- **Global events:** Cross-server propagation and service failure recovery require testing in a published private environment with multiple servers. Memory store requests may fail or be delayed; the panel reports write failures and servers retry polling.
- **Schema v6:** Take a profile snapshot before deployment and test migration, concurrent servers and rollback. Older server code cannot safely load v6 profiles; a rollback needs a compatible build.

## Crystal chest and collection pass (2026-11-06)

- Crystal Chest art was generated for this game and uploaded to the game group as decal 130698869939144 (image 78896703019278); Roblox reports it approved and the image preloaded successfully. Confirm in-game appearance and rights before release.
- Desktop and iPhone 17 Pro landscape simulation showed the compact collection, three-column Keeper layout and chest cards; the Crystal image also loaded. Validate on physical mobile devices, including touch, discovery, long visitor details and chest opening. The Crystal Chest numbers are initial tuning assumptions. Profile schema v7 prevents older servers from loading newer profiles; plan rollout and server restarts.

## Chest and build interface revision (2026-11-06)

- New chest-specific rooms reuse existing game-owned models and icons; distinct visual assets and polish remain to be made. The room balance and revised tier odds require playtesting. Schema v8 requires coordinated rollout because older servers reject newer profiles.
- Confirm the compact build palette filters, room selection and move/remove popup, reduced UI scale, chest opening, touch targets and safe areas on physical devices. Reused Creator Store sounds have not been auditioned or cleared for release; verify purchase and reward-arrival sounds and volume.
