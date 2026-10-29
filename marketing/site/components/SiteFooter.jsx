// © Pexilim

// `current` marks the page you're on ("install", "shortcuts", "privacy", "terms") for screen readers.
export default function SiteFooter({ current }) {
  const here = (page) => (current === page ? "page" : undefined);
  return (
    <footer className="site-foot">
      <div className="inner">
        <div className="foot-top">
          <div className="foot-sign">
            <p className="sign">Blink keeps an eye on your day, so you can get on with it.</p>
            <a className="btn small" href="/#waitlist">Join the waitlist</a>
          </div>
          <nav className="foot-cols" aria-label="Footer">
            <div><h2 id="f-product">Product</h2><ul aria-labelledby="f-product"><li><a href="/#features">Features</a></li><li><a href="/install" aria-current={here("install")}>Install guide</a></li><li><a href="/shortcuts" aria-current={here("shortcuts")}>Keyboard shortcuts</a></li></ul></div>
            <div><h2 id="f-company">Company</h2><ul aria-labelledby="f-company"><li>Pexilim</li><li><a href="mailto:hello@blinkk.app">hello@blinkk.app</a></li></ul></div>
            <div><h2 id="f-legal">Legal</h2><ul aria-labelledby="f-legal"><li><a href="/privacy" aria-current={here("privacy")}>Privacy</a></li><li><a href="/terms" aria-current={here("terms")}>Terms</a></li></ul></div>
          </nav>
        </div>
        <p className="copy"><small>© 2026 Pexilim</small></p>
      </div>
      <p className="wordmark" aria-hidden="true">Blink</p>
    </footer>
  );
}
