// © Pexilim
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";
import PageScripts from "@/components/PageScripts";

export const metadata = {
  title: "Confirm your email · Blink",
  description: "Confirm your spot on the Blink waitlist.",
  alternates: { canonical: "/confirm" },
  robots: { index: false },
};

export default function ConfirmPage() {
  return (
    <>
      <SiteHeader />

      <main id="main" className="doc light">
        <h1>One click and you're in.</h1>
        <p className="lede">Confirm that you asked to hear from us, and we'll email you when Blink is ready to download.</p>
        <p><button className="btn" type="button" id="waitlist-link" data-action="confirm" data-param="t" data-done="You're on the list. We'll email you when Blink is ready." data-missing="This link is missing its code. Use the button in your email, or join again on the home page.">Confirm my email</button></p>
        <p id="waitlist-link-status" role="status" aria-live="polite"></p>
        {/* Shown once confirmed: the five quick questions, while the person is here and keen. */}
        <div className="survey-cta" id="survey-cta" hidden>
          <h2>Got one more minute?</h2>
          <p>Five quick taps decide what we build first, and you can sign up to test Blink before anyone else.</p>
          <p><a className="btn" id="survey-cta-link" href="/survey">Help shape Blink</a></p>
        </div>
      </main>

      <SiteFooter />

      <PageScripts srcs={["/js/config.js", "/js/waitlist-link.js"]} />
    </>
  );
}
