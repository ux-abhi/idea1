// © Pexilim

// The menu bar with a notch, like the Mac's. On the home page the welcome screen shrinks into it and main.js moves the
// eyes; elsewhere they just blink (css-blink).
export default function SiteHeader({ home = false }) {
  return (
    <header className="site-head">
      <div className="inner">
        <a className="brand" href="/" aria-label="Blink home">Blink</a>
        <nav aria-label="Main">
          <a href="/#features">Features</a>
          <a href="/#privacy">Privacy</a>
          <a href="/#faq">FAQ</a>
        </nav>
        <a className="btn small" href="/#waitlist" aria-label="Join the waitlist"><span>Join<span className="wide"> the waitlist</span></span></a>
      </div>
      <span className="head-notch" aria-hidden="true">
        <span className="eyes-look"><img className={home ? undefined : "css-blink"} src="/assets/eyes-idle.png" alt="" width="320" height="160" /></span>
      </span>
    </header>
  );
}
