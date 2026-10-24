// © Pexilim
import { preload } from "react-dom";
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";
import PageScripts from "@/components/PageScripts";

export const metadata = {
  title: "Blink: your day, one glance up",
  description: "Blink is a free personal assistant for Mac that lives in your MacBook's notch. Mail, clipboard, search, your day, habits, money and content, on your own server with your own keys. Join the waitlist.",
  alternates: { canonical: "/" },
  openGraph: {
    title: "Blink: your day, one glance up",
    description: "A free personal assistant that lives in your MacBook's notch. By Pexilim. Join the waitlist.",
    images: ["/assets/blink-film-poster.jpg"],
  },
};

export default function Home() {
  preload("/assets/eyes-idle.png", { as: "image" });
  preload("/assets/fonts/bricolage-latin.woff2", { as: "font", type: "font/woff2", crossOrigin: "anonymous" });
  return (
    <>

      <svg width="0" height="0" style={{ position: 'absolute' }} aria-hidden="true" focusable="false">
        <symbol id="i-doc" viewBox="0 0 24 24"><path d="M7 3h7l5 5v13H7z" /><path d="M14 3v5h5M10 13h6M10 17h6" /></symbol>
        <symbol id="i-link" viewBox="0 0 24 24"><path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1" /><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1" /></symbol>
        <symbol id="i-file" viewBox="0 0 24 24"><path d="M6 3h8l4 4v14H6z" /><path d="M9 14h6M9 17h4" /></symbol>
        <symbol id="i-note" viewBox="0 0 24 24"><rect x="5" y="3" width="14" height="18" rx="3" /><path d="M9 8h6M9 12h6M9 16h3" /></symbol>
        <symbol id="i-check" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" /><path d="m8 12 3 3 5-6" /></symbol>
        <symbol id="i-bell" viewBox="0 0 24 24"><path d="M6 17V11a6 6 0 0 1 12 0v6l1.5 2h-15z" /><path d="M10 21h4" /></symbol>
        <symbol id="i-search" viewBox="0 0 24 24"><circle cx="11" cy="11" r="6.5" /><path d="m16 16 4.5 4.5" /></symbol>
        <symbol id="i-key" viewBox="0 0 24 24"><circle cx="8" cy="15" r="4.5" /><path d="m11.2 11.8 8.3-8.3M16.5 6.5l2.5 2.5M14 9l2 2" /></symbol>
        <symbol id="i-lock" viewBox="0 0 24 24"><rect x="5" y="10.5" width="14" height="10" rx="2.5" /><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5" /></symbol>
        <symbol id="i-off" viewBox="0 0 24 24"><path d="M3 12s3.5-6.5 9-6.5S21 12 21 12s-3.5 6.5-9 6.5S3 12 3 12z" /><circle cx="12" cy="12" r="2.8" /><path d="M4 20 20 4" /></symbol>
        <symbol id="i-mac" viewBox="0 0 24 24"><rect x="4" y="5" width="16" height="11" rx="1.5" /><path d="M2 19h20" /></symbol>
        <symbol id="i-mail" viewBox="0 0 24 24"><rect x="3.5" y="5.5" width="17" height="13" rx="2.5" /><path d="m4.5 7 7.5 6 7.5-6" /></symbol>
      </svg>

      <SiteHeader home />

      {/* Welcome: a black screen that, as you scroll, shrinks into the notch above (main.js). Decorative; the hero says the same. */}
      <div className="intro" id="intro" aria-hidden="true">
        <div className="intro-words">
          <p className="intro-hi"><span className="intro-hi-words">Welcome to</span><span className="intro-eyes"><span className="eyes-look"><img src="/assets/eyes-idle.png" alt="" width="320" height="160" /></span></span></p>
          <p className="intro-name">Blink</p>
          <p className="intro-what">A personal assistant that lives in your MacBook's notch.</p>
        </div>
        <p className="intro-scroll">Scroll to continue<svg viewBox="0 0 24 24"><path d="m6 9 6 6 6-6" /></svg></p>
      </div>

      <main id="main">

        {/* Hero (light) */}
        <section className="hero light" aria-labelledby="hero-title">
          <div className="wrap hero-head">
            <h1 id="hero-title" className="hero-in">Your day, one <mark className="hl">glance&nbsp;up.</mark></h1>
            <p className="lede hero-in">Blink lives in your MacBook's notch. It tells you what's next, what matters in your inbox, and <mark className="hl soft">never acts without your OK</mark>.</p>
            <div className="cta-row hero-in">
              <a className="btn" href="#waitlist">Join the waitlist</a>
              <a className="btn ghost" href="#film" data-play-film>Watch the film</a>
            </div>
            <p className="cta-note hero-in">Free for MacBooks with a notch, on macOS 26. Your data stays on your own server.</p>
          </div>

          <div className="wrap">
            <figure className="mac" id="hero-mac">
              <div className="bezel">
                <div className="screen">
                  <div className="menubar" aria-hidden="true"><span><b>Notes</b><span>File</span><span>Edit</span><span>View</span><span>Window</span></span><span>Tue 13 Oct&nbsp;&nbsp;09:20</span></div>
                  <div className="desk-win" aria-hidden="true"></div>
                  <div className="notch" id="hero-notch">
                    <div className="eyes-slot" aria-hidden="true"><div className="eyes-look"><img src="/assets/eyes-idle.png" alt="" width="320" height="160" /></div></div>
                    <div className="notch-body">
                      <div className="moment">
                        <div className="notch-label"><i className="m-dot"></i><span className="m-kind">Next up</span><span className="m-when">in 10 min</span></div>
                        <div className="notch-q">Design review with Sam</div>
                        <div className="notch-a">The call link is on your clipboard. Your notes from last week are open.</div>
                        <div className="m-acts"><span className="m-act">Join call</span><span className="m-act alt">Snooze 5 min</span></div>
                      </div>
                    </div>
                  </div>
                  <div className="screen-keys" aria-hidden="true"><kbd>⌃</kbd><kbd>⌥</kbd><kbd>Space</kbd></div>
                </div>
              </div>
              <div className="base" aria-hidden="true"></div>
              <figcaption className="sr-only">A MacBook screen. Blink's eyes sit in the notch, which opens to show what matters right now: the next meeting, an important email, the clipboard, a spend and a habit.</figcaption>
            </figure>
            <div className="moments" id="hero-moments" role="group" aria-label="Show a moment in the notch"></div>
          </div>
        </section>

        {/* Film (dark) */}
        <section id="film" className="band dark" aria-labelledby="film-title">
          <div className="wrap">
            <div className="head">
              <h2 id="film-title">Meet Blink in 60 seconds.</h2>
              <p className="sub">The notch, the eyes and a day with Blink. With sound.</p>
            </div>
            <div className="film-frame">
              <video id="film-video" preload="none" playsInline poster="/assets/blink-film-poster.jpg" width="1280" height="720" aria-label="Blink launch film, 60 seconds, with music">
                <source src="/assets/blink-film.mp4" type="video/mp4" />
              </video>
              <button className="play" type="button" id="film-play">
                <span className="disc"><svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#fff" d="M6 4.5v15a1 1 0 0 0 1.5.86l12.5-7.5a1 1 0 0 0 0-1.72L7.5 3.64A1 1 0 0 0 6 4.5z" /></svg></span>
                <span>Play the film</span>
              </button>
            </div>
          </div>
        </section>

        {/* Everyday bento (mist): five tiles, one demo each */}
        <section id="features" className="mist" aria-labelledby="features-title">
          <div className="wrap">
            <div className="head">
              <h2 id="features-title">A lot of help in a small notch.</h2>
              <p className="sub">The five things you'll reach for every day. Each tile is a working demo, so go ahead and click.</p>
            </div>

            <div className="bento">

              {/* Ask: wide, dark */}
              <article className="tile dark t-ask" id="ask" aria-labelledby="ask-title">
                <div className="tile-text">
                  <h3 id="ask-title">Ask anything.</h3>
                  <p>Press <kbd>⌃⌥Space</kbd> and type. Blink answers in the notch, with the model you pick.</p>
                  <div className="models" role="group" aria-label="Choose a model (demo)">
                    <button className="model" type="button" aria-pressed="true" data-note="Claude, with your own Anthropic key.">Claude</button>
                    <button className="model" type="button" aria-pressed="false" data-note="A free model on Groq, with your free Groq key.">Llama 3.3 <small>Free</small></button>
                    <button className="model" type="button" aria-pressed="false" data-note="One of a few top models through your own OpenRouter credit.">Gemini 3.1</button>
                  </div>
                  <p className="model-note" id="model-note" aria-live="polite">Claude, with your own Anthropic key.</p>
                </div>
                <div className="tile-demo" id="ask-mock">
                  <div className="chat">
                    <div className="chat-top"><img src="/assets/eyes-idle.png" alt="" width="56" height="28" /></div>
                    <div className="bubble-q">Plan my day around the thesis review.</div>
                    <div className="bubble-a">Deep work on chapter 3 from 10 to 12, thesis review at 2, gym at 5:30. Want me to block the time?</div>
                    <div className="m-acts" aria-hidden="true"><span className="m-act">Block the time</span><span className="m-act alt">Not now</span></div>
                  </div>
                </div>
              </article>

              {/* Mail: the bento's one peek */}
              <article className="tile t-mail" id="mail" aria-labelledby="mail-title">
                <span className="peeker" aria-hidden="true"><span className="head"><span className="eyes-look"><img loading="lazy" src="/assets/eyes-important.png" alt="" width="320" height="160" /></span></span></span>
                <div className="tile-text">
                  <h3 id="mail-title">Reads your mail.</h3>
                  <p>Tells you what matters. Click a mail to teach it that sender.</p>
                </div>
                <div className="tile-demo">
                  <div className="mail" id="mail-list">
                    <button className="row" type="button" aria-pressed="false"><span className="grow"><span className="t">Job Alerts</span><span className="m">25 new jobs picked for you</span></span><span className="verdict">Not important</span></button>
                    <button className="row imp" type="button" aria-pressed="true"><span className="grow"><span className="t">Prof. Weber</span><span className="m">Thesis meeting moved to Friday</span></span><span className="verdict">Important</span></button>
                    <button className="row" type="button" aria-pressed="false"><span className="grow"><span className="t">StreamBox</span><span className="m">Your plan renews in 3 days</span></span><span className="verdict">Not important</span></button>
                  </div>
                </div>
              </article>

              {/* Clipboard */}
              <article className="tile t-clip" id="clipboard" aria-labelledby="clip-title">
                <div className="tile-text">
                  <h3 id="clip-title">Everything you copy.</h3>
                  <p>Press <kbd>⌃⌥V</kbd> to search your last 50 copies. Passwords are never kept.</p>
                </div>
                <div className="tile-demo" id="clip-mock">
                  <label className="field"><svg aria-hidden="true"><use href="#i-search" /></svg><span className="sr-only">Search the clipboard demo</span><input id="clip-search" type="search" placeholder="Search" autoComplete="off" spellCheck="false" /></label>
                  <ul className="clip-list" id="clip-list">
                    <li className="row" draggable="true"><span className="icon"><svg aria-hidden="true"><use href="#i-doc" /></svg></span><span className="grow"><span className="t">Q4 plan: launch on the 20th</span><span className="m">Text from Notes</span></span></li>
                    <li className="row" draggable="true"><span className="icon"><svg aria-hidden="true"><use href="#i-doc" /></svg></span><span className="grow"><span className="t">Meeting notes, 13 Oct</span><span className="m">Text from Notes</span></span></li>
                    <li className="row" draggable="true"><span className="icon"><svg aria-hidden="true"><use href="#i-link" /></svg></span><span className="grow"><span className="t">example.com/invoice/2026-10</span><span className="m">Link from Safari</span></span></li>
                    <li className="row" draggable="true"><span className="icon"><svg aria-hidden="true"><use href="#i-file" /></svg></span><span className="grow"><span className="t">Invoice_October.pdf</span><span className="m">File from Finder</span></span></li>
                    <li className="row" draggable="true"><span className="icon"><svg aria-hidden="true"><use href="#i-doc" /></svg></span><span className="grow"><span className="t">Invoice #2041, €240.00</span><span className="m">Text from Mail</span></span></li>
                  </ul>
                  <p className="sr-only" id="clip-count" aria-live="polite"></p>
                </div>
              </article>

              {/* ⌘K */}
              <article className="tile t-search" aria-labelledby="search-title">
                <div className="tile-text">
                  <h3 id="search-title">Find anything.</h3>
                  <p>Press <kbd>⌃⌥K</kbd> in any app to search notes, tasks, reminders and posts.</p>
                </div>
                <div className="tile-demo palette" id="search-mock">
                  <label className="field"><svg aria-hidden="true"><use href="#i-search" /></svg><span className="sr-only">Search the Blink demo</span><input id="find-search" type="search" defaultValue="thesis" autoComplete="off" spellCheck="false" /></label>
                  <div className="hits" id="find-list">
                    <div className="row hit on" data-k="thesis outline"><span className="icon"><svg aria-hidden="true"><use href="#i-note" /></svg></span><span className="grow t">Thesis outline</span><span className="kind">Note</span></div>
                    <div className="row hit" data-k="thesis weber draft"><span className="icon"><svg aria-hidden="true"><use href="#i-check" /></svg></span><span className="grow t">Send draft to Prof. Weber</span><span className="kind">Task</span></div>
                    <div className="row hit" data-k="thesis weber meeting"><span className="icon"><svg aria-hidden="true"><use href="#i-bell" /></svg></span><span className="grow t">Thesis meeting, Fri 10:00</span><span className="kind">Reminder</span></div>
                    <div className="row hit" data-k="thesis chapter"><span className="icon"><svg aria-hidden="true"><use href="#i-doc" /></svg></span><span className="grow t">Thesis, chapter 3</span><span className="kind">Space</span></div>
                    <div className="row hit" data-k="launch post blink" hidden><span className="icon"><svg aria-hidden="true"><use href="#i-doc" /></svg></span><span className="grow t">Launch post for Blink</span><span className="kind">Post</span></div>
                    <div className="row hit" data-k="launch q4 plan" hidden><span className="icon"><svg aria-hidden="true"><use href="#i-note" /></svg></span><span className="grow t">Q4 plan: launch on the 20th</span><span className="kind">Note</span></div>
                  </div>
                  <p className="sr-only" id="find-count" aria-live="polite"></p>
                </div>
              </article>

              {/* Ask-First: dark */}
              <article className="tile dark t-af" id="ask-first" aria-labelledby="af-title">
                <div className="tile-text">
                  <h3 id="af-title">Never without your OK.</h3>
                  <p>Sending, posting and paying wait for your Touch ID.</p>
                </div>
                <div className="tile-demo approve">
                  <div className="draft" aria-hidden="true"><span className="to">To Prof. Weber</span>Friday at 10 works. See you then.</div>
                  <p className="q">Send this reply?</p>
                  <div className="touch" id="touch">
                    <button type="button" id="touch-btn" aria-describedby="touch-label">
                      <span className="sr-only">Approve with Touch ID (demo)</span>
                      <svg viewBox="-50 -50 100 100" aria-hidden="true">
                        <circle className="ring-bg" r="44" fill="none" strokeWidth="4" />
                        <circle className="ring" r="44" fill="none" strokeWidth="4" pathLength="100" strokeLinecap="round" transform="rotate(-90)" />
                        <g className="print" fill="none" strokeWidth="3" strokeLinecap="round">
                          <path d="M-16 12 A20 20 0 0 1 -20 0 A20 20 0 0 1 20 0 L20 6" />
                          <path d="M-9 18 A13 13 0 0 1 -13 4 A13 13 0 0 1 13 4 L13 13" />
                          <path d="M0 20 L0 5" />
                        </g>
                        <path className="tick" d="M-18 2 L-5 15 L20 -12" fill="none" strokeWidth="6" strokeLinecap="round" strokeLinejoin="round" />
                      </svg>
                    </button>
                    <div className="touch-label" id="touch-label" aria-live="polite">Click to approve with Touch ID</div>
                  </div>
                </div>
              </article>

            </div>
          </div>
        </section>

        {/* Showcase (light): one feature at a time */}
        <section id="more" className="light" aria-labelledby="more-title">
          <div className="wrap">
            <div className="head">
              <h2 id="more-title">Then it looks after the rest.</h2>
              <p className="sub">Your day, your money, your habits and your posts, plus eyes that tell you what's going on. Pick one.</p>
            </div>

            <div className="showcase">
              <div className="tabs" role="tablist" aria-label="More of what Blink does" aria-orientation="vertical">
                <button className="tab" type="button" role="tab" id="tab-day" aria-controls="day" aria-selected="true">Your day<small>Brief, meeting card, check-in</small></button>
                <button className="tab" type="button" role="tab" id="tab-money" aria-controls="money" aria-selected="false" tabIndex="-1">Money<small>Balance and where it went</small></button>
                <button className="tab" type="button" role="tab" id="tab-habits" aria-controls="habits-panel" aria-selected="false" tabIndex="-1">Habits<small>Streaks and gentle nudges</small></button>
                <button className="tab" type="button" role="tab" id="tab-content" aria-controls="content" aria-selected="false" tabIndex="-1">Content<small>Ideas and drafts in your voice</small></button>
                <button className="tab" type="button" role="tab" id="tab-moods" aria-controls="moods" aria-selected="false" tabIndex="-1">Moods<small>What the eyes mean</small></button>
              </div>

              <div className="stage">
                <div className="panel" role="tabpanel" id="day" aria-labelledby="tab-day" tabIndex="0">
                  <div className="panel-text">
                    <h3>Plans your day. Then tomorrow.</h3>
                    <p>A morning brief from your calendar, a meeting card ten minutes before, focus timers, and an evening check-in that sets up tomorrow.</p>
                  </div>
                  <div className="panel-demo" id="day-mock">
                    <div className="peeks" aria-hidden="true">
                      <div className="mini-notch" style={{ '--c': 'var(--mint)' }}><img loading="lazy" src="/assets/eyes-headsup.png" alt="" width="52" height="26" />Thesis review in 10 min</div>
                      <div className="mini-notch" style={{ '--c': 'var(--orange)' }}><img src="/assets/eyes-idle.png" alt="" width="52" height="26" />Plan tomorrow?</div>
                    </div>
                    <div className="timeline" role="img" aria-label="Timeline: standup 9:30, deep work 10 to 12, lunch 12:30, thesis 2 to 4 pm, gym 5:30 to 6:30.">
                      <div className="block short" style={{ '--c': 'var(--mint)', left: '5%', width: '5%' }}>Standup</div>
                      <div className="block" style={{ '--c': 'var(--blue-fill)', left: '10%', width: '20%' }}>Deep work</div>
                      <div className="block" style={{ '--c': 'var(--orange)', left: '35%', width: '7.5%' }}>Lunch</div>
                      <div className="block" style={{ '--c': 'var(--yellow)', left: '50%', width: '20%' }}>Thesis</div>
                      <div className="block" style={{ '--c': 'var(--green)', left: '85%', width: '10%' }}>Gym</div>
                      <div className="now" style={{ left: '3.3%' }}></div>
                    </div>
                    <div className="hours" aria-hidden="true"><span>9</span><span>11</span><span>13</span><span>15</span><span>17</span><span>19</span></div>
                  </div>
                </div>

                <div className="panel" role="tabpanel" id="money" aria-labelledby="tab-money" tabIndex="0">
                  <div className="panel-text">
                    <h3>Tracks your money.</h3>
                    <p>Type what you spent in plain words and Blink sorts it. Apple Pay taps arrive on their own, and receipts in your mail are added too, never twice.</p>
                  </div>
                  <div className="panel-demo money-demo" id="money-mock">
                    <div className="money-sum">
                      <span className="label">Balance</span>
                      <div className="big-num">€<span id="balance" data-to="2480.50">2,480.50</span></div>
                      <div className="runway"><i></i>Lasts 79 days at this pace</div>
                    </div>
                    <div className="money-chart">
                      <span className="label">Last 14 days</span>
                      <div className="bars" id="bars" role="img" aria-label="Daily spending for 14 days against a €40 daily budget; four days went over."></div>
                    </div>
                  </div>
                </div>

                <div className="panel" role="tabpanel" id="habits-panel" aria-labelledby="tab-habits" tabIndex="0">
                  <div className="panel-text">
                    <h3>Keeps your streaks alive.</h3>
                    <p>A nudge at the right moment, never a nag. Tick today's circle for “No phone after 11” to reach a 7-day milestone.</p>
                  </div>
                  <div className="panel-demo" id="habits"></div>
                </div>

                <div className="panel" role="tabpanel" id="content" aria-labelledby="tab-content" tabIndex="0">
                  <div className="panel-text">
                    <h3>Writes your ideas.</h3>
                    <p>Ideas and drafts for Instagram, LinkedIn and X, in your voice. A weekly plan, and stats on what worked.</p>
                  </div>
                  <div className="panel-demo" id="content-mock">
                    <div className="mini-notch" style={{ '--c': 'var(--green)' }}><img loading="lazy" src="/assets/eyes-done.png" alt="" width="52" height="26" />5 ideas ready</div>
                    <div className="ideas">
                      <div className="idea" style={{ '--c': 'var(--pink)' }}><span className="fmt"><i></i>Reel</span><span className="ttl">3 tools I use every day</span><span className="plat">Instagram</span></div>
                      <div className="idea" style={{ '--c': 'var(--mint)' }}><span className="fmt"><i></i>Carousel</span><span className="ttl">Building an app in a week</span><span className="plat">LinkedIn</span></div>
                      <div className="idea" style={{ '--c': 'var(--orange)' }}><span className="fmt"><i></i>Post</span><span className="ttl">Student budget, honestly</span><span className="plat">X</span></div>
                    </div>
                  </div>
                </div>

                <div className="panel" role="tabpanel" id="moods" aria-labelledby="tab-moods" tabIndex="0">
                  <div className="panel-text">
                    <h3>One glance tells you.</h3>
                    <p>Blink's eyes change colour with what's going on. Orange for your evening check-in, yellow when a streak hits a milestone. Try the others.</p>
                  </div>
                  <div className="panel-demo peek-stage">
                    <div className="peek" id="peek" aria-live="polite">
                      <div className="eyes-slot"><div className="eyes-look"><img id="peek-eyes" src="/assets/eyes-idle.png" alt="" width="320" height="160" /></div></div>
                      <span className="peek-text" id="peek-text">All clear</span>
                    </div>
                    <div className="moods" role="group" aria-label="Blink's moods">
                      <button className="mood" type="button" style={{ '--c': 'var(--rest)' }} data-mood="idle" data-text="All clear" aria-pressed="true"><i></i>At rest</button>
                      <button className="mood" type="button" style={{ '--c': 'var(--red)' }} data-mood="important" data-text="Prof. Weber: thesis meeting moved" aria-pressed="false"><i></i>Needs you</button>
                      <button className="mood" type="button" style={{ '--c': 'var(--mint)' }} data-mood="headsup" data-text="Thesis review in 10 min" aria-pressed="false"><i></i>Time</button>
                      <button className="mood" type="button" style={{ '--c': 'var(--green)' }} data-mood="done" data-text="Reminder set for Friday" aria-pressed="false"><i></i>Done</button>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* Privacy (dark) */}
        <section id="privacy" className="band dark" aria-labelledby="privacy-title">
          <div className="wrap">
            <div className="head">
              <h2 id="privacy-title">Your server. Your keys.</h2>
              <p className="sub">Everything lives on a server in your own account. Pexilim never sees it.</p>
            </div>

            {/* Where your data goes, drawn: Mac ↔ your server (with your keys) ↔ your AI and mail. */}
            <div className="vault" id="diagram" role="img" aria-label="Your Mac talks only to your own server, which holds your keys. Your server calls the AI provider you picked, with your key, and reads your mail. Pexilim is not part of it and stores nothing.">
              <div className="yours"><span>Yours</span></div>
              <div className="v-node">
                <div className="mini-mac"><div className="mm-screen"><i></i></div><div className="mm-base"></div></div>
                <b>Your Mac</b><span>Clipboard and chats stay here</span>
              </div>
              <div className="wire"><i></i><i></i></div>
              <div className="v-node">
                <div className="rack">
                  <div className="unit"><i></i></div><div className="unit"><i></i></div><div className="unit"><i></i></div>
                  <span className="key"><svg><use href="#i-key" /></svg></span>
                </div>
                <b>Your server</b><span>Free Supabase, in your account</span>
              </div>
              <div className="wire"><i></i><i></i></div>
              <div className="v-node">
                <div className="providers">
                  <span>Claude</span><span>Groq</span><span>OpenRouter</span>
                  <span className="mail"><svg><use href="#i-mail" /></svg>Your mail</span>
                </div>
                <b>Your AI</b><span>Called with your key</span>
              </div>
            </div>
            <p className="pex"><span className="pex-chip">Pexilim</span>Not in the picture. Only a sign-in helper for setup, storing nothing.</p>

            <ul className="facts">
              <li><svg aria-hidden="true"><use href="#i-mac" /></svg>Clipboard never leaves your Mac</li>
              <li><svg aria-hidden="true"><use href="#i-lock" /></svg>Keys kept as secrets</li>
              <li><svg aria-hidden="true"><use href="#i-off" /></svg>No cookies, no ads, no tracking in the app</li>
            </ul>
          </div>
        </section>

        {/* Setup (light) */}
        <section id="setup" className="light" aria-labelledby="setup-title">
          <div className="wrap">
            <div className="head">
              <h2 id="setup-title">Set up in three minutes.</h2>
              <p className="sub">No code, no terminal.</p>
            </div>
            <div className="flow" id="flow">
              <span className="rail" aria-hidden="true"><i></i></span>
              <ol className="steps">
                <li className="step">
                  <div className="step-art art-dmg" aria-hidden="true">
                    <div className="dmg">
                      <span className="app"><img loading="lazy" src="/assets/apple-touch-icon.png" alt="" width="180" height="180" />Blink</span>
                      <svg className="drag" viewBox="0 0 48 16"><path d="M2 8h40M36 2l6 6-6 6" /></svg>
                      <span className="app"><span className="folder"></span>Applications</span>
                    </div>
                  </div>
                  <b>Download and open Blink.</b>
                  <span>When Blink is ready, we email you the link. The first time, macOS asks you to confirm in System Settings.</span>
                </li>
                <li className="step">
                  <div className="step-art art-server" aria-hidden="true">
                    <span className="sb-btn">Sign in with Supabase</span>
                    <ul className="progress">
                      <li className="ok">Creating your server</li>
                      <li className="ok">Setting up your data</li>
                      <li className="ok">Installing Blink's brain</li>
                      <li className="wait">Locking it to you</li>
                    </ul>
                  </div>
                  <b>Sign in with Supabase.</b>
                  <span>Blink creates your free server and installs everything on it. Already have one? Paste its address instead.</span>
                </li>
                <li className="step">
                  <div className="step-art art-notch" aria-hidden="true">
                    <div className="mini-notch" style={{ '--c': 'var(--mint)' }}><img loading="lazy" src="/assets/eyes-headsup.png" alt="" width="52" height="26" />Thesis review in 10 min</div>
                    <div className="perm"><span>Groq key</span><span className="dots">••••••••</span></div>
                    <div className="perm"><span>Calendar</span><span className="on">Allowed</span></div>
                  </div>
                  <b>Add a free key and your calendar.</b>
                  <span>Paste a free Groq key and allow Calendar. Your next meeting shows up in the notch.</span>
                </li>
              </ol>
            </div>
          </div>
        </section>

        {/* FAQ (mist) */}
        <section id="faq" className="mist" aria-labelledby="faq-title">
          <div className="wrap faq-grid">
            <div className="head"><h2 id="faq-title">Questions.</h2><p className="sub">Something missing? Write to <a href="mailto:hello@blinkk.app">hello@blinkk.app</a>.</p></div>
            <div className="faq">
              <details><summary>When can I get it?</summary><p>Blink isn't public yet. <a href="#waitlist">Join the waitlist</a> and we'll email you when it's ready to download.</p></details>
              <details><summary>Is it free?</summary><p>Yes. Blink is free to download and use. You only pay for services you choose to add, like a Claude key.</p></details>
              <details><summary>Do I need to code?</summary><p>No. Setup is a few clicks: sign in with Supabase and Blink creates and sets up your server for you. If you already run a Supabase server, you can paste its address instead.</p></details>
              <details><summary>What does it cost to run?</summary><p><strong>Nothing, if you want.</strong> Free models on Groq handle everyday work, and Supabase's free tier holds your data. Claude is optional, with your own Anthropic key; paid models stop for the day when they reach your daily limit ($5 unless you change it). If you outgrow Supabase's free tier, their paid plan is billed to you by Supabase.</p></details>
              <details><summary>Which Macs does it run on?</summary><p>MacBooks with a notch, running macOS 26 or later.</p></details>
              <details><summary>Is my data safe?</summary><p>Your data lives on your own server, in your own Supabase account, and AI requests use your own keys. Pexilim runs no database for the app and can't read your data. Your clipboard never leaves your Mac. Blink never sends, posts or spends without your OK, and the important actions need Touch ID. See the <a href="/privacy">privacy policy</a> for the details.</p></details>
              <details><summary>Does Blink use my Google account?</summary><p>Only if you connect it, and only for <code>/meet</code>: you type <code>/meet</code> in the notch, pick a time and people, approve with Touch ID, and Blink creates that meeting in your Google Calendar with a Google Meet link, so Google emails the invites. Blink asks Google for access to your calendar events and which account is connected, and uses it only to create the meetings you approve. It doesn't read your other events, mail or files, never sells or shares Google data, and never uses it for ads or to train AI. Details are in the <a href="/privacy#google">privacy policy</a>.</p></details>
              <details><summary>Is there an iPhone app?</summary><p>Later. An iPhone app with the Dynamic Island is planned; Blink is Mac first.</p></details>
            </div>
          </div>
        </section>

        {/* Waitlist (dark) */}
        <section id="waitlist" className="band dark end" aria-labelledby="waitlist-title">
          <div className="wrap">
            <div className="end-eyes eyes-look" aria-hidden="true"><img src="/assets/eyes-idle.png" alt="" width="320" height="160" /></div>
            <h2 id="waitlist-title">Be first to meet Blink.</h2>
            <p className="sub">Blink isn't out yet. Leave your email and we'll write when it's ready to download. Free for Mac.</p>

            <form className="waitlist" id="waitlist-form" noValidate>
              <div className="wl-row">
                <label className="wl-label" htmlFor="wl-email">Email</label>
                <input className="wl-input" id="wl-email" name="email" type="email" inputMode="email" autoComplete="email" required maxLength="254" placeholder="you@example.com" aria-describedby="wl-status" />
              </div>
              <div className="hp" aria-hidden="true">
                <label htmlFor="wl-website">Website</label>
                <input id="wl-website" name="website" type="text" tabIndex="-1" autoComplete="off" />
              </div>
              <div className="wl-consent">
                <input id="wl-consent" name="consent" type="checkbox" required aria-describedby="wl-status" />
                <label htmlFor="wl-consent">Email me when Blink is ready. I can unsubscribe anytime.</label>
              </div>
              <p className="wl-fine">We keep your email, when you joined and that you agreed. Nothing else. <a href="/privacy#waitlist">How we handle it</a>.</p>
              <button className="btn wl-submit" type="submit" id="wl-submit">Join the waitlist</button>
              <p className="wl-status" id="wl-status" role="status" aria-live="polite"></p>
              <noscript><p className="wl-status">This form needs JavaScript. To join, email <a href="mailto:hello@blinkk.app">hello@blinkk.app</a>.</p></noscript>
            </form>
          </div>
        </section>
      </main>

      <SiteFooter />

      <PageScripts srcs={["/js/config.js", "/js/vendor/gsap.min.js", "/js/vendor/ScrollTrigger.min.js", "/js/main.js", "module:/js/waitlist.js"]} />
    </>
  );
}
