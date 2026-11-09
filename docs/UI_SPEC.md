# UI Spec (Build a Dungeon)

Implementable client UI spec. Text only. Sources: `docs/GDD.md` (Interface and onboarding; Visual direction) and `docs/ARCHITECTURE.md` (Remotes `State` fields). The client only renders and requests; the server owns all values.

## AI design assistant design pass and device validation

The updated reference direction uses group-owned sprite sheets for the HUD, shared frames, buttons, chest and threat art. Inventory keeps Rooms and Loot Chests tabs fixed above a scrollable card grid; Upgrades has Permanent and Threat tabs. The existing shop and vault actions still display server-provided values. Desktop, phone and published-place checks remain open.

The 2026-11-05 pass consulted AI design assistant in the signed-in browser for a compact purple-and-gold design, then adapted existing game sprites and generated admin icons. The implemented admin, room inspector, loot, and combat changes need desktop and phone validation in Studio. Older screen descriptions below include superseded mechanics; the GDD and current implementation take precedence.

## Style

Playful "toy dungeon": chunky rounded panels, warm gold treasure accents, strong contrast, icon + text on every control. State is never colour-only (always icon, text or shape change as well).

## Design tokens

Colours (hex):

| Token | Hex | Use |
| --- | --- | --- |
| BgDeep | `#1E1630` | Panel background (plum-dark) |
| BgPanel | `#2E2347` | Cards, bars |
| BgRaised | `#3F3162` | Raised buttons, inputs |
| Stroke | `#120D1F` | Outer outlines |
| TextPrimary | `#FFF6E0` | Main text (contrast on BgDeep about 14:1) |
| TextMuted | `#BDB0D6` | Secondary text (about 6.5:1 on BgDeep) |
| Gold | `#FFC83D` | Coins, vault, primary accent |
| GoldDark | `#B8860B` | Gold button shadow/edge |
| TextOnGold | `#2A1A00` | Text on gold (about 10:1) |
| Accent | `#6C5CE7` | Secondary buttons, focus ring |
| Success | `#4ADE80` | Good notices, owned, valid route |
| Danger | `#FF5C5C` | Risk, errors, low health |
| Warning | `#FFA94D` | Cautions |
| Disabled | `#5A4F73` | Disabled fill (text `#A99EC2`) |

Fonts (Font.fromName / Enum.Font):
- Headings, numbers, buttons: `Font.fromName("FredokaOne")` (fallback `Enum.Font.FredokaOne`), weight Bold where available.
- Body, labels: `Font.fromName("BuilderSans", Enum.FontWeight.Medium)` (fallback `Enum.Font.BuilderSans`; older fallback `Enum.Font.GothamMedium`).
- Never below 14 px at 1080p-equivalent for body.

Sizes at 1080p reference (TextSize in px): Title 32, Heading 24, Button 22, Number/HUD 26, Body 18, Caption 14.

Scaling: one `UIScale` per ScreenGui. `scale = clamp(math.min(viewport.X / 1920, viewport.Y / 1080), 0.6, 1.5)`, but on phones (min side below 600) use `clamp(viewport.Y / 720, 0.75, 1.1)` so touch targets stay large. Recompute on `Camera:GetPropertyChangedSignal("ViewportSize")`. Design every size below in reference px before the UIScale.

Shape:
- Corner radius: panels `UDim.new(0, 16)`, buttons `UDim.new(0, 12)`, pills/bars `UDim.new(1, 0)`.
- Stroke: `UIStroke` Thickness 3, Color Stroke, `ApplyStrokeMode = Border`; text labels on busy art get a 2 px text stroke (`TextStrokeColor3 = Stroke`).
- Shadow: a sibling Frame behind, same size, `Position +UDim2(0,0,0,4)`, BackgroundColor `#000000`, BackgroundTransparency 0.65, same corner radius (no image needed). Gold/primary buttons use a 4 px bottom "edge" Frame in GoldDark instead.
- Padding: `UIPadding` 12 px in panels; 8 px gaps in lists (`UIListLayout.Padding = UDim.new(0, 8)`).

## Safe areas and Roblox core UI

- All ScreenGuis: `ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets` so nothing sits under the Roblox top bar (about 58 px tall, with the menu and chat buttons at top-left) or phone notches. Do not also add manual top offsets.
- Keep the top-left corner (menu/chat icons) clear; HUD lives top-centre/top-right and bottom.
- Chat window and backpack: build UI must not cover the bottom-centre hotbar region on desktop when Backpack is enabled; the game disables the default backpack, so bottom bar is free.
- Minimum touch target 44 x 44 px (after UIScale); primary buttons 56 px tall. 8 px minimum gap between adjacent targets.
- Use `GuiObject.AutoButtonColor = false` and implement own states.

## Button states

All buttons: a TextButton (or ImageButton-free Frame + TextButton) with UICorner 12 and UIStroke 3.

| State | Look | Tween |
| --- | --- | --- |
| Idle | Fill token, text token | none |
| Hover (mouse only) | Fill lighter 8%, `Size` x1.03 | 0.12 s Quad Out |
| Press | Fill darker 10%, `Size` x0.96, edge Frame height 4 -> 1 | 0.06 s |
| Selected | Gold 3 px stroke + check icon/text "Selected" | none |
| Disabled | Fill Disabled, text `#A99EC2`, `Active = false`, a short reason label ("Need 50 coins") | none |
| Focus (gamepad) | 3 px Accent `SelectionImageObject`-style stroke | none |

Button fills: Primary = Gold with TextOnGold; Secondary = BgRaised with TextPrimary; Danger = Danger with `#1E0A0A`; Cancel = BgRaised.

## Motion and reduced motion

- Panel open/close: 0.18 s Quad Out, slide 24 px plus fade (`GroupTransparency`). Number change: coin count tweens 0.25 s; brief 1.1x pop on gain. Toasts: 0.2 s in, 2.5 s hold, 0.3 s out.
- Reduced Motion (`State.Settings.ReducedMotion = true`): no scale pops, no slides, no pulsing arrows or looping effects; fades of 0.08 s or instant; tutorial arrow is static. Camera shake and screen flashes are off. Read the flag from the latest `State` snapshot and gate every tween through one helper (`Motion.Tween(inst, info, goal)` that applies the goal instantly when reduced).

## Screens

Positions are in reference px, shown as `UDim2` (scale, offset). Use `AnchorPoint` as listed. Desktop is the 1920x1080 reference; phone is landscape, about 812x375 viewport at scale about 0.75 (sizes still in reference px).

### A. HUD

State fields: `Coins`, `Vault`, `VaultBonus`, `Building`, plot attributes `State`, `NextVisitorAt`, `ChallengerUnlocked`, `ChallengerQueued`.

Desktop:
- Currency panel: AnchorPoint (0.5,0), Position `UDim2.new(0.5,0,0,8)`, Size `UDim2.fromOffset(520,64)`. Two cells in a UIListLayout horizontal: Banked (coin icon + number) and Vault (chest icon + number + bonus pill "+25%"). The vault cell and bonus pill are hidden (`Visible=false`) until a treasure room is placed (`Vault` unlocked / bonus exists); never show a bonus of 0.
- Visitor status chip: AnchorPoint (0.5,0), Position `UDim2.new(0.5,0,0,80)`, Size `UDim2.fromOffset(360,40)`. Next visitor portrait + name when idle (no countdown: visitors arrive back to back), crossed swords while a visitor is inside, nothing while building. A Clock icon and "0:07" countdown appear only while a fixed delay is active (first visitor, build resume), computed from `NextVisitorAt - workspace:GetServerTimeNow()`, display only.
- Action bar: AnchorPoint (0.5,1), Position `UDim2.new(0.5,0,1,-16)`, Size `UDim2.fromOffset(760,72)`, five buttons 140x56 each with icon + label: Build, Bank, Shop, Invite Challenger (crown, label "Challenger"), Settings (gear, label can shrink to icon + "Settings"). Invite Challenger is shown disabled with reason text until `ChallengerUnlocked`, and shows "Queued" when `ChallengerQueued`.

Phone landscape:
- Currency panel: AnchorPoint (0,0), Position `UDim2.new(0,8,0,0)` under the safe inset, Size `UDim2.fromOffset(300,48)`, two cells stacked horizontally, font 22 -> keep 20 minimum.
- Status chip: AnchorPoint (0.5,0), Position `UDim2.new(0.5,0,0,0)`, Size `UDim2.fromOffset(260,40)`.
- Action buttons: right-side vertical column, AnchorPoint (1,0.5), Position `UDim2.new(1,-8,0.5,0)`, each 64x64 (icon above 12 px caption is too small, so caption 14 px under icon, button 72x64). Order: Build, Bank, Shop, Challenger, Settings. Thumb zone is the right edge; leave the left half free for the joystick and the dungeon view.

### B. Build mode

State fields: `Building`, `Rooms` (counts), `Layout`; route status text comes from the server result of Commit/placement requests.
- Dim nothing; show a top route-status banner: desktop AnchorPoint (0.5,0), Position `UDim2.new(0.5,0,0,96)`, Size `UDim2.fromOffset(640,44)`; phone Position `UDim2.new(0.5,0,0,52)`, Size `UDim2.fromOffset(420,40)`. Always icon + text: check + "Route connected" (Success border) or warning triangle (text "!") + plain-language reason such as "Entrance not connected to exit" (Danger border).
- Room inventory (bottom): desktop AnchorPoint (0.5,1), Position `UDim2.new(0.5,0,1,-16)`, Size `UDim2.fromOffset(900,132)`, horizontal `ScrollingFrame`, cards 112x112 (icon/name/"x3" count badge top-right). Zero-count cards are disabled with "x0". Phone: AnchorPoint (0.5,1), Position `UDim2.new(0.5,0,1,-4)`, Size `UDim2.fromOffset(560,104)`, cards 88x88 (above 44 minimum).
- Commit and Cancel: desktop AnchorPoint (1,1), Position `UDim2.new(1,-16,1,-160)`, each 160x56 stacked with 8 gap (Commit Success/Gold with check + "Commit", Cancel with X + "Cancel"). Phone: right column AnchorPoint (1,0.5), Position `UDim2.new(1,-8,0.5,0)`, each 120x56. Commit disabled while the last route status is invalid.
- Remove/Move: small buttons appear in the selected-room callout, 56x44 minimum.

### C. Encounter panel

State fields: plot attributes `VisitorId`, `VisitorHealth`, `VisitorMaxHealth`, `VisitorFighting`; reward and vault risk from the server-provided display data.
- Desktop: AnchorPoint (1,0), Position `UDim2.new(1,-16,0,96)`, Size `UDim2.fromOffset(340,200)`. Contents: skull icon + visitor name (Heading 24), health bar 300x20 pill (Danger fill when below 30%, text "HP 34/50" over bar so colour is not the only cue), row "Reward: +40" with coin icon, row "Vault risk: 15 gold" with chest icon and Danger text with a warning "!" prefix.
- Phone: AnchorPoint (1,0), Position `UDim2.new(1,-8,0,48)`, Size `UDim2.fromOffset(260,150)`; Body 16 minimum; hide the action column while an encounter runs only if overlap would occur (shift it down by 160 instead; do not hide).
- Result toast from `EncounterFx End` (Defeated / Escaped / Robbed) with icon and amount; sourced from server data only.

### D. Shop

- Panel: AnchorPoint (0.5,0.5), Position `UDim2.new(0.5,0,0.5,0)`. Desktop Size `UDim2.fromOffset(900,560)`; phone Size `UDim2.fromOffset(640,320)` (inside the safe area). Title bar 56 tall with title + close X button 56x44.
- Room cards grid (`UIGridLayout`): desktop CellSize `UDim2.fromOffset(200,220)`, phone `UDim2.fromOffset(180,170)`. Each card: icon, name, role tag (text, e.g. "Trap", "Defender", "Treasure"), cost with coin icon, "Owned: N", Buy button (full width, 44+ tall). Unaffordable: Buy disabled with "Need N more". Consequential purchases open a confirm (Confirm / Cancel) showing item and price; the server decides the result.
- Upgrade section: row at the bottom of the panel (desktop height 72) with arrow-up icon, current level -> next level, cost, Upgrade button.
- Never show random odds or imply chance (GDD Collection rule); no randomized rewards in the MVP shop.

### E. Tutorial prompt

- Bubble: AnchorPoint (0.5,1), Position `UDim2.new(0.5,0,1,-170)` on desktop, `UDim2.new(0.5,0,1,-120)` on phone; Size `UDim2.fromOffset(520,96)` (phone 420x88). Text 20 px, buttons Next (primary) and Skip (secondary, 44 min), via `TutorialAction`.
- Arrow highlight: a rotated `Frame` triangle replacement (use a text "v" glyph or a 24 px rounded square rotated 45 degrees) pointing at the target button, plus a Gold 4 px UIStroke pulse on the target. Reduced motion: static arrow, no pulse.
- Recover: if the player opens a different panel, the bubble re-anchors to the step's target instead of blocking.

### F. Settings

- Panel: AnchorPoint (0.5,0.5), Position `UDim2.new(0.5,0,0.5,0)`, Size desktop `UDim2.fromOffset(520,420)`, phone `UDim2.fromOffset(460,300)`.
- Rows (56 tall): Reduced motion toggle (switch 72x40 with "On"/"Off" text, not colour only), Music volume slider, SFX volume slider. Slider: track 260x12 pill, thumb 32x32 (hit area 44x44), numeric readout "70%". Changes send `SaveSettings {ReducedMotion, MusicVolume, SfxVolume}` (0-1 numbers), debounced 0.5 s. Apply locally immediately but treat the server snapshot as truth.

## Icons (no uploaded images yet)

No Roblox image assets exist yet; nothing may be uploaded. Until real icons are made, every icon is a short text label or a shape of Frames; icon slots are 32x32 (24 in compact HUD) and always accompanied by a text label. Later, swap in `ImageLabel`s with the same slot size.

| Icon | Used for | Fallback now |
| --- | --- | --- |
| Coin | Banked coins, costs, rewards | Gold circle: Frame 24x24, `UICorner(1,0)`, Gold fill, GoldDark 3 px stroke, inner "$" text |
| Vault/chest | Vault gold, risk | Frame 28x20 BgRaised + Gold 4 px top bar + small Gold square lock; label "Vault" |
| Hammer (Build) | Build button | Label "Build" with Frame handle (6x24, rotated 45) + head (16x10) |
| Bag (Shop) | Shop button | Rounded Frame 24x24, Accent fill, with "S" or just label "Shop" |
| Sword | Attack/defender | Text glyph "/" bold plus label; or rotated Frame 6x26 + crossguard 16x4 |
| Shield | Defender/defence | Frame 22x26, `UICorner(0.3,0)`, Accent fill, Stroke outline |
| Skull/visitor | Visitor name, encounter | Circle Frame 24x24 TextPrimary fill with two small dark eyes; label "Visitor" |
| Clock | Next-visitor timer | Circle Frame 24x24 stroke only, two thin hands (Frames); label shows the time |
| Gear | Settings | Label "Settings" with a Frame 22x22 `UICorner(1,0)` ring stroke 5 px |
| Crown (Challenger) | Invite Challenger | Gold row of three small Frames (6x14) over a 24x8 base; label "Challenger" |
| Arrow-up (Upgrade) | Upgrade | Text "^" bold in a Success circle, label "Upgrade" |

Naming for future assets (not created): `ui_coin`, `ui_vault`, `ui_hammer`, `ui_bag`, `ui_sword`, `ui_shield`, `ui_skull`, `ui_clock`, `ui_gear`, `ui_crown`, `ui_arrow_up`, stored under the Assets folder `BuildADungeon\ui\icons\` when made.

## Adaptations and Roblox constraints

- Safe zone: layouts start below the 58 px core top bar via `CoreUISafeInsets`; the original-style centre-top HUD stays within the inset area.
- Phone UIScale is derived from viewport height so 44 px touch targets hold; desktop uses the 1920x1080 reference.
- Readability: min 14 px captions, 16+ px body on phone; state never by colour alone (icon/text added to every status).
- Accessibility: reduced motion gate, adjustable audio, contrast values above computed from the palette (verify in Studio).
- Not validated in Studio on desktop or phone yet; treat positions as starting values.

## Mockup pass

The "Pending" note above is now resolved: the AI design assistant mockup pass was done in the owner's Chrome. Files live outside the repo (paths relative to `C:\Users\asus\Projects\Assets\`; prompts in `BuildADungeon\ui\mockups\PROMPTS.md`):

- `BuildADungeon\ui\mockups\01_hud_phone_desktop.png` (HUD, phone + desktop)
- `BuildADungeon\ui\mockups\02_build_mode_phone_desktop.png` (build mode)
- `BuildADungeon\ui\mockups\03_encounter_shop_desktop.png` (encounter panel + shop)
- `BuildADungeon\ui\mockups\04_tutorial_settings.png` (tutorial bubble + settings)
- `BuildADungeon\ui\mockups\05_icon_sheet_magenta.png` (11 icons on flat magenta; chroma-key before cutting; 12th cell empty)
- `BuildADungeon\reference\toy_dungeon_room_kit_and_adventurers.png` (art reference: 6 rooms, 6 characters)

Rights: generated by the owner's AI design assistant account; ownership and usage terms are not cleared for release, so treat as concept/reference until the owner confirms. Do not upload to Roblox.

Concept images are a direction only; the layouts and token names above stay authoritative. Short delta list worth adopting (existing token names kept):

- Icon-first buttons: the HUD action bar reads best as a rounded square with a large icon above the label (desktop bar buttons about 140x72, phone 72x64). Build is the primary call to action: use Success green fill `#4ADE80` with TextOnGold-dark text while the player has no rooms placed (tutorial), then BgRaised.
- Currency panel is a single plum pill (BgPanel, radius 1/2 of height) with a thin Stroke; coin number in FredokaOne 26, small muted caption ("Banked", "Vault") above the number. The bonus is a Gold pill "+25%" (TextOnGold). Keep the unplaced-vault rule: hide vault cell and pill until a treasure room exists.
- Status chip is a smaller pill under the currency panel with the clock icon on the left.
- Build mode: Commit as a large green button (Success fill, check icon) above Cancel (BgRaised, X icon), both 56 px tall minimum. Route banner uses a two-state pill: Success border plus check for valid; Danger border plus triangle for invalid, always with text.
- Room cards: isometric room icon on top, name, count badge as a small Gold pill at the bottom edge ("x3"); zero count uses Disabled fill and "x0".
- Encounter panel: character portrait at left of the card is optional (nice, not required); keep skull + name, then three inset rows (HP bar with text inside, Reward, Vault risk with "!" glyph).
- Shop: role chip (Trap/Defender/Treasure) with a small icon as a pill under the name; disabled Buy shows a lock icon plus "Need N more"; Upgrade row pinned at the bottom with arrow-up icon and green Upgrade button.
- Tutorial: cream bubble (use TextPrimary `#FFF6E0` fill, dark text `#1E1630`) with a mascot at left (wizard portrait) is a good friendly cue; arrow plus glow ring on the target in Gold. Reduced motion: static ring, no pulse.
- Settings: On/Off toggle shows a check plus the word "On"; sliders have a 32 px thumb and a value box at right (70%); each row has a leading icon.
- Adopt a slightly lighter panel plum for contrast against busy backgrounds: panel fill with 0.1 transparency is fine, but keep text on opaque fills.

Changes made versus the generated images, and why:

- Dropped the "Build a Dungeon" logo and device frames (not part of the UI).
- The phone HUD in the image stacks the action column over the right edge and lets the status chip overlap the diorama; the spec keeps the safe-area inset (`CoreUISafeInsets`) and the 58 px Roblox top bar clear.
- Icon labels under 14 px (the phone "Challenger" label is tiny in the image) must be 14 px minimum; abbreviate to "Chall." is not allowed, so use the crown icon with a 14 px caption and a wider 72 px button instead.
- Shop mockup shows 3 cards; real grids follow the `UIGridLayout` sizes in the Shop section above and scroll.
- Icon sheet icons are raster art with a built-in dark outline; in Roblox they are shown as `ImageLabel`s at 32x32 (24 compact). Until sliced and uploaded (owner action, not done), keep the Frame/text fallbacks from the Icons section.
- Clock and gear icons are cream/white in the sheet; on BgPanel they contrast well, but on Gold buttons use the dark outline only variant, or place them on a BgRaised chip.

## UI polish pass (2026-11-06)

The large panel, primary action, and disabled button use individually generated full elements, rather than a cut-up sprite sheet. The panel uses a calibrated nine-slice frame; the full primary button stretches as a whole so its edges remain intact. The group-owned images are 83520285511315, 115081075639992, and 132717535749322. Their original files and upload records are under `Assets/BuildADungeon/ui/sprites/ui_polish_v1/`. The prior sprites remain available in version history.

Tabs share available width, and the chest reveal fits the available viewport. Desktop Studio validation was performed; phone touch behavior, release rights and narrow-screen playback still need physical-device review.

Chest reveal results use the full panel art; the rarity name and gem carry the tier colour, with the Secret shimmer retained.
