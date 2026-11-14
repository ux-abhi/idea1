// © Pexilim
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";

export const metadata = {
  title: "Blink docs",
  description: "Guides for Blink, the free notch assistant for Mac: setting it up, catching Apple Pay spends, and every keyboard shortcut.",
  alternates: { canonical: "/docs" },
};

// New guides go first in this list.
const DOCS = [
  { href: "/docs/setup", title: "Set up Blink", text: "From the first launch to your next meeting in the notch, step by step with pictures. About 5 minutes." },
  { href: "/apple-pay", title: "Catch Apple Pay spends", text: "One Shortcuts automation on your iPhone, and every tap shows up in Money within seconds." },
  { href: "/shortcuts", title: "Keyboard shortcuts", text: "Every shortcut in the notch and the window, and the words you can type instead of clicking." },
  { href: "/install", title: "Install Blink", text: "Download, move to Applications, and the one extra step macOS asks for the first time." },
];

export default function DocsPage() {
  return (
    <>
      <SiteHeader />
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
