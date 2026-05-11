#!/usr/bin/env node

const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const defaultExe = path.join(repoRoot, 'bin_harness', 'AutoHotkey64Harness.exe');

function parseArgs(argv) {
  const args = { exe: defaultExe, timeoutMs: 7000 };
  for (let i = 2; i < argv.length; ++i) {
    if (argv[i] === '--exe' && argv[i + 1]) {
      args.exe = path.resolve(argv[++i]);
    } else if (argv[i] === '--timeout-ms' && argv[i + 1]) {
      args.timeoutMs = Number(argv[++i]);
    } else {
      throw new Error(`Unknown argument: ${argv[i]}`);
    }
  }
  return args;
}

class DBGpParser {
  constructor() {
    this.buffer = Buffer.alloc(0);
    this.frames = [];
    this.junk = [];
  }

  feed(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    for (;;) {
      const nul = this.buffer.indexOf(0);
      if (nul < 0)
        return;

      const lengthText = this.buffer.subarray(0, nul).toString('ascii');
      if (!/^\d+$/.test(lengthText)) {
        this.junk.push(this.buffer.subarray(0, nul + 1));
        this.buffer = this.buffer.subarray(nul + 1);
        continue;
      }

      const length = Number(lengthText);
      const start = nul + 1;
      const end = start + length;
      if (this.buffer.length < end + 1)
        return;

      if (this.buffer[end] !== 0) {
        this.junk.push(this.buffer.subarray(0, end + 1));
        this.buffer = this.buffer.subarray(end + 1);
        continue;
      }

      this.frames.push(this.buffer.subarray(start, end).toString('utf8'));
      this.buffer = this.buffer.subarray(end + 1);
    }
  }

  finish() {
    if (this.buffer.length)
      this.junk.push(this.buffer);
  }

  junkText() {
    return Buffer.concat(this.junk).toString('utf8');
  }
}

function writeProbeScript() {
  const scriptPath = path.join(os.tmpdir(), `ahk-stdio-harness-${Date.now()}.ahk`);
  fs.writeFileSync(scriptPath, [
    '#Requires AutoHotkey v2.0',
    'FileAppend "USER_STDOUT_MARKER``n", "*"',
    'i := 0',
    'Loop 500 {',
    '    i += 1',
    '    Sleep 10',
    '}',
    ''
  ].join('\n'), 'utf8');
  return scriptPath;
}

function waitFor(predicate, timeoutMs, label) {
  const start = Date.now();
  return new Promise((resolve, reject) => {
    const timer = setInterval(() => {
      if (predicate()) {
        clearInterval(timer);
        resolve();
      } else if (Date.now() - start > timeoutMs) {
        clearInterval(timer);
        reject(new Error(`Timed out waiting for ${label}`));
      }
    }, 25);
  });
}

async function main() {
  const args = parseArgs(process.argv);
  if (!fs.existsSync(args.exe))
    throw new Error(`AutoHotkey test executable not found: ${args.exe}`);

  const scriptPath = writeProbeScript();
  const parser = new DBGpParser();
  let stderr = '';
  let closeInfo = null;

  const child = spawn(args.exe, ['/Debug=stdio', scriptPath], {
    cwd: repoRoot,
    stdio: ['pipe', 'pipe', 'pipe']
  });

  child.stdout.on('data', chunk => parser.feed(chunk));
  child.stderr.on('data', chunk => { stderr += chunk.toString('utf8'); });
  child.on('close', (code, signal) => { closeInfo = { code, signal }; });

  const killTimer = setTimeout(() => {
    if (!closeInfo)
      child.kill();
  }, args.timeoutMs + 1500);

  try {
    await waitFor(() => parser.frames.some(frame => frame.includes('<init')), args.timeoutMs, 'DBGp init frame');

    child.stdin.write(Buffer.from('run -i 1\0', 'utf8'));
    await new Promise(resolve => setTimeout(resolve, 250));
    child.stdin.write(Buffer.from('break -i 2\0', 'utf8'));

    await waitFor(
      () => parser.frames.some(frame => frame.includes('status="break"') || frame.includes('command="break"')),
      args.timeoutMs,
      'asynchronous break response'
    );

    child.stdin.write(Buffer.from('stop -i 3\0', 'utf8'));
    await waitFor(() => closeInfo, args.timeoutMs, 'process exit after stop');
  } finally {
    clearTimeout(killTimer);
    parser.finish();
    try { fs.unlinkSync(scriptPath); } catch {}
    if (!closeInfo)
      child.kill();
  }

  const junk = parser.junkText();
  const stdoutStreamSeen = parser.frames.some(frame =>
    frame.includes('<stream type="stdout">') || frame.includes("<stream type='stdout'>")
  );
  const failures = [];

  if (!parser.frames.some(frame => frame.includes('<init')))
    failures.push('missing DBGp init frame');
  if (!stdoutStreamSeen)
    failures.push('script stdout was not captured as a DBGp stream packet');
  if (junk.includes('USER_STDOUT_MARKER'))
    failures.push('raw script stdout polluted the DBGp stdout transport');
  if (junk.trim())
    failures.push(`unexpected raw stdout bytes: ${JSON.stringify(junk)}`);
  if (!closeInfo || closeInfo.signal)
    failures.push(`process did not exit cleanly: ${JSON.stringify(closeInfo)}`);

  const report = {
    exe: args.exe,
    frames: parser.frames.length,
    initSeen: parser.frames.some(frame => frame.includes('<init')),
    stdoutStreamSeen,
    rawStdoutBytes: junk.length,
    stderr,
    closeInfo,
    failures
  };

  console.log(JSON.stringify(report, null, 2));

  if (failures.length)
    process.exit(1);
}

main().catch(error => {
  console.error(error.stack || String(error));
  process.exit(1);
});
