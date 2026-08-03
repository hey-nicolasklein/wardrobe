import assert from 'node:assert/strict';
import test from 'node:test';

import { SerialPoller } from './polling.js';

test('shutdown waits for the original in-flight poll despite extra ticks', async () => {
  let finish!: () => void;
  let runs = 0;
  const inFlight = new Promise<void>((resolve) => {
    finish = resolve;
  });
  const poller = new SerialPoller(async () => {
    runs += 1;
    await inFlight;
  }, (error) => assert.fail(error instanceof Error ? error : String(error)));

  poller.start();
  poller.start();
  assert.equal(runs, 1);

  let stopped = false;
  const stopping = poller.stop().then(() => {
    stopped = true;
  });
  await Promise.resolve();
  assert.equal(stopped, false);
  finish();
  await stopping;
  assert.equal(stopped, true);
});
