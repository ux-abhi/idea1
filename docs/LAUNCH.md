# Going live (free, before the Apple Developer Program)

Blink ships as a free DMG from **blink.pexilim.com**. It is ad-hoc signed, not notarized, so macOS asks once to **Open Anyway** (the site's install page shows how). Paying Apple's $99 later removes that step and adds automatic updates.

## 1. Build the download
```
apps/Blink/scripts/release.sh
```
Makes `apps/Blink/build/release/Blink-<version>.dmg` and its `.sha256`. It needs `Config/Local.xcconfig` (bundle ID prefix and `BLINK_SIGNIN_HELPER`). Bump `MARKETING_VERSION` in `Config/Base.xcconfig` for each release.

What's different from an Xcode build: no `keychain-access-groups` (only a team-signed build may carry it), so the login and the Touch ID approval key live in the login keychain instead of the data-protection keychain. Everything else works the same. One catch: an Xcode build and a DMG build on the same Mac don't share a login, so sign in once in each.

Before giving it to anyone: install the DMG on a second Mac or a second macOS user account, do **Open Anyway**, and run the whole first-run (Sign in with Supabase → Account → Calendar).

## 2. Move the sign-in helper to its own project (owner, about 10 minutes)
Today the helper (`functions/signin`) runs on the same Supabase project as your own Blink data. Before strangers use one-click setup, give it its own free project so their traffic never touches yours:
1. The project exists: `pexilim` (ref `wjhvqnynjkljiqdmnyhw`, Frankfurt), which already holds the waitlist (`backend/pexilim/`).
2. Deploy the helper there: `npx supabase functions deploy signin --project-ref wjhvqnynjkljiqdmnyhw --no-verify-jwt --use-api` (from `backend/`).
3. Add the secrets `BLINK_OAUTH_CLIENT_ID` and `BLINK_OAUTH_CLIENT_SECRET` to the new project (Edge Functions › Secrets), the same values as now.
4. In your Supabase OAuth app settings, change the redirect URL to `https://wjhvqnynjkljiqdmnyhw.supabase.co/functions/v1/signin/callback`.
5. Set `BLINK_SIGNIN_HELPER = https:/$()/wjhvqnynjkljiqdmnyhw.supabase.co/functions/v1/signin` in `Config/Local.xcconfig`, rebuild, and remove the `BLINK_OAUTH_*` secrets and the `signin` function from your personal project.

## Waitlist
The site posts to `https://wjhvqnynjkljiqdmnyhw.supabase.co/functions/v1/waitlist` (`backend/pexilim/`). See who joined: Supabase › pexilim › Table Editor › `waitlist`. Each row has an `unsubscribe` id for the link in the launch email; delete a row when someone asks.

## 3. Put the site up (owner decides the host)
The site is plain files in `marketing/site/` (no build step). Any static host works; Vercel or Cloudflare Pages are free.
1. Upload `marketing/site/` and put the DMG at `downloads/Blink.dmg` (and its SHA-256 on the install page).
2. Add a DNS record at your domain registrar: `blink.pexilim.com` as a CNAME to the host's address.
3. Check the install page link from the DMG ("How to open Blink") opens.

## 4. Before the public launch
- [ ] One full first-run on a fresh Supabase account (one-click setup end to end).
- [ ] Check whether Supabase pauses a free project after a week without visits even though Blink's mail check runs every 5 minutes; if it does, tell users in Settings.
- [ ] Support address answered (hello@pexilim.com) and the privacy and terms pages read once more.
- [ ] Later, with the $99: Developer ID signing, notarization (`xcrun notarytool`), Sparkle updates, TestFlight for iPhone.
