# Third-party notices

Blink is proprietary software of **Pexilim** (see LICENSE).

## Runtime dependencies (shipped in the app)

Pinned in `apps/Blink/BlinkKit/Package.resolved`.

| Component | Version | License | Source |
|---|---|---|---|
| supabase-swift | 2.55.3 | MIT | https://github.com/supabase/supabase-swift |
| swift-crypto (via supabase-swift) | 4.5.2 | Apache-2.0 | https://github.com/apple/swift-crypto |
| swift-asn1 (via swift-crypto) | 1.7.3 | Apache-2.0 | https://github.com/apple/swift-asn1 |
| swift-http-types (via supabase-swift) | 1.8.0 | Apache-2.0 | https://github.com/apple/swift-http-types |
| swift-clocks (via supabase-swift) | 1.1.1 | MIT | https://github.com/pointfreeco/swift-clocks |
| swift-concurrency-extras (via supabase-swift) | 1.4.1 | MIT | https://github.com/pointfreeco/swift-concurrency-extras |
| swift-issue-reporting (via supabase-swift) | 2.1.1 | MIT | https://github.com/pointfreeco/swift-issue-reporting |
| xctest-dynamic-overlay (via supabase-swift) | 1.13.1 | MIT | https://github.com/pointfreeco/xctest-dynamic-overlay |

## Backend dependencies (Edge Functions)

| Component | Version | License | Source |
|---|---|---|---|
| supabase-js | 2.49.4 | MIT | https://github.com/supabase/supabase-js |
| Anthropic TypeScript SDK (`@anthropic-ai/sdk`) | 0.128.0 | MIT | https://github.com/anthropics/anthropic-sdk-typescript |

## Planned runtime dependencies

None planned. DynamicNotchKit and rive-ios were considered and are not used: the notch and the eyes are Blink's own code.

Rule: only MIT, Apache-2.0, BSD, ISC or zlib in shipped code. GPL/AGPL projects (e.g. Boring Notch, Inbox Zero) are reference-only. See ARCHITECTURE.md §32.

## Website (marketing/site, not part of the app)

Served from the site itself (no CDN), not part of the app.

| Component | Version | License | Source |
|---|---|---|---|
| GSAP core + ScrollTrigger (self-hosted in js/vendor) | 3.13.0 | GSAP Standard "no charge" license (free, including commercial use; not MIT) | https://gsap.com/standard-license |
| Inter, Latin subset (self-hosted in assets/fonts) | v20 | SIL Open Font License 1.1 | https://github.com/rsms/inter |

## Development tools (not shipped)

Claude Code skills in `.claude/skills/` help development and are never part of the app or backend. Their sources, pinned commits and licenses are listed in [SKILLS.md](SKILLS.md). License texts sit next to each skill.

| Source | License |
|---|---|
| Jakeschincariol/instagram-agent-skill (`ig-*`) | MIT |
| DietrichGebert/ponytail (`ponytail*`) | MIT |
| anthropics/skills (`frontend-design`, `webapp-testing`) | Apache-2.0 |
| nextlevelbuilder/ui-ux-pro-max-skill | MIT |
| AvdLee/SwiftUI-Agent-Skill | MIT |
| rshankras/claude-code-apple-skills | MIT |
| 199-biotechnologies/swiftui-claude-skills, motion-dev-animations-skill | MIT |
| lottiefiles/motion-design-skill | MIT |
| kylezantos/design-motion-principles | MIT |
| greensock/gsap-skills | MIT |
| dpearson2699/swift-ios-skills | PolyForm Perimeter 1.0.0 (any use except a competing product) |
| remotion-dev/skills (`remotion-*`) | No licence file (docs-only) |
| elevenlabs/skills (`sound-effects`) | MIT |

## Marketing videos (not shipped)

`marketing/intro-video/` makes the Blink intro video. Nothing in it ships with the app or backend.

| Component | License | Source |
|---|---|---|
| Remotion | Remotion License: free for companies of up to 3 people; a company licence is needed beyond that | https://www.remotion.pro/license |
| Inter (font, via @remotion/google-fonts) | SIL Open Font License 1.1 | https://github.com/rsms/inter |
| Kenney Interface Sounds and Impact Sounds (in `public/sfx/kenney/`, via kapishdima/soundcn) | CC0 1.0 | https://kenney.nl |
| "Product Launch" by lnplusmusic (`public/music/`, git-ignored, not redistributed) | Pixabay Content License (owner confirmed the source, 2026-10-13) | https://pixabay.com/users/lnplusmusic/ |
