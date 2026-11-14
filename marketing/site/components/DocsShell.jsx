// © Pexilim
import { DOCS } from "@/lib/docs";

// A guide's page: the list of guides beside it (on top on a phone) with this one marked, the guide itself, and
// Previous / Next at the end, so every guide leads to the others.
export default function DocsShell({ current, children }) {
  const i = DOCS.findIndex((d) => d.href === current);
  const prev = i > 0 ? DOCS[i - 1] : null;
  const next = i >= 0 && i < DOCS.length - 1 ? DOCS[i + 1] : null;
  return (
    <div className="docs-shell">
      <nav className="docs-nav" aria-label="Docs">
        <a className="docs-home" href="/docs">Docs</a>
        <ul>
          {DOCS.map((d) => (
            <li key={d.href}><a href={d.href} aria-current={d.href === current ? "page" : undefined}>{d.title}</a></li>
          ))}
        </ul>
      </nav>
      <main id="main" className="doc light">
        {children}
        {(prev || next) && (
          <nav className="docs-pager" aria-label="More guides">
            {prev ? <a className="prev" href={prev.href}><span>Previous</span>{prev.title}</a> : <span />}
            {next ? <a className="next" href={next.href}><span>Next</span>{next.title}</a> : <span />}
          </nav>
        )}
      </main>
    </div>
  );
}
