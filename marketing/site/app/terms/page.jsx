// © Pexilim
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";

export const metadata = {
  title: "Blink terms",
  description: "The terms for using Blink, the free notch assistant for Mac by Pexilim.",
  alternates: { canonical: "/terms" },
};

export default function TermsPage() {
  return (
    <>
      <SiteHeader />

      <main id="main" className="doc light">
        <h1>Terms</h1>
        <p className="lede">The rules for using Blink, in plain words.</p>
        <p className="updated">Last updated 13 October 2026</p>

        <h2>Using Blink</h2>
        <p>Blink is made by Pexilim. You may download Blink and use it for free, for yourself or your work. Blink stays Pexilim's software: please don't copy, sell or redistribute it, or pass off changed versions as Blink.</p>

        <h2>Your accounts and costs</h2>
        <p>Blink works with services you sign up for yourself: Supabase for your server, AI providers such as Anthropic, Groq and OpenRouter, your mail accounts, and any others you connect. Those accounts, their terms and any charges are between you and each provider. Blink stops paid AI models for the day when they reach your daily limit, but that limit is a convenience, not a guarantee: check your providers' billing too.</p>

        <h2>Your data</h2>
        <p>Your data lives on your Mac and on your own server, so you're responsible for keeping it backed up. See the <a href="/privacy">privacy policy</a> for where everything is kept.</p>

        <h2>AI can be wrong</h2>
        <p>Blink uses AI to sort mail, draft replies, sort spending and suggest posts, and AI makes mistakes. That's why Blink asks before it acts: read each card before you approve it. You're responsible for what you approve and send.</p>

        <h2>Fair use</h2>
        <p>Don't use Blink to break the law, send spam, get into accounts or mailboxes that aren't yours, or break the terms of the services you connect.</p>

        <h2>Provided as is</h2>
        <p>Blink is free and provided “as is”, without any warranty. It may have bugs, and features may change or stop. As far as the law allows, Pexilim isn't liable for losses that come from using Blink, including lost data, missed messages or charges from services you connect. Nothing here limits rights you have by law that can't be limited.</p>

        <h2>Updates and ending</h2>
        <p>We may update Blink and these terms. If the terms change, we'll update this page and the date at the top. You can stop using Blink at any time by deleting it; your server stays yours.</p>

        <h2>Contact</h2>
        <p><a href="mailto:hello@blinkk.app">hello@blinkk.app</a></p>
      </main>

      <SiteFooter current="terms" />

    </>
  );
}
