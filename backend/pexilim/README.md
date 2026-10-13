# Pexilim's own server (Supabase project `pexilim`, eu-central-1)

Not part of Blink: nothing here is installed on owners' servers. It holds what Pexilim itself runs:
- **waitlist**: emails from www.blinkk.app (table `waitlist`, function `waitlist`).
- later: the sign-in helper for one-click setup (see docs/LAUNCH.md §2).

Deploy from this folder: `npx supabase functions deploy waitlist --project-ref wjhvqnynjkljiqdmnyhw --no-verify-jwt --use-api`.
