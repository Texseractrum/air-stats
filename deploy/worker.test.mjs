import assert from 'node:assert/strict';
import test from 'node:test';
import worker, { downloadURL } from './worker.mjs';

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
