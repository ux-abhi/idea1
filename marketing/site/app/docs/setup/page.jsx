// © Pexilim
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";
import DocsShell from "@/components/DocsShell";

export const metadata = {
  title: "Set up Blink",
  description: "How to set up Blink, the free notch assistant for Mac, from the first launch: your own server, sign in, your calendar, and the first things to try.",
  alternates: { canonical: "/docs/setup" },
};

// Screenshots are Blink's real setup screens (a sample meeting stands in for a real one). Retake them with the Debug
// build's -docs.step launch argument when a screen changes: see DocsShot in apps/Blink/Blink/OnboardingView.swift.
function Shot({ n, name, height, alt }) {
  return (
    <figure className="shot">
      <img src={`/assets/docs/setup-${n}-${name}.png`} alt={alt} width="600" height={height} loading={n > 1 ? "lazy" : undefined} />
    </figure>
  );
}

export default function SetupPage() {
  return (
    <>
      <SiteHeader current="docs" />
      <DocsShell current="/docs/setup">
        <h1>Set up Blink.</h1>
        <p className="lede">From the first launch to your next meeting in the notch. It takes about five minutes, and you need no code and no terminal.</p>

        <h2>Before you start</h2>
        <ul>
          <li>A MacBook with a notch, on macOS 26 or later.</li>
          <li>Blink in your Applications folder. Not there yet? Follow the <a href="/install">install guide</a> first.</li>
          <li>A free <a href="https://supabase.com" rel="noopener">Supabase</a> account with an organization. Blink puts your private server there. Making the account takes a minute: sign up, confirm your email, and create an organization when Supabase asks.</li>
        </ul>

        <h2>1. Welcome</h2>
        <p>Open Blink. It says hello and shows what it does: your day in the notch, your data on your own server, and nothing sent or booked without your OK. Click <span className="path">Get Started</span>.</p>
        <Shot n={1} name="welcome" height={580} alt="Blink's welcome screen: the Blink eyes, “Meet Blink”, three short promises and a Get Started button." />

        <h2>2. Your own server</h2>
        <p>Blink keeps your notes, mail and money in a private server that belongs to you, not to us. Click <span className="path">Create My Server</span>. Supabase opens in your browser: sign in and allow Blink. Blink then creates the server and installs everything it needs, which takes about three minutes. If anything interrupts it, it picks up where it stopped.</p>
        <Shot n={2} name="server" height={410} alt="The “Your own server” step with a Create My Server button and an “I already have a server” link." />
        <p>Already set Blink up on another Mac? Choose <span className="path">I already have a server</span> and paste its address and publishable key, from your Blink project in Supabase under Project Settings › Data API and API Keys. If you used Blink on this Mac before, a <span className="path">Reconnect</span> button takes you straight back.</p>

        <h2>3. Sign in</h2>
        <p>Click <span className="path">Sign in with Supabase</span> and use the same Supabase account. Blink remembers it on this Mac, so you won't type a password. Prefer email? Open <span className="path">Sign in with email instead</span>. Picked the wrong server? <span className="path">Use a different one</span> takes you back.</p>
        <Shot n={3} name="account" height={330} alt="The Sign in step with a Sign in with Supabase button, an email option and a link to use a different server." />

        <h2>4. See your day</h2>
        <p>Click <span className="path">Allow Calendar</span>; macOS asks about your calendars and reminders. Blink then shows your real next meeting. It reads calendars on this Mac and taps you in the notch ten minutes before each meeting.</p>
        <Shot n={4} name="calendar" height={370} alt="The See your day step showing the next meeting, “Design review with Sam”, beside a pair of Blink eyes." />

        <h2>5. About you</h2>
        <p>Tick <span className="path">I post on social media</span> if you'd like help with posts, and keep <span className="path">Open Blink when I log in</span> on so your day is ready when you sit down. Click <span className="path">Open Blink</span>. Mail, money and habits come later; Today shows what's left to set up, when you want it.</p>
        <Shot n={5} name="about" height={350} alt="The About you step with a social media checkbox, an “AI is ready” line, an Open at login checkbox, and Skip and Open Blink buttons." />

        <h2>First things to try</h2>
        <ul>
          <li><kbd>⌃⌥Space</kbd> asks Blink anything: “What's left today?” or “remind me to call Sam at 4pm”.</li>
          <li><kbd>⌃⌥D</kbd> dictates into any app: speak, then press it again to type it where your cursor is.</li>
          <li><kbd>⌃⌥B</kbd> takes a voice command: “open Chrome and play Alphas”.</li>
          <li><kbd>⌃⌥V</kbd> opens your clipboard history, and <kbd>⌃⌥K</kbd> searches everything.</li>
          <li>Move the pointer onto the notch to peek at your day; click it to open.</li>
        </ul>
        <p>You can change any of these keys in <span className="path">Settings › Shortcuts</span>. All of them are on the <a href="/shortcuts">keyboard shortcuts</a> page.</p>

        <h2>Make it yours</h2>
        <ul>
          <li><b>AI.</b> Chat works on this Mac for free. For mail sorting, drafts and better answers, add a free Groq key, or a Claude or OpenRouter key, in <span className="path">Settings › Connections</span>. Pick which model does what in <span className="path">Settings › AI</span>.</li>
          <li><b>Mail.</b> Connect Gmail, iCloud or any IMAP mailbox in <span className="path">Settings › Connections</span>; Blink brings up only what matters.</li>
          <li><b>Money.</b> Add your accounts in Money, and <a href="/apple-pay">catch Apple Pay taps</a> from your iPhone.</li>
          <li><b>A name.</b> Call your assistant something else in <span className="path">Settings › General › Name</span>.</li>
        </ul>

        <h2>If something goes wrong</h2>
        <ul>
          <li><b>“No free project left”:</b> free Supabase accounts get two projects. Pause or delete one at supabase.com/dashboard, then try again.</li>
          <li><b>Supabase asks for an organization:</b> create one on supabase.com (it's free), then click Create My Server again.</li>
          <li><b>Calendar shows nothing:</b> allow Blink in System Settings › Privacy &amp; Security › Calendars.</li>
          <li><b>Dictation or voice commands don't type:</b> allow Blink in System Settings › Privacy &amp; Security › Accessibility.</li>
        </ul>

        <h2>Need help?</h2>
        <p>Write to <a href="mailto:hello@blinkk.app">hello@blinkk.app</a>.</p>
      </DocsShell>
      <SiteFooter current="docs" />
    </>
  );
}
