import { test } from 'node:test';
import assert from 'node:assert';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DBGpClient } from '../build/dbgp-client.js';
import { ScriptLauncher } from '../build/launcher.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '..', '..', '..');
const EXE = process.env.AHK_EXE ?? path.join(REPO_ROOT, 'bin', 'AutoHotkey64.exe');
const HAVE_EXE = fs.existsSync(EXE);

test('real engine: launch, run, stream stdout, clean exit', { skip: !HAVE_EXE }, async () => {
  const fixture = path.join(__dirname, 'fixtures', 'integration-hello.ahk');
  fs.writeFileSync(
    fixture,
    'Print("hello-from-integration")\r\nFileAppend("fileappend-marker`n", "*")\r\nExitApp(0)\r\n'
  );
  const client = new DBGpClient(0);
  const launcher = new ScriptLauncher(client);

  try {
    const result = await launcher.launch(fixture, { exe: EXE });
    assert.equal(result.initAttributes.language.toLowerCase(), 'autohotkey');

    const response = await client.run();
    // Engine reports "stopped" when the script runs to completion.
    assert.match(response.status, /^stopp(ing|ed)$/);

    // give the process a moment to flush and exit
    await new Promise((resolve) => setTimeout(resolve, 1000));
    const stdout = client.getOutput('stdout');
    assert.match(stdout, /hello-from-integration/); // raw Print passthrough
    assert.match(stdout, /fileappend-marker/);      // DBGp <stream> packet path
    assert.equal(launcher.isRunning(), false);
    assert.equal(launcher.getExitInfo()?.code, 0);
  } finally {
    await launcher.terminate();
    fs.rmSync(fixture, { force: true });
  }
});

test('real engine: exception breaks instead of dying', { skip: !HAVE_EXE }, async () => {
  const fixture = path.join(__dirname, 'fixtures', 'integration-throw.ahk');
  fs.writeFileSync(fixture, 'x := 1\r\nthrow Error("integration boom")\r\n');
  const client = new DBGpClient(0);
  const launcher = new ScriptLauncher(client);

  try {
    await launcher.launch(fixture, { exe: EXE });
    const response = await client.run();
    assert.equal(response.status, 'break');

    const stack = await client.getStackTrace();
    assert.ok(stack.length >= 1);
    assert.equal(stack[0].lineno, 2);
  } finally {
    await launcher.terminate();
    fs.rmSync(fixture, { force: true });
  }
});
