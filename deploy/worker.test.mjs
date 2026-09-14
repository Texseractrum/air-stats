import assert from 'node:assert/strict';
import test from 'node:test';
import worker, { downloadURL, latestReleaseAPI } from './worker.mjs';

function recorder() {
  const points = [];
  return { points, env: { USAGE: { writeDataPoint: (point) => points.push(point) } } };
}

function stubGitHub(response) {
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url, options) => {
    calls.push({ url, options });
    return response;
  };
  return { calls, restore: () => { globalThis.fetch = original; } };
}

const settled = () => new Promise((resolve) => setImmediate(resolve));

for (const method of ['GET', 'HEAD']) {
  for (const path of ['/', '/download', '/AirStats.dmg', '/?campaign=test']) {
    test(`${method} ${path} starts the download without a landing page`, async () => {
      const response = worker.fetch(new Request(`https://health.sparkles.dev${path}`, { method }));
      assert.equal(response.status, 302);
      assert.equal(response.headers.get('Location'), downloadURL);
      assert.equal(response.headers.get('Cache-Control'), 'no-store');
      assert.equal(await response.text(), '');
    });
  }
}

test('unknown paths do not trigger downloads', () => {
  for (const path of ['/favicon.ico', '/robots.txt', '/secret', '//evil.example']) {
    assert.equal(worker.fetch(new Request(`https://health.sparkles.dev${path}`)).status, 404);
  }
});
test('HEAD 404 has no body', async () => {
  assert.equal(await worker.fetch(new Request('https://health.sparkles.dev/nope', { method: 'HEAD' })).text(), '');
});
test('write methods are rejected', () => {
  for (const method of ['POST', 'PUT', 'DELETE', 'PATCH']) {
    const response = worker.fetch(new Request('https://health.sparkles.dev', { method }));
    assert.equal(response.status, 405);
    assert.equal(response.headers.get('Allow'), 'GET, HEAD');
  }
});
test('query parameters cannot replace the download destination', () => {
  const response = worker.fetch(new Request('https://health.sparkles.dev/?url=https://evil.example'));
  assert.equal(response.headers.get('Location'), downloadURL);
});

test('downloads are counted without an analytics binding present', async () => {
  assert.equal(worker.fetch(new Request('https://health.sparkles.dev/download'), {}).status, 302);
});

test('downloads are counted', async () => {
  const { points, env } = recorder();
  worker.fetch(new Request('https://health.sparkles.dev/download'), env);
  await settled();
  assert.deepEqual(points[0].blobs, ['download', 'unknown', 'unknown', 'unknown']);
  assert.equal(points[0].indexes, undefined);
});

test('an update check is counted and answered from the public release', async () => {
  const { points, env } = recorder();
  const github = stubGitHub(new Response(JSON.stringify({ tag_name: 'v1.2.0', body: 'Notes' }), { status: 200 }));
  try {
    const response = await worker.fetch(
      new Request('https://health.sparkles.dev/latest?k=daily&v=1.1.0&os=15.2'),
      env,
    );
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { tag_name: 'v1.2.0', body: 'Notes' });
    assert.equal(response.headers.get('Cache-Control'), 'no-store');
    assert.equal(github.calls[0].url, latestReleaseAPI);
    await settled();
    assert.deepEqual(points[0].blobs, ['daily', '1.1.0', '15.2', 'unknown']);
  } finally {
    github.restore();
  }
});

test('unrecognised check details are recorded as unknown rather than stored verbatim', async () => {
  const { points, env } = recorder();
  const github = stubGitHub(new Response(JSON.stringify({ tag_name: 'v1.2.0' }), { status: 200 }));
  try {
    await worker.fetch(
      new Request('https://health.sparkles.dev/latest?k=<script>&v=not-a-version&os=' + '9'.repeat(40)),
      env,
    );
    await settled();
    assert.deepEqual(points[0].blobs, ['unknown', 'unknown', 'unknown', 'unknown']);
  } finally {
    github.restore();
  }
});

test('repeat checks from one Mac share a daily key when a salt is configured', async () => {
  const { points, env } = recorder();
  env.ANALYTICS_SALT = 'test-salt';
  const github = stubGitHub(new Response(JSON.stringify({ tag_name: 'v1.2.0' }), { status: 200 }));
  try {
    for (const kind of ['daily', 'manual']) {
      await worker.fetch(
        new Request(`https://health.sparkles.dev/latest?k=${kind}&v=1.1.0&os=15.2`, {
          headers: { 'CF-Connecting-IP': '203.0.113.7', 'User-Agent': 'AirStats/1.1.0 (2)' },
        }),
        env,
      );
    }
    await settled();
    assert.equal(points.length, 2);
    assert.match(points[0].indexes[0], /^[0-9a-f]{16}$/);
    assert.equal(points[0].indexes[0], points[1].indexes[0]);

    await worker.fetch(
      new Request('https://health.sparkles.dev/latest?k=daily&v=1.1.0&os=15.2', {
        headers: { 'CF-Connecting-IP': '203.0.113.8', 'User-Agent': 'AirStats/1.1.0 (2)' },
      }),
      env,
    );
    await settled();
    assert.notEqual(points[2].indexes[0], points[0].indexes[0]);
  } finally {
    github.restore();
  }
});

test('release notes are truncated so one release cannot bloat the response', async () => {
  const github = stubGitHub(new Response(JSON.stringify({ tag_name: 'v1.2.0', body: 'x'.repeat(9000) }), { status: 200 }));
  try {
    const response = await worker.fetch(new Request('https://health.sparkles.dev/latest'), {});
    assert.equal((await response.json()).body.length, 4000);
  } finally {
    github.restore();
  }
});

test('an unavailable release API fails without inventing a version', async () => {
  for (const upstream of [new Response('nope', { status: 503 }), new Response('{}', { status: 200 })]) {
    const github = stubGitHub(upstream);
    try {
      const response = await worker.fetch(new Request('https://health.sparkles.dev/latest'), {});
      assert.equal(response.status, 502);
      assert.deepEqual(await response.json(), { error: 'upstream_unavailable' });
    } finally {
      github.restore();
    }
  }
});

test('a check still counts when the release API is unreachable', async () => {
  const { points, env } = recorder();
  const original = globalThis.fetch;
  globalThis.fetch = async () => { throw new Error('offline'); };
  try {
    assert.equal((await worker.fetch(new Request('https://health.sparkles.dev/latest?k=install&v=1.1.0&os=15.2'), env)).status, 502);
    await settled();
    assert.deepEqual(points[0].blobs, ['install', '1.1.0', '15.2', 'unknown']);
  } finally {
    globalThis.fetch = original;
  }
});

test('write methods are rejected on the release path too', () => {
  assert.equal(worker.fetch(new Request('https://health.sparkles.dev/latest', { method: 'POST' }), {}).status, 405);
});
