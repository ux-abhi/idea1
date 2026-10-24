// © Pexilim
import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";
import PageScripts from "@/components/PageScripts";

export const metadata = {
  title: "Help shape Blink · Blink",
  description: "Five quick questions that decide what Blink builds first.",
  alternates: { canonical: "/survey" },
  robots: { index: false },
};

export default function SurveyPage() {
  return (
    <>
      <SiteHeader />

      <main id="main" className="doc light survey">
        <div className="survey-top">
          <p className="survey-title">Help shape Blink</p>
          <div className="bar" role="progressbar" aria-label="Progress" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0"><i></i></div>
        </div>
        <form id="survey" noValidate>
          <fieldset className="q" data-name="slips" data-multi="true">
            <legend tabIndex="-1">What slips through the cracks in your day? <span className="hint">Tap all that fit</span></legend>
            <div className="choices">
                <label className="choice"><input type="checkbox" name="slips" defaultValue="missed-emails" /><span><kbd>1</kbd>Missed emails</span></label>
                <label className="choice"><input type="checkbox" name="slips" defaultValue="late-meetings" /><span><kbd>2</kbd>Late for meetings</span></label>
                <label className="choice"><input type="checkbox" name="slips" defaultValue="forgotten-tasks" /><span><kbd>3</kbd>Forgotten tasks</span></label>
                <label className="choice"><input type="checkbox" name="slips" defaultValue="lost-copies" /><span><kbd>4</kbd>Lost copied stuff</span></label>
                <label className="choice"><input type="checkbox" name="slips" defaultValue="overspending" /><span><kbd>5</kbd>Overspending</span></label>
                <label className="choice"><input type="checkbox" name="slips" defaultValue="not-posting" /><span><kbd>6</kbd>Not posting enough</span></label>
            </div>
          </fieldset>
          <fieldset className="q" data-name="uses" data-multi="true">
            <legend tabIndex="-1">What do you use today to stay on top of things? <span className="hint">Tap all</span></legend>
            <div className="choices">
                <label className="choice"><input type="checkbox" name="uses" defaultValue="apple" /><span><kbd>1</kbd>Apple Reminders or Calendar</span></label>
                <label className="choice"><input type="checkbox" name="uses" defaultValue="notion" /><span><kbd>2</kbd>Notion</span></label>
                <label className="choice"><input type="checkbox" name="uses" defaultValue="todoist" /><span><kbd>3</kbd>Todoist</span></label>
                <label className="choice"><input type="checkbox" name="uses" defaultValue="ai-chat" /><span><kbd>4</kbd>ChatGPT or Claude</span></label>
                <label className="choice"><input type="checkbox" name="uses" defaultValue="sticky-notes" /><span><kbd>5</kbd>Sticky notes</span></label>
                <label className="choice"><input type="checkbox" name="uses" defaultValue="nothing" /><span><kbd>6</kbd>Nothing really</span></label>
            </div>
          </fieldset>
          <fieldset className="q" data-name="first" data-multi="false">
            <legend tabIndex="-1">Which Blink feature would you use first? <span className="hint">Pick one</span></legend>
            <div className="choices">
                <label className="choice"><input type="radio" name="first" defaultValue="ask" /><span><kbd>1</kbd>Ask from the notch</span></label>
                <label className="choice"><input type="radio" name="first" defaultValue="mail" /><span><kbd>2</kbd>Mail sorting</span></label>
                <label className="choice"><input type="radio" name="first" defaultValue="clipboard" /><span><kbd>3</kbd>Clipboard history</span></label>
                <label className="choice"><input type="radio" name="first" defaultValue="meet" /><span><kbd>4</kbd>Meetings (/meet)</span></label>
                <label className="choice"><input type="radio" name="first" defaultValue="money" /><span><kbd>5</kbd>Money alerts</span></label>
                <label className="choice"><input type="radio" name="first" defaultValue="habits" /><span><kbd>6</kbd>Habits</span></label>
                <label className="choice"><input type="radio" name="first" defaultValue="posts" /><span><kbd>7</kbd>Post drafts</span></label>
            </div>
          </fieldset>
          <fieldset className="q" data-name="pay" data-multi="false">
            <legend tabIndex="-1">What would you pay for Blink? <span className="hint">Pick one</span></legend>
            <div className="choices">
                <label className="choice"><input type="radio" name="pay" defaultValue="free-only" /><span><kbd>1</kbd>Only if it's free</span></label>
                <label className="choice"><input type="radio" name="pay" defaultValue="once-10-20" /><span><kbd>2</kbd>One time, $10–20</span></label>
                <label className="choice"><input type="radio" name="pay" defaultValue="once-20-40" /><span><kbd>3</kbd>One time, $20–40</span></label>
                <label className="choice"><input type="radio" name="pay" defaultValue="month-3-5" /><span><kbd>4</kbd>$3–5 a month</span></label>
                <label className="choice"><input type="radio" name="pay" defaultValue="month-5-10" /><span><kbd>5</kbd>$5–10 a month</span></label>
                <label className="choice"><input type="radio" name="pay" defaultValue="more" /><span><kbd>6</kbd>More, if it's great</span></label>
            </div>
          </fieldset>
          <fieldset className="q" data-name="beta" data-multi="false">
            <legend tabIndex="-1">Want to be a beta tester? <span className="hint">You'd get Blink first</span></legend>
            <div className="choices">
                <label className="choice"><input type="radio" name="beta" defaultValue="yes" /><span><kbd>1</kbd>Yes, I'm in</span></label>
                <label className="choice"><input type="radio" name="beta" defaultValue="maybe" /><span><kbd>2</kbd>Maybe later</span></label>
            </div>
          </fieldset>
          <fieldset className="q" data-name="notch" data-multi="false" id="notch-step">
            <legend tabIndex="-1">Do you have a MacBook with a notch? <span className="hint">Blink lives in it</span></legend>
            <div className="choices">
                <label className="choice"><input type="radio" name="notch" defaultValue="true" /><span><kbd>1</kbd>Yes</span></label>
                <label className="choice"><input type="radio" name="notch" defaultValue="false" /><span><kbd>2</kbd>No</span></label>
            </div>
          </fieldset>
          <fieldset className="q" data-name="note" data-multi="true">
            <legend tabIndex="-1"><label htmlFor="note">What would make Blink a must-have for you?</label> <span className="hint">Optional, one sentence is plenty</span></legend>
            <textarea id="note" name="note" rows="3" maxLength="1000" placeholder="Type here, or just press Enter"></textarea>
          </fieldset>
          <div className="survey-nav">
            <button className="btn ghost" type="button" id="survey-back">Back</button>
            <button className="btn" type="button" id="survey-next">OK</button>
            <span className="key-hint" aria-hidden="true">or press <kbd>Enter ↵</kbd></span>
          </div>
          <p id="survey-status" role="status" aria-live="polite"></p>
        </form>
        <div className="survey-done" id="survey-done" hidden tabIndex="-1">
          <span className="happy-eyes" aria-hidden="true"><img src="/assets/eyes-done.png" alt="" width="320" height="160" /></span>
          <h1>Thank you!</h1>
          <p className="lede" id="survey-done-text">This really helps. We'll email you when Blink is ready.</p>
          <p><a className="btn ghost" href="/">Back to blinkk.app</a></p>
        </div>
      </main>

      <SiteFooter />

      <PageScripts srcs={["/js/config.js", "/js/survey.js"]} />
    </>
  );
}
