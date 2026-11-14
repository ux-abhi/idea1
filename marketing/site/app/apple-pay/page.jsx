// © Pexilim
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";
import DocsShell from "@/components/DocsShell";

export const metadata = {
  title: "Catch Apple Pay spends with Blink",
  description: "Set up an iPhone Shortcuts automation so every Apple Pay tap shows up in Blink's Money page within seconds. About three minutes, no app to install.",
  alternates: { canonical: "/apple-pay" },
};

// The steps match the app's own (Money › Apple Pay › Set Up on iPhone, CaptureViews.swift): change both together.
export default function ApplePayPage() {
  return (
    <>
      <SiteHeader current="docs" />
      <DocsShell current="/apple-pay">
        <h1>Catch every Apple Pay tap.</h1>
        <p className="lede">Pay with your iPhone and the spend appears in Blink's Money page within seconds, already sorted. It takes about three minutes and uses Apple's Shortcuts app; there's no Blink app to install on the iPhone.</p>

        <h2>Before you start</h2>
        <ul>
          <li>Blink on your Mac, signed in to your server.</li>
          <li>An iPhone with Apple Pay and the <b>Shortcuts</b> app (it's built in).</li>
          <li>The Mac and iPhone on the same Apple Account, so you can copy on one and paste on the other.</li>
        </ul>

        <h2>On your Mac</h2>
        <ol className="steps-doc">
          <li><b>Open Money in Blink.</b>On the Apple Pay card, click <span className="path">Set Up on iPhone…</span></li>
          <li><b>Make a link.</b>Name it after the iPhone (say “iPhone 15”) and click <span className="path">Make Link</span>. Blink shows an <strong>Address</strong> and a <strong>Key</strong>, each with a Copy button. The key is shown only now, so keep this window open until you're done.</li>
        </ol>

        <h2>On your iPhone</h2>
        <ol className="steps-doc">
          <li><b>Start a new automation.</b>Open <span className="path">Shortcuts › Automation › +</span> and pick <span className="path">Transaction</span>. Choose your cards, select <span className="path">Run Immediately</span>, then <span className="path">New Blank Automation</span>.</li>
          <li><b>Add “Get Contents of URL”.</b>Search for it and add it. Paste the <strong>Address</strong> from your Mac. Tap <span className="path">›</span> and set Method to <span className="path">POST</span>.</li>
          <li><b>Add the key.</b>Under Headers, add <code>Authorization</code> and paste the <strong>Key</strong> as its value. It starts with “Bearer”.</li>
          <li><b>Send the payment.</b>Under Request Body choose <span className="path">JSON</span> and add three text fields: <code>amount</code> with <span className="path">Shortcut Input › Amount</span>, <code>merchant</code> with <span className="path">Merchant</span>, and <code>card</code> with <span className="path">Card or Pass</span>.</li>
          <li><b>Optional: see what Blink saved.</b>Add <span className="path">Show Notification</span> with <span className="path">Contents of URL</span>.</li>
          <li><b>Pay once to test.</b>Tap your iPhone to pay. The spend shows up in Money; change or delete it there.</li>
        </ol>

        <h2>What it looks like when it's right</h2>
        <figure className="shortcut-mock" aria-label="The finished Get Contents of URL action in Shortcuts">
          <div className="sm-card">
            <p className="sm-title"><span className="sm-icon" aria-hidden="true">↗</span> Get contents of <span className="sm-token">https://…/functions/v1/capture</span></p>
            <dl>
              <div><dt>Method</dt><dd><span className="sm-token">POST</span></dd></div>
              <div><dt>Headers</dt><dd><code>Authorization</code> <span className="sm-token">Bearer ••••••</span></dd></div>
              <div><dt>Request Body</dt><dd><span className="sm-token">JSON</span></dd></div>
              <div><dt><code>amount</code></dt><dd><span className="sm-var">Amount</span></dd></div>
              <div><dt><code>merchant</code></dt><dd><span className="sm-var">Merchant</span></dd></div>
              <div><dt><code>card</code></dt><dd><span className="sm-var">Card or Pass</span></dd></div>
            </dl>
          </div>
          <figcaption>Blue words are what you paste or pick; the orange ones are taken from each payment.</figcaption>
        </figure>

        <h2>Which account it goes to</h2>
        <p>Blink names the account from the card: a card called “Visa Debit” goes to your Visa account. If no account matches, the spend goes to your default account. Receipts that also arrive by mail are added only once.</p>

        <h2>Private by design</h2>
        <p>Each tap goes straight from your iPhone to your own server, with a key only that iPhone has. Pexilim never sees your spending. To stop an iPhone sending taps, click <span className="path">Remove</span> next to it on the Apple Pay card; make a new link to start again.</p>

        <h2>If a tap doesn't show up</h2>
        <ul>
          <li><b>Nothing at all:</b> check the automation is set to <span className="path">Run Immediately</span>, and that the Address was pasted whole.</li>
          <li><b>The notification says “unauthorized”:</b> the Key is missing “Bearer” or a character; copy it again from a new link.</li>
          <li><b>Wrong amount or merchant:</b> make sure each JSON field uses the payment's own value (orange), not typed text.</li>
          <li><b>Several iPhones:</b> make one link per iPhone with <span className="path">Add Another iPhone</span>.</li>
        </ul>

        <h2>Need help?</h2>
        <p>Write to <a href="mailto:hello@blinkk.app">hello@blinkk.app</a>.</p>
      </DocsShell>
      <SiteFooter current="apple-pay" />
    </>
  );
}
