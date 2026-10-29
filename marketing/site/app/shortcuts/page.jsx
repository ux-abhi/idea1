// © Pexilim
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";
// The same list the app shows in Help › Keyboard Shortcuts (design/shortcuts.json; tests/shortcuts.test.mjs keeps this copy equal).
import shortcuts from "@/lib/shortcuts.json";

export const metadata = {
  title: "Blink keyboard shortcuts",
  description: "Every keyboard shortcut in Blink, the free notch assistant for Mac: in the notch, in the window, and the words you can type instead of clicking.",
  alternates: { canonical: "/shortcuts" },
};

export default function ShortcutsPage() {
  return (
    <>
      <SiteHeader />
      <main id="main" className="doc light">
        <h1>Keyboard shortcuts</h1>
        <p className="lede">Everything in Blink works from the keyboard. In the app, press ⌘/ to see this list.</p>
        {shortcuts.groups.map((group) => (
          <div key={group.name}>
            <h2>{group.name}</h2>
            <dl className="shortcut-list">
              {group.items.map((item) => (
                <div key={item.keys + item.what}>
                  <dt><kbd>{item.keys}</kbd></dt>
                  <dd>{item.what}</dd>
                </div>
              ))}
            </dl>
          </div>
        ))}
      </main>
      <SiteFooter current="shortcuts" />
    </>
  );
}
