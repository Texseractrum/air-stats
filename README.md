# Air Stats

<img src="docs/icon.png" alt="Air Stats — heart and pulse on green" width="112">

A native, lightweight macOS menu-bar companion for Fitbit Air and other Google/Fitbit trackers. Inspired by the compact widgets in [Stats](https://mac-stats.com/); implemented independently in SwiftUI, AppKit, and Swift Charts. macOS 14 or later. No web server, Electron, or third-party dependencies. The only request Air Stats makes besides your own Google account is a daily update check, which also counts the install; see [Install counting](#install-counting).

## Install

[Download Air Stats for Mac](https://health.sparkles.dev) — opening this URL starts the latest `.dmg` download directly, with no landing page. The same universal app supports Apple silicon and Intel Macs.

Open the disk image, drag **Air Stats** to **Applications**, then open it. The app lives in the menu bar. macOS requires you to open and install downloaded apps; a website cannot silently install them.

The initial release is **Developer ID signed but not yet notarized**. macOS Gatekeeper may block its first launch. Review the source and release checksum before choosing **System Settings → Privacy & Security → Open Anyway**, or build locally below. Do not disable Gatekeeper globally. Notarized releases will be explicitly identified in their release notes.

Air Stats ships with a default Google **Desktop app** OAuth client, so you can connect Fitbit without any setup — just click **Connect with Google**. (A Desktop client's secret is not treated as confidential by Google, so it is safe to bundle.) If you would rather use your own Google Cloud project, import its Desktop-app OAuth JSON from Settings to override the default — see [Google Cloud setup](#google-cloud-setup). Air Stats is an independent project, not affiliated with Google or Fitbit.

## Run

```sh
bash scripts/build.sh
bash scripts/run.sh
```

This creates `dist/Air Stats.app`. Open the app, click its menu-bar item, then **Connect with Google**, sign in with the account linked to Fitbit, and allow the four read-only permissions. The default OAuth client is used automatically; to use your own instead, import its Desktop-app JSON from Settings.

You can also import an existing credential file without putting its contents in source code:

```sh
bash scripts/run.sh --credentials /absolute/path/to/client_secret.json --connect
```

The app bundles a default Desktop OAuth client inside `Air Stats.app`; its refresh token is stored in macOS Keychain after you connect. If you import your own OAuth JSON, that configuration and its token are stored in Keychain and take precedence over the bundled default; the imported JSON stays local to this Mac. Health readings live only in memory and are cleared when you disconnect or quit.

### Ask Claude Code or Codex about your health

After connecting Google, open **Settings → Claude Code and Codex → Set up agent access**. Air Stats detects locally installed copies of Claude Code and Codex, registers a read-only MCP server, and installs an `airstats-health` skill for automatic discovery. Start a new agent session, then ask questions such as “How has my sleep changed this week?” or “Summarize my recovery signals.”

Readings are fetched from Google only when an agent calls the Air Stats tool. OAuth credentials remain in Keychain and are never added to agent configuration. The readings used to answer your question are sent to that agent's configured model provider, so setup requires an explicit confirmation and can be removed from Settings at any time. The integration preserves measurement timestamps and source errors; it does not turn wearable readings into a diagnosis.

For scripted setup or removal from an app bundle:

```sh
"/Applications/Air Stats.app/Contents/MacOS/AirStats" --install-agent-integration
"/Applications/Air Stats.app/Contents/MacOS/AirStats" --remove-agent-integration
```

To keep the app after removing this workspace, copy `dist/Air Stats.app` to your Applications folder. Enable **Launch at login** in the app's Settings if desired. Right-click its menu-bar item to refresh or quit. Hold Command while dragging the menu-bar item to choose its position; Air Stats remembers that placement. macOS owns the status-item region on the right side of the menu bar, so apps cannot force an item across the camera cutout into the application-menu region.

## What you can see

| Metric | Behavior |
| --- | --- |
| Heart rate | Latest synced measurement, its age, recorded min/max, and an interactive five-minute-average trend from the last 24 hours |
| Sleep | Main sleep duration, interactive sleep stages, seven-night history, and duration-based sleep efficiency |
| Resting heart rate and HRV | Latest daily reading, date, and an interactive seven-day trend |
| Blood oxygen and breathing rate | Latest available overnight reading, date, and an interactive trend |
| Skin temperature | Difference from the baseline supplied by Google, in °C |
| Steps | Reconciled wearable steps since midnight in the Mac's local time zone |
| Device | Tracker name, battery percentage, and last phone-sync time |

Menu-bar readings are configurable. A trailing dot marks heart rate older than 15 minutes, or sleep/HRV from a previous date. Refresh can run every 1, 5, or 15 minutes; after rate limiting the app waits at least 15 minutes. It also refreshes after waking from sleep. Missing or denied data appears as `—`; preview data is opt-in and clearly labeled.

Heart rate and daily vitals use labeled line charts with time/date and numeric axes. Heart-rate lines join only adjacent five-minute buckets; daily lines join only consecutive calendar days. Missing readings leave gaps, and isolated measurements appear as short bars. The heart chart spans the available readings from the last 24 hours; its range summary uses the original readings, not the averaged line. Minimum vertical spans prevent small changes from looking dramatic. Sleep bars show hours and a recorded-night average; skin temperature includes its zero-baseline reference.

Move the pointer across a chart to inspect its time/date and value (five-minute averages for heart rate). Missing intervals are identified rather than borrowing a distant reading. When a chart has keyboard focus, use the Left and Right Arrow keys to inspect recorded points without a mouse. Overview is a fixed, non-scrollable layout; longer Sleep, Vitals, and Settings pages remain scrollable without scrollbar gutters. Connection errors stay reachable through a compact Settings action on Overview.

Air Stats checks the repository's latest public GitHub release once a day by default. When a newer stable version is available, macOS shows an update dialog with options to download it, be reminded later, or skip that version. Automatic checks can be disabled and manual checks are available in Settings and the menu-bar context menu. The updater only reads public release metadata; downloads continue through `health.sparkles.dev` and installation remains under the user's control.

### Fitbit scores and live heart rate

Google's published Health API v4 schema does **not** expose Fitbit's proprietary **Sleep Score** or **Daily Readiness Score**. Air Stats explicitly shows their unavailability. It does not invent a readiness score or relabel sleep efficiency as Sleep Score. Efficiency here is the rounded ratio of finalized minutes asleep to the sleep interval's duration.

Cloud heart rate is available only after the tracker syncs to the phone and Google. Automatic refresh cannot turn it into a live Bluetooth stream. Every heart-rate value retains its measurement timestamp, and gaps in data are not connected by an invented line.

Sleep stages, HRV, SpO₂, and other metrics depend on your hardware, permissions, and actual recorded data. The app queries the reconciled `google-wearables` stream, which can include Fitbit and Pixel devices on the same account. It doesn't promise Air-only filtering when several devices are linked.

## Google Cloud setup

The provided credentials must belong to a project with:

1. **Google Health API** (`health.googleapis.com`) enabled.
2. A Google OAuth client of type **Desktop app**, with a loopback redirect.
3. Your Fitbit-linked Google account in **Google Auth Platform → Audience → Test users**, if the app is in testing.
4. These read-only scopes configured under **Data Access**:

```text
https://www.googleapis.com/auth/googlehealth.sleep.readonly
https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly
https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly
https://www.googleapis.com/auth/googlehealth.settings.readonly
```

Google consent must be completed by the account owner. Desktop sign-in uses the system browser, an ephemeral listener bound only to `127.0.0.1`, random OAuth state, and PKCE S256. The token exchange includes the installed-client secret. Sign-in can be canceled and times out after four minutes; tokens refresh on demand. Network responses use an ephemeral session without disk caching.

If authorization is declined, reconnect. If only some permissions were granted, the permitted metrics continue to work and Settings identifies the denied sources. For `403` responses, check the API, test-user list, and scopes. Google OAuth refresh tokens for apps in **Testing** generally expire after seven days and require reconnecting. Disconnect removes the local token and readings; Google's grant can also be revoked through **Manage Google permissions** in Settings.

## Development and verification

The dashboard uses native segmented navigation, grouped settings, aligned metric cards, and SwiftUI number/ring transitions. Builds made with Xcode 26 or later use native Liquid Glass controls and popover material on macOS 26; macOS 14–15 retain standard material and bordered controls. System Reduce Motion, Reduce Transparency, and Increase Contrast settings are respected.

```sh
swift test
swift build
bash scripts/build.sh
```

Tests cover real API JSON representations (including string-encoded int64 values), missing values versus zero, sleep summaries and overlapping awakenings, daily dates, DST boundaries, pagination including empty pages, permission failures, rate limiting, temperature baseline handling, PKCE, callback state validation, and token-form encoding. HTTP tests use an injected URLSession protocol and do not read a real account.

Render the actual native interface with sample data, without screen-recording access:

```sh
.build/debug/AirStats --snapshot .context/overview-dark.png
.build/debug/AirStats --snapshot .context/overview-light.png --appearance light
.build/debug/AirStats --snapshot .context/sleep.png --tab sleep
.build/debug/AirStats --snapshot .context/vitals.png --tab vitals
.build/debug/AirStats --snapshot .context/welcome.png --welcome
.build/debug/AirStats --ui-smoke
```

`--demo` launches an interactive sample dashboard. Demo, snapshot, and UI-smoke modes use an isolated store without reading the real Keychain or calling Google automatically. The smoke check exercises native controls and Escape navigation through the app's own accessibility tree; it does not require Accessibility permission.

On macOS 14.4 or later, add `--composited` to capture rendered materials accurately, or `--popover` to capture the actual menu-bar popover. These options capture only this process's sample window using ScreenCaptureKit, without Screen Recording permission or desktop capture. Plain snapshots remain available on macOS 14.0. Use `--state empty|stale|loading|error|sparse|single`, `--tab settings`, `--reduce-motion`, `--reduce-transparency`, `--high-contrast`, or `--legacy-glass` for visual checks; preview flags never change system accessibility preferences. To compile-test the pre-Liquid Glass path with a newer SDK, run `swift build --scratch-path .context/legacy-build -Xswiftc -DAIRSTATS_LEGACY_GLASS`.

Set `AIRSTATS_BUILD_PATH` and `AIRSTATS_OUTPUT_DIR` when building an isolated preview so another build or running app is not replaced.

After completing Google consent, verify the real integration without printing tokens or measurement values:

```sh
"dist/Air Stats.app/Contents/MacOS/AirStats" --check-connection
```

The check prints source availability, record counts, and actionable API errors. Exit status is `0` for a successful fetch of all sources, `1` for an API error, or `2` if account consent is still needed. An empty data source can be valid for a device without that capability.

The default build script produces an ad-hoc signed app for local use. `AIRSTATS_UNIVERSAL=1 bash scripts/build.sh` builds both architectures. The repository intentionally contains no OAuth secrets, tokens, or account health data.

## Releasing

On a Mac with a Developer ID Application certificate and a notarization profile stored using `xcrun notarytool store-credentials`:

```sh
export AIRSTATS_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export AIRSTATS_NOTARY_PROFILE='your-keychain-profile'
bash scripts/package.sh
```

This builds both architectures, signs with hardened runtime and a secure timestamp, notarizes and staples the app, creates a drag-to-Applications DMG, then signs, notarizes, and staples the DMG. Outputs are `dist/AirStats.dmg` and `dist/AirStats.dmg.sha256`. Upload both to a GitHub release; retain the `AirStats.dmg` asset name so the download URL continues to work.

Before packaging, increment both `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`. Publish the GitHub release with a matching stable tag such as `v1.1.0`. Once that release is public, installed copies on an older version will discover it automatically; drafts and releases marked as prereleases are not returned by GitHub's latest-release endpoint.

For an explicitly unnotarized preview only, omit `AIRSTATS_NOTARY_PROFILE` and set `AIRSTATS_ALLOW_UNNOTARIZED=1`. Packaging otherwise fails closed when notarization is not configured. Preview builds must be labeled as unnotarized.

`deploy/worker.mjs` is the complete download and release service. It redirects the root and explicit download paths to the latest public GitHub release, and answers `/latest` with that release's tag and notes so installed copies can check for updates. It has no storage, user accounts, or landing page; it counts requests as described in [Install counting](#install-counting). Test it with `node --test deploy/worker.test.mjs`; deploy with `wrangler deploy --config deploy/wrangler.jsonc` from an authorized Cloudflare account. Never put deployment credentials in the repository.

## Install counting

The project has no way to see how many people use Air Stats other than counting, so the once-a-day update check doubles as the count. Instead of asking GitHub directly, the app asks `health.sparkles.dev/latest`, which forwards the same public release and records four things: whether this is a first launch, a daily check, or a manual one; the app version; the macOS major and minor version; and the country Cloudflare already sees. Downloads from the redirect are counted the same way.

Nothing else is sent. There is no account, no installation identifier, no Google or Fitbit data, and no health reading of any kind — the app never attaches one to this request. Addresses are not stored: to avoid counting one Mac twice in a day, the service derives a truncated digest of the caller and a daily-rotating secret, which cannot be linked back to an address or followed from one day to the next. Set that secret before deploying, or the service records no per-caller key at all and reports raw request counts:

```sh
wrangler secret put ANALYTICS_SALT --config deploy/wrangler.jsonc
```

Turn it off in **Settings → Updates → Count this install anonymously**. The app then asks GitHub's release API directly, exactly as it did before, and no request reaches the project. Turning off **Automatically check for updates** stops both.

Query the counts with the [Analytics Engine SQL API](https://developers.cloudflare.com/analytics/analytics-engine/sql-api/), where `blob1` is the kind, `blob2` the app version, `blob3` the macOS version, and `blob4` the country:

```sql
SELECT toDate(timestamp) AS day,
       SUM(_sample_interval) AS checks,
       COUNT(DISTINCT index1) AS installs
FROM air_stats_usage
WHERE blob1 IN ('daily', 'install') AND timestamp > NOW() - INTERVAL '30' DAY
GROUP BY day ORDER BY day
```

## Contributing and license

Issues and pull requests are welcome. Run `swift test`, `node --test deploy/worker.test.mjs`, and a universal build before submitting a change. Use preview mode for screenshots and test fixtures; never include personal health readings, OAuth files, access tokens, or signing keys in an issue or pull request.

[MIT](LICENSE). The icon is drawn from original vector paths in `scripts/icon.swift`.

## API references

Implementation checked against Google's published v4 discovery schema and documentation on 2026-09-13:

- [Google Health data types and device support](https://developers.google.com/health/data-types)
- [Sleep sessions, summaries, and sleep efficiency](https://developers.google.com/health/data-types/sleep)
- [Vitals and health metrics](https://developers.google.com/health/data-types/vitals)
- [Reconciled data points](https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints/reconcile)
- [List filters and pagination](https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints/list)
- [Google Cloud and OAuth setup](https://developers.google.com/health/setup)
- [Native-app OAuth](https://developers.google.com/identity/protocols/oauth2/native-app)

## Layout

`Sources/HealthCore` contains the API client, data parsing, query filters, and OAuth primitives. `Sources/AirStats` contains the native app, sign-in listener, Keychain storage, and views. `Tests/HealthCoreTests` contains unit and HTTP integration tests. `scripts/build.sh` packages the executable and a locally drawn icon into an `.app` bundle.
