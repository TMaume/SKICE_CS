# SKICE_CS — Roadmap

Personal CS2 companion for iOS. Zero-trust by design. No third-party APIs in the MVP runtime.

- Last updated: 2026-10-16
- Platform: iOS 17+ (SwiftUI, OLED black)
- Toolchain: xtool (SwiftPM cross-compilation, Linux -> iOS), no Xcode project

---

## 0. Guiding rules

### 0.1 No third-party APIs in the MVP

The app talks only to first-party services: Valve/Steam (Web API, inventory, market) and FACEIT (v4). Third-party data sources are opt-in, deferred, and must respect zero-trust (see ADR-02).

### 0.2 Zero-trust & data privacy

- Credentials (SteamID64, Steam Web API key, FACEIT API key) live only in the iOS Keychain. No middleman, no relay server.
- Steam session tokens (OAuth / Steam Guard), once introduced, stay on-device and are never transmitted.
- No telemetry. Debug logs are local and gated behind Developer Mode.

---

## 1. Stack

- Swift / SwiftUI, iOS 17+ (Observation, async/await).
- Design system: OLED-black dark theme (`AppTheme`), CS2-inspired.
- Build: SwiftPM package built with xtool (cross-compiled Linux -> iOS). No .xcodeproj, no Xcode.
- SPM dependencies: currently zero. Future additions (e.g. SwiftProtobuf for the GC) must be justified and minimal.

---

## 2. Authentication model (two tiers)

Tier A — MVP (key-based). SteamID64 + Steam Web API key stored in Keychain. Enables the public inventory reader and basic stats. No OpenID.

Tier B — Auth session Steam (DELIVERED 2026-10-16). Real Steam session tokens via QR or password + Steam Guard, stored in the Keychain. Required for anything that touches the Game Coordinator: Loadouts, Inspect Float / Seed / Stickers.

Tier B is delivered; GC-dependent work is now unblocked.

Note: the Web API inventory reader requires a public Steam profile; private inventories surface an explicit error state.

---

## 3. Modules

| Module | Name | State | Auth tier |
|---|---|---|---|
| M0 | Profile / Home | Delivered | A |
| M1 | Remote Match | Placeholder | A |
| M2 | Loadout (GC) | Scrapped | B |
| M3 | Inventory & Economy | Delivered (partial) | A (+B for Float/Seed) |
| M4 | Stats | Delivered (partial) | A |
| M5 | Tactics | Placeholder | A |

### M0 — Profile / Home (delivered)

Steam identity card, connection status, career snapshot, FACEIT badge, shortcuts.

### M1 — Remote Match (placeholder)

Live match pipeline on the gaming PC:

- Local UDP log receiver (CS2 `-netconport`), parse connection / game-state lines.
- Optional killfeed via GSI (see Amendment).
- Forward to the iPhone via APNs.
- Must stay VAC-safe / read-only; never inject into the game.

### M2 — Loadout (GC) — SCRAPPED

The read-only GC Loadout (equip-slot) feature was built, then scrapped by the owner (2026-10-16) as unusable. The GC session, protobuf framing and attribute decode were reused for the Inspect (float / seed / stickers) feature; scrapped files are parked in /tmp/skice-scrapped.

### M3 — Inventory & Economy (delivered, partial)

- Steam inventory parser (assets/descriptions -> `SkinItem`): rarity, exterior, trade-lock state, StatTrak / Souvenir.
- UI: grid/list, search, filters (sheet), market value bar.
- Pricing: Steam Community Market (EUR) ONLY (`/market/priceoverview`), local cache ~24h, ~400 items/pass, concurrency 6. Third-party price sources (Buff163, Skinport, CSFloat) are out of the MVP and deferred (see ADR-02).
- Trade-Up Contract calculator: deterministic Valve engine (majority collection, R -> R+1, normalized average float, all-or-nothing StatTrak, souvenir rejected), EV/ROI in EUR, embedded local catalog. Delivered.

Dependency — Float / Pattern Seed / Stickers:
Float Value, Pattern Index (Seed) and Stickers come from the Game Coordinator "Inspect Item" payload. They require an authenticated Steam session (OAuth / Steam Guard), NOT the Web API key -> gated by the Tier B milestone. Until then the inventory exposes rarity, exterior and StatTrak / Souvenir only.

Trade-up catalog data source:
The collections dataset is baked at build time from an open dataset (ByMykel/CSGO-API `skins.json`) and embedded in the app. No third-party call happens at runtime (offline-friendly, zero-trust compliant). Updating it = regenerate + new build.

### M4 — Stats (delivered, partial)

- Career stats: Steam Web API (career) + FACEIT v4 (ELO / match history).
- Local snapshot cache.
- Scope: live ingestion = Steam Web API + FACEIT v4. Valve "Match Share Codes" and the .dem demo parser belong to Phase 4. The GSI module (Amendment) depends on the Desktop Daemon (Phase 3).

### M5 — Tactics (placeholder)

Lineups (smokes / molotovs), economy & round logic, map-specific tips.

---

## 4. Amendment — GSI via Desktop Daemon

CS2 Game State Integration (GSI) only emits locally. To use it on the phone:

- A small Desktop Daemon (Python) runs on the gaming PC, listens to the CS2 GSI HTTP POST, normalizes JSON, and relays to the iPhone (APNs or local socket).
- The daemon is optional and local-only; it never proxies Steam credentials.
- Dependency: Phase 3.

---

## 5. Phases

### Phase 1 — MVP

- Tier A auth: SteamID64 + Steam Web API key in Keychain (no OpenID).
- Inventory reader via the Steam Web API (public profile required; private -> explicit error).
- Dashboard: Steam identity + base stats (Steam Web API + FACEIT v4).
- Native SwiftUI UI (iOS 17+).
- Exit milestone (BLOCKING): "Auth session Steam" (OAuth / Steam Guard tokens) — the gateway to Phase 2.

### Phase 2 — Economy -> Auth -> GC

1. Price history (Steam EUR) — builds on M3.
2. Trade-Up simulator (EV/ROI) — delivered.
3. BLOCKING MILESTONE — Auth session Steam (OAuth / Steam Guard). ✔ delivered 2026-10-16.
4. GC Protobuf: Loadouts — scrapped (unusable).
5. GC Inspect: Float / Seed / Stickers — delivered.

### Phase 3 — Desktop Daemon

- Local daemon for GSI + NetCon-based Remote Match, APNs relay.

### Phase 4 — Advanced analytics

- Match Share Codes ingestion, .dem demo parser, deeper performance analytics.

### Phase 5 — UI / UX polish

- Theme is natively OLED Black (dark-only by default, non-negotiable for OLED). Light mode is OPTIONAL / deferred, non-blocking for release.

---

## 6. Technical specifics

### 6.1 Toolchain & deployment

- Host: Linux with an editor of choice (Windows/Linux supported).
- Build: `xtool dev build` (cross-compilation Linux -> iOS; output `xtool/SKICE_CS.app`).
- Install: `xtool install --usb xtool/SKICE_CS.app` (physical iPhone over USB).
- Do NOT use `xtool launch` (team-prefixed bundle ID): relaunch the app by hand.
- Bundle ID: com.dtl21.SKICEcs. Device: dt.l21.

### 6.2 Architecture

```
Sources/SKICE_CS/
├── App/                 # entry point, TabView, AppTab
├── Core/
│   ├── Network/         # direct Steam/FACEIT API clients, GC socket, NetCon
│   ├── Storage/         # Keychain, local caches (credentials, prices, stats snapshots)
│   ├── Models/          # shared entities (User, Item, Session)
│   └── Utils/           # DebugLogger, network helpers
├── UI/
│   ├── Theme/           # AppTheme (colors, fonts, modifiers)
│   └── Components/      # reusable views (Settings, DebugLogs, SafariView)
└── Modules/
    ├── Profile/         # M0 Home
    ├── Inventory/       # M3 inventory + pricing + trade-up
    ├── Stats/           # M4 Steam + FACEIT
    ├── Loadout/         # M2 GC              [empty placeholder]
    ├── RemoteMatch/     # M1                 [empty placeholder]
    └── Tactics/         # M5                 [empty placeholder]
```

### 6.3 FACEIT privacy

- FACEIT API key stored locally only; requests go directly from the device to FACEIT.
- No FACEIT data is forwarded to any third party.

### 6.4 DebugLogger

- In-app ring-buffer logger; Developer Mode (Settings) unlocks a debug console.
- No remote shipping.

---

## 7. Implementation state (2026-10-16)

DELIVERED

- Auth Tier A (SteamID64 + Web API key in Keychain; no OpenID).
- Auth session Steam (Tier B): QR or password sign-in with Steam Guard; refresh/access tokens in the Keychain; "remember password" for quick re-connect.
- Inventory: Steam parser, rarity / exterior / trade-lock badges, grid + list, search, filters (sheet).
- Pricing: Steam Community Market EUR, 24h local cache, ~400 items/pass, concurrency 6.
- Trade-Up: Valve engine (majority collection, R -> R+1, normalized average float, all-or-nothing StatTrak, souvenir rejected), EV/ROI EUR, embedded local catalog.
- Stats: Steam Web API (career) + FACEIT v4 (history / ELO), local snapshot.
- Logging: DebugLogger + Developer Mode.
- GC Inspect: exact wear float / pattern seed / StatTrak kills / applied stickers, read from the Game Coordinator (Tier B) and cached on-device (ItemInspectionStore).

NOT STARTED (empty placeholders)

- Remote Match / M1 (daemon + APNs), Tactics / M5 (lineups / economy), Demo Parser.

SCRAPPED

- Loadout / M2 (GC equip slots) — unusable; superseded by GC Inspect.

CORE REFACTOR (2026-10-16)

- Open-source readability pass: dead code removed; Core no longer depends on Modules; stores split from models; duplicated logic deduped (SteamID64 validator, UTC day-bucket, JSON file cache); GC protobuf decode extracted; doc comments normalised; logging helpers renamed.

---

## 8. Decisions (ADR)

- ADR-01 Auth MVP = key-based (SteamID64 + Web API key); OAuth / Steam Guard deferred until the "Auth session Steam" milestone. Delivered 2026-10-16 (QR + password + Steam Guard, tokens in Keychain).
- ADR-02 Pricing = Steam Community Market EUR only; third-party sources deferred.
- ADR-03 Trade-up catalog = baked local dataset; no third-party runtime calls.
- ADR-04 Zero-trust: no intermediary infra, no credential relay; everything stays on-device.
- ADR-05 Phase 2 order: Economy / Trade-up BEFORE GC (GC is blocked by auth).
- ADR-06 Toolchain: xtool / SwiftPM, no Xcode / .xcodeproj; SPM dependencies minimal (currently 0).

---

## 9. Backlog — porting ideas from Recon Bolt (Valorant companion)

Reference: Recon-Bolt — a Valorant companion app (open-source), cloned at /home/dtl21/Documents/Recon-Bolt. Reviewed 2026-10-16. Its UI/UX patterns port; its third-party packages (HandyOperators, UserDefault) are NOT adopted (ADR-06: zero SPM deps). Roughly in priority order.

1. Image caching (M3). SKICE_CS grids use bare `AsyncImage`; Recon Bolt has a dedicated `ImageManager`: an actor that deduplicates concurrent downloads, a size-capped in-memory cache (256x256 px) falling back to disk for large images, version-aware re-download via sidecar metadata, and 50 ms-batched UI updates. Port the pattern for Steam CDN thumbnails to kill grid-scroll jank on large inventories. Still zero-trust (images come straight from Steam).
2. Rank / rating tracking + widgets (M0). Recon Bolt's origin feature: track competitive rank over time (`RankInfoView`, `ActRankView`) plus home-screen widgets. CS2 analog: track CS Rating / Premier rating history and ship a WidgetKit widget. New capability — no equivalent today.
3. Live-match UI (M1, Phase 3). Recon Bolt `LiveMatchView`: a map-splash hero (200 pt, material overlay, mode label) over a team-grouped player list with agent icon + rank badge. Template for a CS2 live scoreboard + round-kill feed (GSI / NetCon).
4. Stats visualisations (M4). Win-rate, hit-distribution heatmap, playtime. CS2 additions: per-map win rate, hit distribution, playtime.
5. Reference tab (M5 Tactics). Recon Bolt `AgentInfoView` / `WeaponInfoView`: offline, browsable reference. Template for a weapon / map / callout reference tab.
6. Localisation infrastructure. Recon Bolt is fully localised (`String(localized:comment:)`, .lproj, Crowdin, 22 languages). SKICE_CS is English-only. First step: extract user-facing strings into a Localizable catalog (English only) so it is translation-ready. Large diff — treat as its own phase.
7. Small wins. `@SceneStorage` tab persistence; a reusable `CircularProgressView`; a storage-management screen (show + clear each cache); a screenshot privacy toggle (Recon Bolt's `AnonymizationMode`).

### 9.1 Armory pass vs. Night Market — feasibility

Recon Bolt's Night Market is a live, per-account, rotating discounted store fetched from Riot's API after login (`client.getStorefront()`; `Storefront.NightMarket` with `discountPercent` + `remainingDuration`, alongside the daily store, featured bundles and the accessory store).

CS2's Armory is a different shape: a pass + Armory Stars + a redeem store. There is no first-party Web API for it, and a player's personalised state (Stars balance, redeemed items, current featured offers) is not exposed. Only the catalogue (collections, items, Star prices) is bakeable, like the trade-up catalogue (ADR-03).

- Feasible (zero-trust): a read-only Armory catalogue view from baked data, cross-referenced against the GC inventory cache (already available) to flag Armory items you own.
- Not feasible like the Night Market: a live, personalised Armory. Whether undocumented Game Coordinator Armory messages exist is unverified and would need reverse-engineering.
