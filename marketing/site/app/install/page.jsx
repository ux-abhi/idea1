// © Pexilim
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";
import PageScripts from "@/components/PageScripts";

export const metadata = {
  title: "Install Blink",
  description: "How to download, install and set up Blink, the free notch assistant for Mac.",
  alternates: { canonical: "/install" },
};

export default function InstallPage() {
  return (
    <>
      <SiteHeader />

      <main id="main" className="doc light">
        <h1>Install Blink.</h1>
        <p className="lede">Free, for MacBooks with a notch running macOS 26. It takes about three minutes once you have the download.</p>

        <div className="note" id="waitlist-note">
          <p><strong>Blink isn't public yet.</strong> Join the waitlist and we'll email you when it's ready to download. This guide is here so you know what to expect.</p>
          <div className="cta-row"><a className="btn" href="/#waitlist">Join the waitlist</a></div>
        </div>

        {/* Shown by js/install.js once downloads/Blink.dmg is on the server. */}
        <div className="download-box" id="download" hidden>
          <a className="btn" id="dmg-link" href="/downloads/Blink.dmg" download>Download Blink.dmg</a>
          <span className="size" id="dmg-size" hidden></span>
        </div>

        <div className="note warn">
          <p><strong>One extra step, the first time.</strong> This build isn't notarized by Apple yet, so the first time you open Blink, macOS stops it until you confirm in System Settings. Step 4 shows how. We'll ship a notarized build soon; until then macOS asks once.</p>
        </div>

        <h2>Install</h2>
        <ol className="steps-doc">
          <li><b>Download Blink.dmg.</b>Use the link in your waitlist email. It lands in your Downloads folder.</li>
          <li><b>Drag Blink into Applications.</b>Open Blink.dmg and drag the Blink icon onto the Applications folder. Then eject the disk image.</li>
          <li><b>Open Blink.</b>Open your Applications folder and double-click Blink. macOS says it can't check Blink and doesn't open it. Click <span className="path">Done</span>, not Move to Trash.</li>
          <li><b>Allow it in System Settings.</b>Open <span className="path">System Settings › Privacy &amp; Security</span> and scroll down to Security. Next to “Blink was blocked”, click <span className="path">Open Anyway</span>, enter your Mac password, then click <span className="path">Open Anyway</span> once more. You only do this the first time.</li>
        </ol>

        <h2>Set up</h2>
        <p>Blink opens with a short setup. You need no code and no terminal.</p>
        <ol className="steps-doc">
          <li><b>Server.</b>Click <span className="path">Sign in with Supabase</span>. Blink creates a free Supabase project in your own account and installs everything it needs. If something interrupts it, it picks up where it stopped. Already run a Supabase server? Choose <span className="path">I already have a server</span> and paste its address and publishable key.</li>
          <li><b>Account.</b>Create or sign in to the login on your own server. Each Mac is registered with your server, not with Pexilim.</li>
          <li><b>Calendar.</b>Allow Calendar access. Your next meeting shows up in the notch.</li>
          <li><b>About you.</b>Optional. Tell Blink a little about your day so its suggestions fit.</li>
        </ol>
        <p>For AI, paste a free Groq key during setup. Add a Claude or OpenRouter key later in <span className="path">Settings › Connections</span> if you want them. Keys are stored as secrets on your server and never shown again.</p>
        <p>Then press <kbd>⌃⌥Space</kbd> to ask Blink anything, or <kbd>⌃⌥V</kbd> for your clipboard.</p>

        <h2>Verify the download</h2>
        <p>To check that your copy is exactly the one we published, open Terminal and run:</p>
        <p><code>shasum -a 256 ~/Downloads/Blink.dmg</code></p>
        <p>The result should match this line:</p>
        <p><code id="dmg-sha">SHA-256: published here with the first release</code></p>

        <h2>Remove Blink</h2>
        <p>Quit Blink and move it from Applications to the Trash. Your data on your own server stays there until you delete it; deleting the Supabase project removes all of it.</p>

        <h2>Need help?</h2>
        <p>Write to <a href="mailto:hello@blinkk.app">hello@blinkk.app</a>.</p>
      </main>

      <SiteFooter current="install" />

      <PageScripts srcs={["/js/install.js"]} />
    </>
  );
}
