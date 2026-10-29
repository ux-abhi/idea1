// © Pexilim
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";
import PageScripts from "@/components/PageScripts";

export const metadata = {
  title: "Leave the waitlist · Blink",
  description: "Leave the Blink waitlist.",
  alternates: { canonical: "/leave" },
  robots: { index: false },
};

export default function LeavePage() {
  return (
    <>
      <SiteHeader />

      <main id="main" className="doc light">
        <h1>Leave the waitlist?</h1>
        <p className="lede">We'll delete your email from the Blink waitlist right away. No more emails from us.</p>
        <p><button className="btn" type="button" id="waitlist-link" data-action="leave" data-param="u" data-done="Done. Your email is deleted and we won't write again." data-missing="This link is missing its code. Email hello@blinkk.app and we'll remove you by hand.">Remove my email</button></p>
        <p id="waitlist-link-status" role="status" aria-live="polite"></p>
      </main>

      <SiteFooter />

      <PageScripts srcs={["/js/config.js", "/js/waitlist-link.js"]} />
    </>
  );
}
