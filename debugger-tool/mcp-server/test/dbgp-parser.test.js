import { test } from 'node:test';
import assert from 'node:assert';
import { DbgpFrameParser, classifyPacket } from '../build/dbgp-parser.js';

function frame(xml) {
  const body = Buffer.from(xml, 'utf-8');
  return Buffer.concat([
    Buffer.from(String(body.length), 'ascii'),
    Buffer.from([0]),
    body,
    Buffer.from([0]),
  ]);
}

test('parses a single frame', () => {
  const p = new DbgpFrameParser();
  const msgs = p.feed(frame('<response command="run" transaction_id="1" status="break"/>'));
  assert.equal(msgs.length, 1);
  assert.match(msgs[0], /command="run"/);
});

test('parses a frame split across chunks', () => {
  const p = new DbgpFrameParser();
  const f = frame('<response command="status" transaction_id="2" status="break"/>');
  const a = p.feed(f.subarray(0, 5));
  const b = p.feed(f.subarray(5));
  assert.equal(a.length, 0);
  assert.equal(b.length, 1);
});

test('parses multiple frames in one chunk', () => {
  const p = new DbgpFrameParser();
  const msgs = p.feed(Buffer.concat([frame('<init appid="AutoHotkey"/>'), frame('<response transaction_id="1"/>')]));
  assert.equal(msgs.length, 2);
});

test('resyncs after corrupted framing', () => {
  const p = new DbgpFrameParser();
  const msgs = p.feed(Buffer.concat([Buffer.from('garbage\0'), frame('<response transaction_id="3"/>')]));
  assert.equal(msgs.length, 1);
  assert.match(msgs[0], /transaction_id="3"/);
});

test('diverts raw non-frame bytes (Print passthrough) without losing frames', () => {
  const p = new DbgpFrameParser();
  const msgs = p.feed(Buffer.concat([
    Buffer.from('hello from Print\n'),
    frame('<response transaction_id="4" status="break"/>'),
  ]));
  assert.equal(msgs.length, 1);
  assert.equal(p.drainRaw(), 'hello from Print\n');
  assert.equal(p.drainRaw(), ''); // drained
});

test('classifies init packets', () => {
  const pkt = classifyPacket('<?xml version="1.0"?><init appid="AutoHotkey" language="AutoHotkey" protocol_version="1"/>');
  assert.equal(pkt.kind, 'init');
  assert.equal(pkt.attributes.appid, 'AutoHotkey');
});

test('classifies and decodes stream packets', () => {
  const b64 = Buffer.from('hello world\n', 'utf-8').toString('base64');
  const pkt = classifyPacket(`<stream type="stdout" encoding="base64">${b64}</stream>`);
  assert.equal(pkt.kind, 'stream');
  assert.equal(pkt.stream, 'stdout');
  assert.equal(pkt.text, 'hello world\n');
});

test('classifies response packets with attributes', () => {
  const pkt = classifyPacket('<response command="run" transaction_id="7" status="stopping"/>');
  assert.equal(pkt.kind, 'response');
  assert.equal(pkt.attributes.transaction_id, '7');
  assert.equal(pkt.attributes.status, 'stopping');
});
