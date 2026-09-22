import { test } from 'node:test';
import assert from 'node:assert';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DBGpClient } from '../build/dbgp-client.js';
import { ScriptLauncher, toWindowsPath } from '../build/launcher.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FAKE_AHK = path.join(__dirname, 'fixtures', 'fake-ahk.js');
const FAKE_EXE = path.join(__dirname, 'fixtures', 'fake-ahk.sh');

test('toWindowsPath converts /mnt/<drive>/ paths', () => {
  assert.equal(toWindowsPath('/mnt/c/Users/me/script.ahk'), 'C:\\Users\\me\\script.ahk');
  assert.equal(toWindowsPath('C:\\already\\windows.ahk'), 'C:\\already\\windows.ahk');
  assert.equal(toWindowsPath('relative.ahk'), 'relative.ahk');
});

test('launch waits for init and reports pid', async () => {
  const client = new DBGpClient(0);
  const launcher = new ScriptLauncher(client);
  const result = await launcher.launch(FAKE_AHK, {
    exe: FAKE_EXE,
    breakOnException: false,
    redirectStreams: false,
  });
  assert.ok(result.pid > 0);
  assert.equal(result.initAttributes.appid, 'AutoHotkey');
  assert.equal(launcher.isRunning(), true);
  await launcher.terminate();
});

test('run produces stream output and exit is recorded', async () => {
  const client = new DBGpClient(0);
  const launcher = new ScriptLauncher(client);
  await launcher.launch(FAKE_AHK, {
    exe: FAKE_EXE,
    breakOnException: false,
    redirectStreams: false,
  });
  const response = await client.run();
  assert.equal(response.status, 'stopping');
  assert.equal(client.getOutput('stdout'), 'fake output\n');

  // wait for child exit to be observed
  await new Promise((resolve) => setTimeout(resolve, 300));
  assert.equal(launcher.isRunning(), false);
  assert.deepEqual(launcher.getExitInfo(), { code: 0 });
});

test('second launch while running is refused', async () => {
  const client = new DBGpClient(0);
  const launcher = new ScriptLauncher(client);
  await launcher.launch(FAKE_AHK, {
    exe: FAKE_EXE,
    breakOnException: false,
    redirectStreams: false,
  });
  await assert.rejects(
    launcher.launch(FAKE_AHK, { exe: FAKE_EXE, breakOnException: false, redirectStreams: false }),
    /already running/i
  );
  await launcher.terminate();
});
