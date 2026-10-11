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

## Planned runtime dependencies

| Component | License | Source |
|---|---|---|
| DynamicNotchKit | MIT | https://github.com/MrKai77/DynamicNotchKit |
| rive-ios | MIT | https://github.com/rive-app/rive-ios |

Rule: only MIT, Apache-2.0, BSD, ISC or zlib in shipped code. GPL/AGPL projects (e.g. Boring Notch, Inbox Zero) are reference-only. See ARCHITECTURE.md §32.

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
