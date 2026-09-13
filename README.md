# Air Stats

<img src="docs/icon.png" alt="Air Stats — heart and pulse on green" width="112">

A native, lightweight macOS menu-bar companion for Fitbit Air and other Google/Fitbit trackers. Inspired by the compact widgets in [Stats](https://mac-stats.com/); implemented independently in SwiftUI, AppKit, and Swift Charts. macOS 14 or later. No web server, Electron, telemetry, or third-party dependencies.

## Install

[Download Air Stats for Mac](https://health.sparkles.dev) — opening this URL starts the latest `.dmg` download directly, with no landing page. The same universal app supports Apple silicon and Intel Macs.

Open the disk image, drag **Air Stats** to **Applications**, then open it. The app lives in the menu bar. macOS requires you to open and install downloaded apps; a website cannot silently install them.

The initial release is **Developer ID signed but not yet notarized**. macOS Gatekeeper may block its first launch. Review the source and release checksum before choosing **System Settings → Privacy & Security → Open Anyway**, or build locally below. Do not disable Gatekeeper globally. Notarized releases will be explicitly identified in their release notes.

You need your own Google **Desktop app** OAuth configuration to connect Fitbit. See [Google Cloud setup](#google-cloud-setup). No developer credentials are included in the download. Air Stats is an independent project, not affiliated with Google or Fitbit.

## Run

```sh
bash scripts/build.sh
bash scripts/run.sh
```

This creates `dist/Air Stats.app`. Open the app, click its menu-bar item, then **Connect with Google**. Import your Google **Desktop app** OAuth client JSON when prompted. Sign in with the account linked to Fitbit and allow the four read-only permissions.

You can also import an existing credential file without putting its contents in source code:

```sh
bash scripts/run.sh --credentials /absolute/path/to/client_secret.json --connect
```

The app stores the imported configuration and refresh token in macOS Keychain. The JSON is not copied into the app bundle. Importing a configuration is local to this Mac; a distributable build does not contain your credentials. Health readings live only in memory and are cleared when you disconnect or quit.

To keep the app after removing this workspace, copy `dist/Air Stats.app` to your Applications folder. Enable **Launch at login** in the app's Settings if desired. Right-click its menu-bar item to refresh or quit.

## What you can see

| Metric | Behavior |
| --- | --- |
| Heart rate | Latest synced measurement, its age, and a 24-hour chart of five-minute averages |
| Sleep | Main sleep duration, sleep stages, seven-night history, and duration-based sleep efficiency |
| Resting heart rate and HRV | Latest daily reading, date, and seven-day trend |
| Blood oxygen and breathing rate | Latest available overnight reading and date |
| Skin temperature | Difference from the baseline supplied by Google, in °C |
| Steps | Reconciled wearable steps since midnight in the Mac's local time zone |
| Device | Tracker name, battery percentage, and last phone-sync time |

Menu-bar readings are configurable. A trailing dot marks heart rate older than 15 minutes, or sleep/HRV from a previous date. Refresh can run every 1, 5, or 15 minutes; after rate limiting the app waits at least 15 minutes. It also refreshes after waking from sleep. Missing or denied data appears as `—`; preview data is opt-in and clearly labeled.

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
```

`--demo` launches an interactive sample dashboard. Snapshot mode never reads the real Keychain or calls Google. No health data is written to screenshots unless you explicitly add a capture feature for a connected session.

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

For an explicitly unnotarized preview only, omit `AIRSTATS_NOTARY_PROFILE` and set `AIRSTATS_ALLOW_UNNOTARIZED=1`. Packaging otherwise fails closed when notarization is not configured. Preview builds must be labeled as unnotarized.

`deploy/worker.mjs` is the complete direct-download service. It redirects only the root and explicit download paths to the latest public GitHub release. It has no analytics, storage, user accounts, or landing page. Test it with `node --test deploy/worker.test.mjs`; deploy with `wrangler deploy --config deploy/wrangler.jsonc` from an authorized Cloudflare account. Never put deployment credentials in the repository.

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
