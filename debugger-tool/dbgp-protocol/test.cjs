const assert = require('node:assert/strict');
const { test } = require('node:test');
const { DBGpFramer } = require('./index.cjs');
const frame = text => Buffer.concat([Buffer.from(`${Buffer.byteLength(text)}\0`), Buffer.from(text), Buffer.from([0])]);

test('all byte boundaries preserve Unicode, length and complete frames', () => {
  const text = '<response note="café 🐈"/>';
  const packet = Buffer.concat([frame(text), frame('done')]);
  for (let split = 0; split <= packet.length; ++split) {
    const reader = new DBGpFramer();
    assert.deepEqual([...reader.push(packet.subarray(0, split)), ...reader.push(packet.subarray(split))], [text, 'done']);
  }
});

test('partial frames remain buffered and reset discards them', () => {
  const reader = new DBGpFramer();
  assert.deepEqual(reader.push(Buffer.from('5\0abc')), []);
  reader.reset();
  assert.deepEqual(reader.push(frame('next')), ['next']);
});

test('invalid framing fails explicitly and resets parser', () => {
  for (const packet of ['x\0', '12345678901', '3\0abc!', '99\0', Buffer.from([0xb3, 0])]) {
    const reader = new DBGpFramer(10);
    assert.throws(() => reader.push(Buffer.from(packet)), /DBGp/);
    assert.deepEqual(reader.push(frame('next')), ['next']);
  }
});
