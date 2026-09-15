/// The landing page for health.aidaniil.com. One self-contained document: no external
/// stylesheet, script, font, or image, so the page needs no asset hosting and nothing
/// about a visitor leaves Cloudflare. `version` is the latest public release tag, or
/// null when GitHub could not be reached; the page then simply omits the version line.

const escapeHTML = (value) =>
  String(value).replace(/[&<>"']/g, (character) => `&#${character.charCodeAt(0)};`);

const features = [
  ['Heart rate', 'The last 24 hours as a labelled chart, with the newest reading in the menu bar. A trailing dot marks a reading that has gone stale.'],
  ['Sleep', 'Stages, time asleep, and a duration-based efficiency ratio for every recorded night of the past week.'],
  ['Vitals', 'Resting heart rate, HRV, blood oxygen, breathing rate, and skin-temperature deviation, each on its own daily line.'],
  ['Steps', "Today's total from the same reconciled stream, next to everything else instead of behind a phone app."],
  ['Private by design', 'Your readings stay on your Mac. Sign-in lives in the Keychain, and Air Stats talks to Google directly — there is no server in between.'],
  ['Ask your agent', 'An optional MCP skill lets Claude Code or Codex answer questions about your own readings, locally.'],
];

const icon = `<svg class="icon" viewBox="0 0 100 100" aria-hidden="true" focusable="false">
  <defs>
    <linearGradient id="tile" x1="0" y1="1" x2="0" y2="0">
      <stop offset="0" stop-color="#0e5e54"/><stop offset="1" stop-color="#29b391"/>
    </linearGradient>
  </defs>
  <rect x="7" y="7" width="86" height="86" rx="19" fill="url(#tile)"/>
  <g transform="translate(0,100) scale(1,-1)">
    <path fill="#f2fcf7" d="M50 26.5C43.5 32.2 22.5 47 22.5 61c0 17.5 19 21 27.5 7 8.5 14 27.5 10.5 27.5-7 0-14-21-28.8-27.5-34.5Z"/>
    <path fill="none" stroke="#0e5e54" stroke-width="4.6" stroke-linecap="round" stroke-linejoin="round"
          d="M30.5 54h10l5 7.5 6-19 5.5 11.5h12.5"/>
  </g>
</svg>`;

export function landingHTML(version) {
  const tag = version && /^v?\d[\w.-]{0,20}$/.test(version) ? escapeHTML(version) : null;
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Air Stats — your Fitbit in the Mac menu bar</title>
<meta name="description" content="A free, native macOS menu-bar app for Fitbit and Google trackers. Heart rate, sleep, vitals, and steps at a glance. Open source, no server, macOS 14 or later.">
<meta name="color-scheme" content="dark light">
<link rel="canonical" href="https://health.aidaniil.com/">
<meta property="og:title" content="Air Stats — your Fitbit in the Mac menu bar">
<meta property="og:description" content="Heart rate, sleep, vitals, and steps in your menu bar. Free, native, and open source.">
<meta property="og:url" content="https://health.aidaniil.com/">
<meta property="og:type" content="website">
<style>
  *, *::before, *::after { box-sizing: border-box; }
  :root {
    --bg: #071310; --panel: #0d1f1b; --line: #1d3a33; --ink: #e8f6ef;
    --muted: #9dbbb1; --accent: #46d3ab; --accent-ink: #052019;
  }
  @media (prefers-color-scheme: light) {
    :root {
      --bg: #f4f9f7; --panel: #ffffff; --line: #d9e8e2; --ink: #0b241e;
      --muted: #4f6f66; --accent: #0f7a63; --accent-ink: #ffffff;
    }
  }
  html { -webkit-text-size-adjust: 100%; }
  body {
    margin: 0; background: var(--bg); color: var(--ink);
    font: 16px/1.6 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", system-ui, sans-serif;
    -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility;
  }
  .wrap { width: min(100% - 40px, 900px); margin-inline: auto; }
  a { color: inherit; }
  a:focus-visible, .button:focus-visible { outline: 2px solid var(--accent); outline-offset: 3px; border-radius: 8px; }
  .icon { width: 100%; height: 100%; display: block; }

  header { position: relative; z-index: 1; padding: 22px 0; }
  .bar { display: flex; align-items: center; justify-content: space-between; gap: 16px; }
  .brand { display: flex; align-items: center; gap: 10px; font-weight: 600; letter-spacing: -0.01em; }
  .brand span:first-child { width: 28px; height: 28px; }
  .bar nav { display: flex; gap: 18px; font-size: 14px; color: var(--muted); }
  .bar nav a { text-decoration: none; }
  .bar nav a:hover { color: var(--ink); }

  .hero { position: relative; text-align: center; padding: 56px 0 64px; overflow: hidden; }
  .hero::before {
    content: ""; position: absolute; inset: -160px 0 auto; height: 520px; pointer-events: none;
    background:
      radial-gradient(46% 42% at 50% 0, color-mix(in oklab, var(--accent) 34%, transparent), transparent 72%),
      radial-gradient(32% 34% at 15% 8%, color-mix(in oklab, var(--accent) 16%, transparent), transparent 70%),
      radial-gradient(32% 34% at 85% 8%, color-mix(in oklab, var(--accent) 12%, transparent), transparent 70%);
  }
  .hero::after {
    content: ""; position: absolute; inset: 0; pointer-events: none;
    background-image:
      linear-gradient(90deg, color-mix(in oklab, var(--ink) 7%, transparent) 1px, transparent 0),
      linear-gradient(color-mix(in oklab, var(--ink) 7%, transparent) 1px, transparent 0);
    background-size: 48px 48px;
    -webkit-mask-image: radial-gradient(68% 60% at 50% 0, #000 10%, transparent 72%);
    mask-image: radial-gradient(68% 60% at 50% 0, #000 10%, transparent 72%);
  }
  .hero > .wrap { position: relative; z-index: 1; }
  .badge {
    display: inline-flex; align-items: center; gap: 8px; margin: 0 0 22px;
    padding: 6px 14px; border: 1px solid var(--line); border-radius: 999px;
    background: color-mix(in oklab, var(--panel) 70%, transparent);
    font-size: 13px; color: var(--muted);
  }
  .badge b { color: var(--accent); font-weight: 600; }
  h1 {
    margin: 0 0 16px; font-size: clamp(34px, 6.4vw, 56px); line-height: 1.06;
    letter-spacing: -0.03em; font-weight: 700; text-wrap: balance;
  }
  .lede { margin: 0 auto 30px; max-width: 30em; font-size: clamp(16px, 2.2vw, 18px); color: var(--muted); text-wrap: pretty; }
  .actions { display: flex; flex-wrap: wrap; gap: 12px; justify-content: center; }
  .button {
    display: inline-flex; align-items: center; gap: 8px; padding: 13px 24px; border-radius: 12px;
    border: 1px solid transparent; font-size: 15px; font-weight: 600; text-decoration: none;
    background: var(--accent); color: var(--accent-ink); transition: transform .15s ease, filter .15s ease;
  }
  .button:hover { filter: brightness(1.06); transform: translateY(-1px); }
  .button.ghost { background: transparent; color: var(--ink); border-color: var(--line); }
  .button.ghost:hover { border-color: var(--accent); }
  .meta { margin: 18px 0 0; font-size: 13px; color: var(--muted); }

  .menubar {
    margin: 44px auto 0; max-width: 560px; padding: 10px 18px; border-radius: 12px;
    border: 1px solid var(--line); background: color-mix(in oklab, var(--panel) 88%, transparent);
    display: flex; gap: 26px; justify-content: center; flex-wrap: wrap;
    font: 500 15px/1.4 ui-monospace, "SF Mono", Menlo, monospace; font-variant-numeric: tabular-nums;
  }
  .menubar span { white-space: nowrap; }
  .menubar-label { margin: 12px 0 0; font-size: 13px; color: var(--muted); }

  section { padding: 56px 0; border-top: 1px solid var(--line); }
  h2 { margin: 0 0 8px; font-size: clamp(22px, 3.4vw, 28px); letter-spacing: -0.02em; text-wrap: balance; }
  .sub { margin: 0 0 30px; color: var(--muted); }
  .grid { display: grid; gap: 14px; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); }
  .card {
    padding: 20px; border: 1px solid var(--line); border-radius: 14px; background: var(--panel);
    transition: border-color .15s ease, transform .15s ease;
  }
  .card:hover { border-color: color-mix(in oklab, var(--accent) 55%, var(--line)); transform: translateY(-2px); }
  .card h3 { margin: 0 0 6px; font-size: 16px; letter-spacing: -0.01em; }
  .card p { margin: 0; font-size: 14px; color: var(--muted); }

  .steps { counter-reset: step; display: grid; gap: 12px; padding: 0; margin: 0; list-style: none; }
  .steps li { position: relative; padding-left: 38px; color: var(--muted); }
  .steps li::before {
    counter-increment: step; content: counter(step); position: absolute; left: 0; top: 1px;
    width: 26px; height: 26px; border-radius: 8px; display: grid; place-items: center;
    background: color-mix(in oklab, var(--accent) 16%, transparent); color: var(--accent);
    font-size: 13px; font-weight: 600;
  }
  .steps b { color: var(--ink); font-weight: 600; }

  footer { padding: 40px 0 60px; border-top: 1px solid var(--line); color: var(--muted); font-size: 13px; }
  footer nav { display: flex; flex-wrap: wrap; gap: 18px; margin-bottom: 14px; }
  footer p { margin: 0 0 8px; max-width: 62ch; }
  @media (prefers-reduced-motion: reduce) {
    * { transition: none !important; }
    .button:hover, .card:hover { transform: none; }
  }
</style>
</head>
<body>
<header class="wrap">
  <div class="bar">
    <div class="brand"><span>${icon}</span><span>Air Stats</span></div>
    <nav>
      <a href="#features">Features</a>
      <a href="#install">Install</a>
      <a href="https://github.com/Texseractrum/air-stats">GitHub</a>
    </nav>
  </div>
</header>

<main>
  <div class="hero"><div class="wrap">
    <p class="badge"><b>Free and open source</b> · macOS 14 or later</p>
    <h1>Your Fitbit, in your Mac's menu bar</h1>
    <p class="lede">Air Stats is a native menu-bar companion for Fitbit and Google trackers. Heart rate, sleep, vitals, and steps — at a glance, without opening the phone app.</p>
    <div class="actions">
      <a class="button" href="/download">Download for Mac</a>
      <a class="button ghost" href="https://github.com/Texseractrum/air-stats">View source</a>
    </div>
    <p class="meta">${tag ? `${tag} · ` : ''}Universal — Apple silicon and Intel · No Electron, no server, no account</p>
    <div class="menubar" role="img" aria-label="Menu bar showing 64 beats per minute, 7 hours 42 minutes of sleep, 8,214 steps, and HRV of 56">
      <span>♥ 64</span><span>☾ 7h 42m</span><span>↗ 8,214</span><span>HRV 56</span>
    </div>
    <p class="menubar-label">What Air Stats looks like when it is running.</p>
  </div></div>

  <section id="features" class="wrap">
    <h2>Everything your tracker already recorded</h2>
    <p class="sub">Read straight from the Google Health API with your own account.</p>
    <div class="grid">
      ${features.map(([title, body]) => `<article class="card"><h3>${title}</h3><p>${body}</p></article>`).join('\n      ')}
    </div>
  </section>

  <section id="install" class="wrap">
    <h2>Install in a minute</h2>
    <p class="sub">No configuration, no Google Cloud project, no command line.</p>
    <ol class="steps">
      <li><b>Download the disk image</b> and drag Air Stats to Applications.</li>
      <li><b>Open it from the menu bar</b> and click Connect with Google.</li>
      <li><b>Allow read-only access</b> to the health data you want to see. That's it — readings appear as soon as your tracker syncs.</li>
    </ol>
  </section>
</main>

<footer class="wrap">
  <nav>
    <a href="/download">Download</a>
    <a href="https://github.com/Texseractrum/air-stats">GitHub</a>
    <a href="https://github.com/Texseractrum/air-stats/releases">Releases</a>
    <a href="https://github.com/Texseractrum/air-stats/blob/master/LICENSE">MIT licence</a>
  </nav>
  <p>Air Stats is an independent project and is not affiliated with Google or Fitbit. Fitbit's Sleep Score and Daily Readiness are not part of the public API, so Air Stats never invents them.</p>
  <p>Your health data never reaches this site. The only thing counted here is the download and the once-a-day update check, which you can turn off in Settings.</p>
</footer>
</body>
</html>`;
}
