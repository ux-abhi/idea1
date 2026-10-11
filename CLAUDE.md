# Blink (Pexilim)

Claude-powered personal assistant in the MacBook notch and the iPhone Dynamic Island. Built for Pexilim's own use first, written so that selling it later needs only a licence file.

## Source of truth
- `ARCHITECTURE.md` wins on any conflict; §36 (gap review) wins over earlier sections.
- `DESIGN.md` for look and motion; `design/tokens.json` for every colour, material, radius and motion value. Never hardcode a value that has a token.
- `PHASE0.md` for what to build right now. Build one phase at a time; each phase has a "done when" in ARCHITECTURE §29 and §36.7.

## How to work
- Ponytail mode (full): the smallest change that fully solves the task. Mark deliberate shortcuts with `// shortcut: <limit>, <when to upgrade>`. Never cut validation at trust boundaries, data-loss handling, security or accessibility.
- One small test for any new branch, parser, money or security logic.
- Use the installed skills for their topic (swiftui-*, activitykit, widgetkit, app-intents, eventkit, swift-security, swift-concurrency, swift-testing, ios-accessibility, sf-symbols, motion-design, ponytail-review before each commit).
- Build and run what you change. On the Mac: build with Xcode or `xcodebuild`, and look at the result before saying it works.

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
