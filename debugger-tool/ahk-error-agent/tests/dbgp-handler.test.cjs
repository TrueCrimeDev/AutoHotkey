const assert = require('node:assert/strict');
const { test } = require('node:test');
const { EventEmitter } = require('node:events');
const { DBGpHandler } = require('../dist/dbgp-handler.js');
const frame = xml => Buffer.concat([Buffer.from(`${Buffer.byteLength(xml)}\0`), Buffer.from(xml), Buffer.from([0])]);

test('handler preserves fragmented UTF-8 and dispatches complete responses', async () => {
  const handler = new DBGpHandler(0, 20);
  handler.socket = { write: () => true, destroy() {} };
  const pending = handler.sendCommand('status');
  const xml = '<response command="status" transaction_id="1" note="café 🐈"/>';
  for (const byte of frame(xml)) handler.handleData(Buffer.from([byte]));
  assert.equal((await pending).note, 'café 🐈');
  assert.equal(handler.pendingCommands.size, 0);
  handler.close();
});

test('timeout and close reject outstanding commands and remove timers', async () => {
  const handler = new DBGpHandler(0, 20);
  handler.socket = { write: () => true, destroy() {} };
  await assert.rejects(handler.sendCommand('status'), /timeout/);
  assert.equal(handler.pendingCommands.size, 0);
  const closed = assert.rejects(handler.sendCommand('status'), /closed/);
  handler.close();
  await closed;
  assert.equal(handler.pendingCommands.size, 0);
});

test('late socket events cannot terminate the replacement session', async () => {
  const handler = new DBGpHandler(0);
  const socket = () => Object.assign(new EventEmitter(), { write: () => true, destroy() {} });
  await handler.listen();
  try {
    const old = socket();
    handler.server.emit('connection', old);
    old.emit('end');
    const current = socket();
    handler.server.emit('connection', current);
    const messages = [];
    handler.on('message', message => messages.push(message));
    old.emit('data', frame('<response transaction_id="99"/>'));
    old.emit('end');
    old.emit('error', new Error('late previous-session error'));
    assert.equal(handler.socket, current);
    assert.deepEqual(messages, []);
  } finally {
    handler.close();
  }
});
