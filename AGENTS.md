# Build a Dungeon — Agent Build Rules

These instructions apply to all AI agents and LLM-assisted work in this repository. Follow the user's current instructions and any higher-priority platform or tool requirements. If a nested `AGENTS.md` adds more specific instructions, follow it for that directory. Read `docs/GDD.md` and `docs/BUILD_PHASES.md` before implementing game systems, and update the relevant design documents when the user approves a change in direction.

## Reuse existing work

- Before creating a new system or asset, inspect this repository and, when useful, look through `C:\Users\asus\Projects\Roblox` for reusable code, UI patterns, models, animation, VFX or utilities. Search narrowly first and read the relevant implementation and its dependencies.
- Prefer adapting a suitable existing solution over recreating it. Verify that it fits this game's architecture, security model, device targets and license or ownership constraints. Do not assume something is safe or reusable merely because it exists in another project.
- Copy or adapt only the pieces needed into this repository; preserve attribution or license notices where required. Do not modify, move or delete assets or code in another project unless the user explicitly asks. Never copy credentials, secrets, production data or unrelated private information.
- Record meaningful reused assets and dependencies in the appropriate documentation. If an asset's origin or permission is uncertain, flag it rather than presenting it as cleared for release.

## Server authority and anti-cheat

- Security is a core design requirement. Treat the client, all client-provided data and remote arguments as untrusted. The client requests actions and renders feedback; the server decides and applies game state.
- The server owns and validates currency, purchases, inventory, room placement and ownership, dungeon paths, visitor spawning and movement outcomes, combat/encounter resolution, rewards, theft, unlocks, upgrades and saved progress. Client-side predictions and visuals must never grant rewards or change authoritative state.
- Validate remote argument types, ranges, ownership, permissions, costs, cooldowns, plot boundaries, connections and current game state. Reject impossible or stale requests and rate-limit where appropriate. Avoid relying on hidden client code, obscurity or client-only checks for security.
- Serialize conflicting mutations per player, handle retries and make encounter payouts idempotent. Plan for disconnects, duplicate requests, concurrent sessions and failed persistence calls. A failed profile load must never be saved over with default data.
- Test both normal play and adversarial cases relevant to each feature, including replayed requests and altered values. Keep server performance and false positives in mind; document assumptions and any remaining risks. Do not claim a system is cheat-proof.

## UI design workflow — ChatGPT in the browser

- For UI elements that need to be designed, use ChatGPT through the user's already logged-in account in the browser as a design aid, when that browser/account is available and the current task's tool permissions allow it. Inspect the existing game and reusable UI first, then supply the relevant design context and ask for a concrete UI concept, layout or visual direction. Adapt and implement the resulting work in the game; do not treat generated output as automatically correct or production-ready.
- Use existing authenticated browser sessions and supported browser/computer-use tools. Do not ask for, extract, store or copy passwords, cookies, session tokens or other credentials. Do not sign out, change account settings, or initiate purchases or subscriptions.
- Do not send secrets, private production data or unrelated project files to the browser service. Share only the minimum context needed for the UI task, consistent with the user's instructions and applicable tool rules.
- If the logged-in session, browser access or necessary tool is unavailable, explain the limitation and continue useful work that does not depend on it. Do not pretend the browser was used. If the UI design itself depends on that workflow, leave that dependent part pending and tell the user what access is needed.
- Validate UI in Roblox for desktop and mobile, including touch targets, safe areas, readability, contrast and reduced-motion/effects options where relevant. Generated concepts do not replace in-game testing.

## Implementation and scope

- Follow the existing Rojo layout. `src/shared` holds only the remote contract (`Net/Remotes`) and tiny generic utilities (`Core/Loader`, `Core/Signal`). Definitions, balance and game rules are server-only (`src/server/Definitions`, `src/server/Rules`). `src/client` holds input and presentation only: it receives display data through the `GetCatalog` remote, the `State` snapshot and replicated plot attributes, asks the server to check layouts (`PreviewLayout`), and does no game math beyond presentation (tweens, interpolation). Do not move rules or balance back into `src/shared` for the client's convenience; add a catalog, State or attribute field instead. Inspect the current project before introducing a framework or new dependency.
- Build to the current approved phase. Prefer a small playable vertical slice, reusable room definitions and clear interfaces over speculative systems or a large content dump. Keep tunable balance separate from core logic.
- Keep room layout and encounter behavior understandable to players. Protect the established vision: dungeon building and NPC visitors are the core; direct dungeon crawling, player-controlled troops and raiding are not MVP requirements.
- Do not silently change the economy, monetization, save schema or player-facing rules. Document design assumptions and migration needs. Check current platform requirements before implementing any paid randomized rewards.
- Preserve the user's existing changes. Avoid unrelated refactors, destructive operations or edits outside the task. Ask only when a necessary decision cannot reasonably be inferred from the user's request.

## Verification and handoff

- Run checks appropriate to the change and test meaningful failure cases. For gameplay changes, include server validation, persistence implications and relevant multiplayer behavior; for UI, check desktop and mobile when the available environment permits.
- Be explicit about what was tested, what could not be tested in Studio or a published place, and any remaining risks. Do not invent test results. Keep implementation notes and phase status current when behavior or scope changes.
