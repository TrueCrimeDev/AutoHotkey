import assert from 'node:assert/strict';
import { test } from 'node:test';
import { EventEmitter } from 'node:events';
import { DBGpClient } from '../build/dbgp-client.js';

const frame = xml => Buffer.concat([Buffer.from(`${Buffer.byteLength(xml)}\0`), Buffer.from(xml), Buffer.from([0])]);

test('DBGp framing preserves split UTF-8 and consumes multiple frames', () => {
  const client = new DBGpClient();
  const messages = [];
  client.on('message', xml => messages.push(xml));
  const xml = '<response command="status" transaction_id="1" note="café 🐈"/>';
  const packet = frame(xml);
  for (const byte of packet) client.handleData(Buffer.from([byte]));
  client.handleData(Buffer.concat([frame(xml), frame(xml)]));
  assert.deepEqual(messages, [xml, xml, xml]);
});

test('timed-out error waiters are removed', async () => {
  const client = new DBGpClient();
  assert.equal(await client.waitForError(10), null);
  assert.equal(client.errorWaiters.length, 0);
});

test('a waiting consumer receives each error only once', async () => {
  const client = new DBGpClient();
  const pending = client.waitForError(100);
  const error = { message: 'sample' };
  client.queueError(error);
  assert.equal(await pending, error);
  assert.deepEqual(client.getQueuedErrors(), []);
  assert.equal(await client.waitForError(10), null);
});

test('close resolves waiting error consumers', async () => {
  const client = new DBGpClient();
  const pending = client.waitForError(100);
  await client.close();
  assert.equal(client.errorWaiters.length, 0);
  assert.equal(await pending, null);
});

test('command response, timeout and close release pending requests', async () => {
  const client = new DBGpClient(0, 20);
  client.connected = true;
  client.socket = client.output = { write: () => true, end() {}, destroy() {} };
  const completed = client.getStatus();
  client.handleData(frame('<response command="status" transaction_id="1" status="break"/>'));
  assert.equal((await completed).status, 'break');
  await assert.rejects(client.getStatus(), /timeout/i);
  assert.equal(client.pendingCommands.size, 0);
  assert.equal(client.listenerCount('message'), 0);
  const disconnected = assert.rejects(client.getStatus(), /closed|disconnect/i);
  await client.close();
  await disconnected;
  assert.equal(client.pendingCommands.size, 0);
});

test('late socket events do not affect a replacement connection', async () => {
  const client = new DBGpClient(0);
  const socket = () => Object.assign(new EventEmitter(), { write: () => true, destroy() {} });
  await client.listen();
  try {
    const old = socket();
    client.server.emit('connection', old);
    old.emit('end');
    const current = socket();
    client.server.emit('connection', current);
    const messages = [];
    client.on('message', message => messages.push(message));
    old.emit('data', frame('<response transaction_id="99"/>'));
    old.emit('end');
    old.emit('error', new Error('late previous-session error'));
    assert.equal(client.socket, current);
    assert.equal(client.isConnected(), true);
    assert.deepEqual(messages, []);
  } finally {
    await client.close();
  }
});
