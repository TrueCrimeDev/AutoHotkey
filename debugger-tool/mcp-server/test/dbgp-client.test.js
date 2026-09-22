import { test } from 'node:test';
import assert from 'node:assert';
import { PassThrough } from 'node:stream';
import { DBGpClient } from '../build/dbgp-client.js';

function frame(xml) {
  const body = Buffer.from(xml, 'utf-8');
  return Buffer.concat([
    Buffer.from(String(body.length), 'ascii'),
    Buffer.from([0]),
    body,
    Buffer.from([0]),
  ]);
}

function makeClient() {
  const fromAhk = new PassThrough(); // what AHK writes (we write into this)
  const toAhk = new PassThrough();   // what AHK reads (commands appear here)
  const client = new DBGpClient(0);
  client.attachStream(fromAhk, toAhk);
  return { client, fromAhk, toAhk };
}

test('init packet marks client connected and emits init', async () => {
  const { client, fromAhk } = makeClient();
  const initSeen = new Promise((resolve) => client.once('init', resolve));
  fromAhk.write(frame('<init appid="AutoHotkey" protocol_version="1"/>'));
  const attrs = await initSeen;
  assert.equal(attrs.appid, 'AutoHotkey');
  assert.equal(client.isConnected(), true);
});

test('sendCommand resolves on matching transaction_id', async () => {
  const { client, fromAhk, toAhk } = makeClient();
  const ready = new Promise((r) => client.once('init', r));
  fromAhk.write(frame('<init appid="AutoHotkey"/>'));
  await ready;

  const commandSeen = new Promise((resolve) => {
    toAhk.once('data', (buf) => resolve(buf.toString('utf-8')));
  });
  const pending = client.getStatus();
  const sent = await commandSeen;
  assert.match(sent, /^status -i (\d+)\0$/);
  const tid = sent.match(/-i (\d+)/)[1];

  fromAhk.write(frame(`<response command="status" transaction_id="${tid}" status="break" reason="ok"/>`));
  const response = await pending;
  assert.equal(response.status, 'break');
});

test('stream packets are buffered, not treated as responses', async () => {
  const { client, fromAhk } = makeClient();
  const ready = new Promise((r) => client.once('init', r));
  fromAhk.write(frame('<init appid="AutoHotkey"/>'));
  await ready;

  const b64 = Buffer.from('line one\n', 'utf-8').toString('base64');
  const streamSeen = new Promise((resolve) => client.once('stream', resolve));
  fromAhk.write(frame(`<stream type="stdout" encoding="base64">${b64}</stream>`));
  await streamSeen;
  assert.equal(client.getOutput('stdout'), 'line one\n');
  assert.equal(client.getOutput('stdout', true), 'line one\n'); // clear=true
  assert.equal(client.getOutput('stdout'), '');
});

test('raw Print pollution is captured as stdout', async () => {
  const { client, fromAhk } = makeClient();
  const ready = new Promise((r) => client.once('init', r));
  fromAhk.write(frame('<init appid="AutoHotkey"/>'));
  await ready;

  const streamSeen = new Promise((resolve) => client.once('stream', resolve));
  fromAhk.write(Buffer.concat([
    Buffer.from('raw print line\n'),
    frame('<response transaction_id="99" status="break"/>'),
  ]));
  const pkt = await streamSeen;
  assert.equal(pkt.stream, 'stdout');
  assert.equal(client.getOutput('stdout'), 'raw print line\n');
});

test('detach rejects pending commands', async () => {
  const { client, fromAhk } = makeClient();
  const ready = new Promise((r) => client.once('init', r));
  fromAhk.write(frame('<init appid="AutoHotkey"/>'));
  await ready;

  const pending = client.getStatus();
  client.detach();
  await assert.rejects(pending, /disconnected/i);
  assert.equal(client.isConnected(), false);
});
