# Blink (Pexilim)

Claude-powered personal assistant in the MacBook notch and the iPhone Dynamic Island. Built for Pexilim's own use first, written so that selling it later needs only a licence file.

## Source of truth
- `ARCHITECTURE.md` wins on any conflict; §36 (gap review) wins over earlier sections.
- `DESIGN.md` for look and motion; `design/tokens.json` for every colour, material, radius and motion value. Never hardcode a value that has a token.
- `PHASE0.md` for what to build right now. Build one phase at a time; each phase has a "done when" in ARCHITECTURE §29 and §36.7.

## How to work
- **Ponytail is always on (level: full).** Load the `ponytail` skill at the start of every coding task: the smallest change that fully solves it. Mark deliberate shortcuts with `// shortcut: <limit>, <when to upgrade>`. Never cut validation at trust boundaries, data-loss handling, security or accessibility.
- **Before every commit:** run `/ponytail-review` on the change and fix every must-fix finding.
- **End of every phase:** run `/ponytail-audit` and `/ponytail-debt`; the phase is not done while the audit has must-fix items or a shortcut has no upgrade trigger.
- One small test for any new branch, parser, money or security logic.
- Build and run what you change. On the Mac: build with Xcode or `xcodebuild`, and look at the result before saying it works.

## Skills: load the matching one before writing code for that area
| Work | Skills |
|---|---|
| Any SwiftUI view or state | `swiftui-pro`, `swiftui-expert-skill`, `swiftui-patterns` |
| Layout, lists, forms, settings | `swiftui-layout-components` |
| Navigation, tabs, deep links | `swiftui-navigation` |
| Gestures, hover, drag | `swiftui-gestures` |
| Animation, the Blink eyes, notch morphs | `swiftui-animation`, `animation-patterns`, `motion-design`, `design-motion-principles` (values from `design/tokens.json` → `motion`) |
| Glass and materials | `swiftui-liquid-glass` |
| Icons | `sf-symbols` |
| Notch panel (NSPanel, AppKit) | `appkit-swiftui-bridge`, `macos-tahoe-apis` |
| Keychain, Face ID / Touch ID, Secure Enclave, pinning | `swift-security`, `authentication` |
| async/await, actors, Swift 6 errors | `swift-concurrency` |
| Local storage | `swiftdata` |
| Calendar and reminders | `eventkit` |
| Notifications and push | `push-notifications` |
| Dynamic Island, Live Activities | `activitykit`, `live-activity-generator` |
| Widgets, Control Center | `widgetkit` |
| Siri, Shortcuts, Spotlight | `app-intents` |
| Background work | `background-processing` |
| First run, setup | `onboarding-generator` |
| Habits and streaks | `streak-tracker` (but follow ARCHITECTURE §36.2 habit rules over its defaults) |
| Words on screen | `ux-writing` |
| Accessibility | `ios-accessibility` (every new screen) |
| Reviewing a screen | `swiftui-ux-review`, `ui-review-tahoe`, `ui-ux-pro-max` |
| Performance, battery | `swiftui-performance`, `debugging-instruments`, `metrickit` |
| Tests | `swift-testing` |
| Web app and design pages | `frontend-design`, `webapp-testing`, `gsap-*`, `motion-dev-animations` |
| Content engine (Phase 3) | `ig-*` |

## Code rules
- Swift 6, SwiftUI first, AppKit only for the notch panel. App targets: Approachable Concurrency with MainActor default. `BlinkKit`: no default isolation; sync engine is one actor.
- Apple system colours by name, never hex, in Swift.
- Nothing personal in code: names, emails, accounts, server address and keys come from setup and live in the Keychain or the user's server.
- Keychain: tokens use `AfterFirstUnlockThisDeviceOnly`; only the Secure Enclave approval key is biometry-bound (§36.5).
- Backend: every table has `owner_id` + RLS. Add a migration in `backend/supabase/migrations/`, extend `backend/supabase/tests/rls.sql`, run `backend/supabase/tests/run.sh`.

## Licences and secrets
- Shipped code: MIT, Apache-2.0 or BSD only. Record each new dependency in `THIRD_PARTY_NOTICES.md` in the same commit.
- Never copy code from GPL/AGPL projects (Boring Notch, Inbox Zero) or paste skill text into app code.
- Never commit secrets. `Local.xcconfig`, `.env` files, keys and certificates are git-ignored.

## Commits
Conventional commits (`feat:`, `fix:`, `docs:`, `chore:`). Small and focused.
