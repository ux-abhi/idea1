# Going live (free, before the Apple Developer Program)

Blink ships as a free DMG from **www.blinkk.app** (the product is called Blink; the domain has two k's). It is ad-hoc signed, not notarized, so macOS asks once to **Open Anyway** (the site's install page shows how). Paying Apple's $99 later removes that step and adds automatic updates.

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
- The form posts to the site's own Vercel function `marketing/site/api/waitlist.mjs`. It stores the signup on the `pexilim` Supabase project (`backend/pexilim/`), which hands back the confirm and leave links only to that function (shared `MAILER_SECRET`, set on both sides), and it emails them through Resend with `RESEND_KEY` and `RESEND_FROM` from the Vercel project. The Resend key never leaves Vercel.
- Double opt-in: the person confirms on `confirm.html` and can leave from any email on `leave.html` (a click on the page, so mail scanners that open links can't confirm or remove anyone). Unconfirmed signups are deleted after 30 days.
- See who joined: Supabase › pexilim › Table Editor › `waitlist` (`confirmed_at` set = confirmed).
- Owner, once: Resend › Domains › `blinkk.app` must show **Verified** (its DNS records go in Vercel › Domains › blinkk.app). `RESEND_KEY` and `RESEND_FROM` are set for Production only, so preview deployments store signups without emailing.

## 3. Put the site up on Vercel (www.blinkk.app)
The site is plain files in `marketing/site/` (no build step).
1. Vercel › Add New › Project › import this repository, **Root Directory** `marketing/site`, Framework preset **Other**, no build command.
2. Vercel › the project › Domains: add `www.blinkk.app` and `blinkk.app` (redirect to www).
3. When the DMG is public, put it at `marketing/site/downloads/Blink.dmg` (the install page shows the button as soon as the file exists) and its SHA-256 on the install page.

## 4. Before the public launch
- [ ] One full first-run on a fresh Supabase account (one-click setup end to end).
- [ ] Check whether Supabase pauses a free project after a week without visits even though Blink's mail check runs every 5 minutes; if it does, tell users in Settings.
- [ ] Support address answered (hello@blinkk.app) and the privacy and terms pages read once more.
- [ ] Later, with the $99: Developer ID signing, notarization (`xcrun notarytool`), Sparkle updates, TestFlight for iPhone.
