export const downloadURL = 'https://github.com/Texseractrum/air-stats/releases/latest/download/AirStats.dmg?download=1';
export const latestReleaseAPI = 'https://api.github.com/repos/Texseractrum/air-stats/releases/latest';

const redirectPaths = ['/', '/download', '/AirStats.dmg'];
const checkKinds = new Set(['install', 'daily', 'manual']);
const versionPattern = /^\d{1,4}(\.\d{1,4}){0,3}$/;
const releaseCacheSeconds = 900;
const notesLimit = 4000;

const securityHeaders = {
  'Cache-Control': 'no-store',
  'Referrer-Policy': 'no-referrer',
  'X-Content-Type-Options': 'nosniff',
  'X-Robots-Tag': 'noindex',
};

const labelled = (value, allowed) => (allowed(value) ? value : 'unknown');

/// A per-day, salted digest of the caller so repeated checks from one Mac count once.
/// It rotates every day and is never stored next to the address it is derived from,
/// so it cannot follow an install from one day to the next.
async function dailyCallerKey(request, env) {
  const salt = env?.ANALYTICS_SALT;
  if (!salt) return null;
  const material = [
    new Date().toISOString().slice(0, 10),
    salt,
    request.headers.get('CF-Connecting-IP') ?? '',
    request.headers.get('User-Agent') ?? '',
  ].join('\n');
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(material));
  return [...new Uint8Array(digest).slice(0, 8)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function writeEvent(request, env, kind, appVersion, systemVersion) {
  if (!env?.USAGE) return;
  const key = await dailyCallerKey(request, env);
  env.USAGE.writeDataPoint({
    blobs: [kind, appVersion, systemVersion, request.cf?.country ?? 'unknown'],
    doubles: [1],
    ...(key ? { indexes: [key] } : {}),
  });
}

function count(request, env, ctx, kind, appVersion = 'unknown', systemVersion = 'unknown') {
  const written = writeEvent(request, env, kind, appVersion, systemVersion).catch(() => {});
  ctx?.waitUntil?.(written);
}

function json(body, status, request) {
  return new Response(request.method === 'HEAD' ? null : JSON.stringify(body), {
    status,
    headers: { ...securityHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  });
}

async function latestRelease(request, env, ctx) {
  const params = new URL(request.url).searchParams;
  count(
    request,
    env,
    ctx,
    labelled(params.get('k'), (value) => checkKinds.has(value)),
    labelled(params.get('v'), (value) => versionPattern.test(value ?? '')),
    labelled(params.get('os'), (value) => versionPattern.test(value ?? '')),
  );

  try {
    const upstream = await fetch(latestReleaseAPI, {
      headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'air-stats-download-worker' },
      cf: { cacheTtl: releaseCacheSeconds, cacheEverything: true },
    });
    if (!upstream.ok) return json({ error: 'upstream_unavailable' }, 502, request);
    const release = await upstream.json();
    if (typeof release?.tag_name !== 'string') return json({ error: 'upstream_unavailable' }, 502, request);
    return json({ tag_name: release.tag_name, body: String(release.body ?? '').slice(0, notesLimit) }, 200, request);
  } catch {
    return json({ error: 'upstream_unavailable' }, 502, request);
  }
}

export default {
  fetch(request, env, ctx) {
    if (!['GET', 'HEAD'].includes(request.method)) {
      return new Response(null, { status: 405, headers: { Allow: 'GET, HEAD' } });
    }
    const path = new URL(request.url).pathname;
    if (path === '/latest') {
      return latestRelease(request, env, ctx);
    }
    if (!redirectPaths.includes(path)) {
      return new Response(request.method === 'HEAD' ? null : 'Not found', { status: 404 });
    }
    count(request, env, ctx, 'download');
    return new Response(null, {
      status: 302,
      headers: { ...securityHeaders, Location: downloadURL },
    });
  },
};
