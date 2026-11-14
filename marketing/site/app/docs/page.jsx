// © Pexilim
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";
import { DOCS } from "@/lib/docs";

export const metadata = {
  title: "Blink docs",
  description: "Guides for Blink, the free notch assistant for Mac: setting it up, catching Apple Pay spends, and every keyboard shortcut.",
  alternates: { canonical: "/docs" },
};


export default function DocsPage() {
  return (
    <>
      <SiteHeader current="docs" />
      <main id="main" className="doc light">
        <h1>Docs.</h1>
        <p className="lede">Short guides for getting Blink going and getting more out of it.</p>
        <ul className="doc-list">
          {DOCS.map((d) => (
            <li key={d.href}>
              <a href={d.href}><b>{d.title}</b><span>{d.text}</span></a>
            </li>
          ))}
        </ul>
        <p>Can't find what you need? Write to <a href="mailto:hello@blinkk.app">hello@blinkk.app</a>.</p>
      </main>
      <SiteFooter current="docs" />
    </>
  );
}
