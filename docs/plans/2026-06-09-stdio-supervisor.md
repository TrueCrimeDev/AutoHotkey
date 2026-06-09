# Stdio Child-Process Supervisor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the MCP server launch and own `AutoHotkey64.exe` as a child process, speaking DBGp over the child's stdin/stdout (`/Debug=stdio`), removing the port-9000/listen-first/manual-launch workflow.

**Architecture:** Extract a robust DBGp frame parser (port of `test-stdio-dbgp.js`), make `DBGpClient` transport-agnostic via `attachStream(input, output)` (TCP socket and child pipes both attach the same way), add a `ScriptLauncher` that spawns the exe and wires it to the client, and expose three new MCP tools: `launch_script`, `terminate_script`, `get_script_output`. Script stdout/stderr arrive as DBGp `<stream>` packets (base64) and are buffered for `get_script_output`. TCP listen on 9000 stays for back-compat.

**Tech Stack:** TypeScript (ES2022/Node16 modules), Node 18 built-in `node:test`, no new dependencies.

**Roadmap context (decided 2026-06-09):**
- This plan = Phase 1 (stdio supervisor) + doc updates (stdin-`*`, break→eval→run pattern, NDJSON convention).
- GUI bridge (introspect/drive/screenshot a running GUI) = Phase 2, separate plan.
- DAP adapter: dropped (zero-plusplus extension covers IDE use; adds nothing for the harness).
- In-process eval channel: demoted — use DBGp async `break` → `eval` → `run` instead (engine advertises `supports_async=1`).

**Key engine facts (verified in source):**
- `/Debug=stdio` selects `StdioTransport` (`source/Debugger.cpp:2653`, `source/AutoHotkey.cpp:280-285`).
- After debugger connect, the engine calls `g_Debugger.Break()` (`source/AutoHotkey.cpp:427-429`) — a launched script is **paused before auto-exec**; first `run` starts it.
- DBGp framing both directions: `<length>\0<xml>\0`; commands sent as `cmd -i <tid>\0`.
- `stdout -c 2` / `stderr -c 2` redirect script output into `<stream type="..." encoding="base64">` packets (`source/Debugger.cpp:2300-2305`) — required in stdio mode so script output can't pollute the protocol pipe.
- `breakpoint_set -t exception` is supported (`source/Debugger.cpp:724`, `breakpoint_types: "line exception"`).
- Working dir for all paths below: repo root `/mnt/c/Users/uphol/Documents/Design/Coding/AutoHotkey`.

---

### Task 0: Branch setup

**Files:** none

- [ ] **Step 1: Create feature branch from alpha**

```bash
git checkout alpha && git checkout -b feat/stdio-supervisor
```

Note: the working tree has an unrelated modification (`tests/test_console.ahk`) and untracked `drafts/`. Leave both alone; never `git add -A`.

---

### Task 1: DBGp frame parser module

**Files:**
- Create: `debugger-tool/mcp-server/src/dbgp-parser.ts`
- Create: `debugger-tool/mcp-server/test/dbgp-parser.test.js`
- Modify: `debugger-tool/mcp-server/package.json` (add test script)

- [ ] **Step 1: Add test script to package.json**

In `debugger-tool/mcp-server/package.json`, change the `scripts` block to:

```json
  "scripts": {
    "build": "tsc",
    "watch": "tsc --watch",
    "prepare": "npm run build",
    "test": "npm run build && node --test test/"
  },
```

- [ ] **Step 2: Write the failing tests**

Create `debugger-tool/mcp-server/test/dbgp-parser.test.js`:

```js
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
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd debugger-tool/mcp-server && npm test
```

Expected: FAIL — `Cannot find module '../build/dbgp-parser.js'`.

- [ ] **Step 4: Write the implementation**

Create `debugger-tool/mcp-server/src/dbgp-parser.ts`:

```ts
/**
 * DBGp frame parser and packet classifier.
 * Wire framing (both directions, TCP and stdio): <length>\0<xml>\0
 * where <length> is the ASCII decimal byte count of <xml>.
 */

export interface DbgpStreamPacket {
  kind: 'stream';
  stream: 'stdout' | 'stderr';
  text: string;
}

export interface DbgpInitPacket {
  kind: 'init';
  attributes: Record<string, string>;
}

export interface DbgpResponsePacket {
  kind: 'response';
  attributes: Record<string, string>;
  raw: string;
}

export type DbgpPacket = DbgpStreamPacket | DbgpInitPacket | DbgpResponsePacket;

export class DbgpFrameParser {
  private buffer = Buffer.alloc(0);

  /** Feed raw bytes; returns any complete XML payloads. */
  feed(chunk: Buffer): string[] {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    const messages: string[] = [];

    for (;;) {
      const nullPos = this.buffer.indexOf(0);
      if (nullPos === -1) break;

      const lengthStr = this.buffer.subarray(0, nullPos).toString('ascii');
      const dataLength = parseInt(lengthStr, 10);
      if (isNaN(dataLength) || dataLength < 0 || String(dataLength) !== lengthStr) {
        // Corrupted framing — drop one byte and resync.
        this.buffer = this.buffer.subarray(1);
        continue;
      }

      const totalNeeded = nullPos + 1 + dataLength + 1;
      if (this.buffer.length < totalNeeded) break; // wait for more data

      messages.push(this.buffer.subarray(nullPos + 1, nullPos + 1 + dataLength).toString('utf-8'));
      this.buffer = this.buffer.subarray(totalNeeded);
    }

    return messages;
  }
}

export function parseAttributes(tagBody: string): Record<string, string> {
  const attrs: Record<string, string> = {};
  const re = /(\w+)="([^"]*)"/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(tagBody)) !== null) attrs[m[1]] = m[2];
  return attrs;
}

export function classifyPacket(xml: string): DbgpPacket {
  const streamMatch = xml.match(/<stream([^>]*)>([\s\S]*?)<\/stream>/);
  if (streamMatch) {
    const attrs = parseAttributes(streamMatch[1]);
    return {
      kind: 'stream',
      stream: attrs.type === 'stderr' ? 'stderr' : 'stdout',
      text: Buffer.from(streamMatch[2].trim(), 'base64').toString('utf-8'),
    };
  }

  const initMatch = xml.match(/<init([^>]*?)\/?>/);
  if (initMatch) {
    return { kind: 'init', attributes: parseAttributes(initMatch[1]) };
  }

  const respMatch = xml.match(/<response([^>]*?)\/?>/);
  return {
    kind: 'response',
    attributes: respMatch ? parseAttributes(respMatch[1]) : {},
    raw: xml,
  };
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd debugger-tool/mcp-server && npm test
```

Expected: 7 pass, 0 fail.

- [ ] **Step 6: Commit**

```bash
git add debugger-tool/mcp-server/src/dbgp-parser.ts debugger-tool/mcp-server/test/dbgp-parser.test.js debugger-tool/mcp-server/package.json
git commit -m "feat(mcp): add robust DBGp frame parser with stream packet support"
```

---

### Task 2: Transport-agnostic DBGpClient

**Files:**
- Modify: `debugger-tool/mcp-server/src/dbgp-client.ts`
- Create: `debugger-tool/mcp-server/test/dbgp-client.test.js`

The client currently hardwires `net.Socket`. Make it work over any (Readable, Writable) pair, route responses by transaction id, capture `<stream>` packets into output buffers, and treat `<init>` as the connected signal.

- [ ] **Step 1: Write the failing tests**

Create `debugger-tool/mcp-server/test/dbgp-client.test.js`:

```js
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
  fromAhk.write(frame('<init appid="AutoHotkey"/>'));
  await new Promise((r) => client.once('init', r));

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
  fromAhk.write(frame('<init appid="AutoHotkey"/>'));
  await new Promise((r) => client.once('init', r));

  const b64 = Buffer.from('line one\n', 'utf-8').toString('base64');
  const streamSeen = new Promise((resolve) => client.once('stream', resolve));
  fromAhk.write(frame(`<stream type="stdout" encoding="base64">${b64}</stream>`));
  await streamSeen;
  assert.equal(client.getOutput('stdout'), 'line one\n');
  assert.equal(client.getOutput('stdout', true), 'line one\n'); // clear=true
  assert.equal(client.getOutput('stdout'), '');
});

test('detach rejects pending commands', async () => {
  const { client, fromAhk } = makeClient();
  fromAhk.write(frame('<init appid="AutoHotkey"/>'));
  await new Promise((r) => client.once('init', r));

  const pending = client.getStatus();
  client.detach();
  await assert.rejects(pending, /disconnected/i);
  assert.equal(client.isConnected(), false);
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd debugger-tool/mcp-server && npm test
```

Expected: dbgp-parser tests pass; dbgp-client tests FAIL (`client.attachStream is not a function`).

- [ ] **Step 3: Rewrite the transport/command core of dbgp-client.ts**

In `debugger-tool/mcp-server/src/dbgp-client.ts`:

**3a.** Replace the imports at the top (lines 1-6) with:

```ts
/**
 * DBGp Client - speaks DBGp to AutoHotkey over any stream pair
 * (TCP socket or a child process's stdio when launched with /Debug=stdio).
 */

import * as net from 'net';
import { EventEmitter } from 'events';
import { DbgpFrameParser, classifyPacket } from './dbgp-parser.js';
```

**3b.** Replace the class fields and `listen()`/`handleData()`/`sendCommand()` (lines 50-146) with:

```ts
interface PendingCommand {
  resolve: (response: DebugResponse) => void;
  reject: (err: Error) => void;
  timer: NodeJS.Timeout | null;
}

export class DBGpClient extends EventEmitter {
  private server: net.Server | null = null;
  private output: NodeJS.WritableStream | null = null;
  private transactionId = 1;
  private port: number;
  private parser = new DbgpFrameParser();
  private connected = false;
  private pending = new Map<number, PendingCommand>();
  private stdoutBuffer = '';
  private stderrBuffer = '';
  private errorQueue: ErrorInfo[] = [];
  private errorQueueMaxSize = 100;
  private errorWaiters: Array<(error: ErrorInfo) => void> = [];

  constructor(port: number = 9000) {
    super();
    this.port = port;
  }

  /**
   * Attach any (input, output) stream pair as the DBGp transport.
   * TCP: attachStream(socket, socket). Stdio child: attachStream(child.stdout, child.stdin).
   */
  attachStream(input: NodeJS.ReadableStream, output: NodeJS.WritableStream): void {
    this.parser = new DbgpFrameParser();
    this.output = output;
    input.on('data', (data: Buffer) => {
      for (const xml of this.parser.feed(data)) this.handlePacket(xml);
    });
    input.on('end', () => this.detach());
    input.on('error', (err: Error) => this.emit('error', err));
  }

  /** Drop the current transport, rejecting all in-flight commands. */
  detach(): void {
    if (!this.connected && !this.output) return;
    this.connected = false;
    this.output = null;
    for (const [, entry] of this.pending) {
      if (entry.timer) clearTimeout(entry.timer);
      entry.reject(new Error('Debugger disconnected'));
    }
    this.pending.clear();
    this.emit('disconnected');
  }

  /**
   * Start listening for an AutoHotkey TCP connection (legacy /Debug mode).
   */
  async listen(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.server = net.createServer((socket) => {
        this.attachStream(socket, socket);
      });

      this.server.listen(this.port, '127.0.0.1', () => {
        this.emit('listening', this.port);
        resolve();
      });

      this.server.on('error', reject);
    });
  }

  private handlePacket(xml: string): void {
    const packet = classifyPacket(xml);

    if (packet.kind === 'stream') {
      if (packet.stream === 'stdout') this.stdoutBuffer += packet.text;
      else this.stderrBuffer += packet.text;
      this.emit('stream', packet);
      return;
    }

    if (packet.kind === 'init') {
      this.connected = true;
      this.emit('init', packet.attributes);
      this.emit('connected');
      return;
    }

    this.emit('message', xml);
    const tid = parseInt(packet.attributes.transaction_id ?? '', 10);
    const entry = isNaN(tid) ? undefined : this.pending.get(tid);
    if (entry) {
      this.pending.delete(tid);
      if (entry.timer) clearTimeout(entry.timer);
      entry.resolve(this.parseResponse(xml));
    }
  }

  /** Buffered script output captured from DBGp <stream> packets. */
  getOutput(stream: 'stdout' | 'stderr', clear = false): string {
    const value = stream === 'stdout' ? this.stdoutBuffer : this.stderrBuffer;
    if (clear) {
      if (stream === 'stdout') this.stdoutBuffer = '';
      else this.stderrBuffer = '';
    }
    return value;
  }

  /**
   * Send DBGp command. timeoutMs=0 disables the timeout (used for run/step,
   * which legitimately block until a breakpoint or script end).
   */
  private async sendCommand(command: string, timeoutMs = 5000): Promise<DebugResponse> {
    if (!this.output || !this.connected) {
      throw new Error('Not connected to AutoHotkey debugger');
    }

    const tid = this.transactionId++;
    const fullCommand = `${command} -i ${tid}\0`;

    return new Promise((resolve, reject) => {
      const timer = timeoutMs > 0
        ? setTimeout(() => {
            this.pending.delete(tid);
            reject(new Error(`Command timeout after ${timeoutMs}ms: ${command}`));
          }, timeoutMs)
        : null;

      this.pending.set(tid, { resolve, reject, timer });
      this.output!.write(fullCommand);
    });
  }
```

**3c.** Replace the debug-control methods (former lines 232-258) so run/step get a long timeout:

```ts
  // === Debug Control Commands ===

  async run(timeoutMs = 60000): Promise<DebugResponse> {
    return this.sendCommand('run', timeoutMs);
  }

  async stepInto(): Promise<DebugResponse> {
    return this.sendCommand('step_into', 60000);
  }

  async stepOver(): Promise<DebugResponse> {
    return this.sendCommand('step_over', 60000);
  }

  async stepOut(): Promise<DebugResponse> {
    return this.sendCommand('step_out', 60000);
  }

  async stop(): Promise<DebugResponse> {
    return this.sendCommand('stop');
  }

  async getStatus(): Promise<DebugResponse> {
    return this.sendCommand('status');
  }

  async sendRawCommand(command: string): Promise<DebugResponse> {
    return this.sendCommand(command);
  }
```

**3d.** Replace `close()` (former lines 340-350) with:

```ts
  async close(): Promise<void> {
    this.detach();
    if (this.server) {
      this.server.close();
      this.server = null;
    }
  }
```

Everything else (`parseResponse`, `parseProperties`, `parseStack`, breakpoint/variable/stack methods, error-queue methods, `getSourceContext`) stays exactly as it is. The old `socket`/`buffer` fields and `handleData()` are gone — make sure no references remain (`grep -n "this.socket\|handleData\|this.buffer" src/dbgp-client.ts` must return nothing).

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd debugger-tool/mcp-server && npm test
```

Expected: all dbgp-parser + dbgp-client tests pass (11 total).

- [ ] **Step 5: Commit**

```bash
git add debugger-tool/mcp-server/src/dbgp-client.ts debugger-tool/mcp-server/test/dbgp-client.test.js
git commit -m "feat(mcp): make DBGpClient transport-agnostic with stream capture and per-command timeouts"
```

---

### Task 3: ScriptLauncher (child-process supervisor)

**Files:**
- Create: `debugger-tool/mcp-server/src/launcher.ts`
- Create: `debugger-tool/mcp-server/test/fixtures/fake-ahk.js`
- Create: `debugger-tool/mcp-server/test/launcher.test.js`

- [ ] **Step 1: Create the fake AHK fixture (lets launcher be tested without Windows exe)**

Create `debugger-tool/mcp-server/test/fixtures/fake-ahk.js`:

```js
// Simulates AutoHotkey64.exe /Debug=stdio: emits init, answers commands.
// Invoked as: node fake-ahk.js /Debug=stdio <script>

function frame(xml) {
  const body = Buffer.from(xml, 'utf-8');
  return Buffer.concat([
    Buffer.from(String(body.length), 'ascii'),
    Buffer.from([0]),
    body,
    Buffer.from([0]),
  ]);
}

process.stdout.write(frame('<init appid="AutoHotkey" language="AutoHotkey" protocol_version="1"/>'));

let buf = '';
process.stdin.on('data', (chunk) => {
  buf += chunk.toString('utf-8');
  let idx;
  while ((idx = buf.indexOf('\0')) !== -1) {
    const command = buf.slice(0, idx);
    buf = buf.slice(idx + 1);
    const tidMatch = command.match(/-i (\d+)/);
    const tid = tidMatch ? tidMatch[1] : '0';
    const name = command.split(' ')[0];

    if (name === 'run') {
      // Emit one stdout stream packet, then report script end and exit.
      const b64 = Buffer.from('fake output\n', 'utf-8').toString('base64');
      process.stdout.write(frame(`<stream type="stdout" encoding="base64">${b64}</stream>`));
      process.stdout.write(frame(`<response command="run" transaction_id="${tid}" status="stopping" reason="ok"/>`));
      setTimeout(() => process.exit(0), 50);
    } else if (name === 'stop') {
      process.stdout.write(frame(`<response command="stop" transaction_id="${tid}" status="stopped" reason="ok"/>`));
      setTimeout(() => process.exit(0), 50);
    } else {
      process.stdout.write(frame(`<response command="${name}" transaction_id="${tid}" status="starting" reason="ok"/>`));
    }
  }
});
```

- [ ] **Step 2: Write the failing tests**

Create `debugger-tool/mcp-server/test/launcher.test.js`:

```js
import { test } from 'node:test';
import assert from 'node:assert';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DBGpClient } from '../build/dbgp-client.js';
import { ScriptLauncher, toWindowsPath } from '../build/launcher.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const FAKE_AHK = path.join(__dirname, 'fixtures', 'fake-ahk.js');

test('toWindowsPath converts /mnt/<drive>/ paths', () => {
  assert.equal(toWindowsPath('/mnt/c/Users/me/script.ahk'), 'C:\\Users\\me\\script.ahk');
  assert.equal(toWindowsPath('C:\\already\\windows.ahk'), 'C:\\already\\windows.ahk');
  assert.equal(toWindowsPath('relative.ahk'), 'relative.ahk');
});

test('launch waits for init and reports pid', async () => {
  const client = new DBGpClient(0);
  const launcher = new ScriptLauncher(client);
  const result = await launcher.launch(FAKE_AHK, {
    exe: process.execPath,
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
    exe: process.execPath,
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
    exe: process.execPath,
    breakOnException: false,
    redirectStreams: false,
  });
  await assert.rejects(
    launcher.launch(FAKE_AHK, { exe: process.execPath, breakOnException: false, redirectStreams: false }),
    /already running/i
  );
  await launcher.terminate();
});
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd debugger-tool/mcp-server && npm test
```

Expected: launcher tests FAIL (`Cannot find module '../build/launcher.js'`); earlier tests still pass.

- [ ] **Step 4: Write the implementation**

Create `debugger-tool/mcp-server/src/launcher.ts`:

```ts
/**
 * ScriptLauncher - spawns AutoHotkey64.exe /Debug=stdio as a child process
 * and wires its stdio to a DBGpClient. The MCP server owns the process:
 * no TCP port, no listen-first ordering, deterministic teardown.
 */

import { spawn, ChildProcess } from 'child_process';
import * as path from 'path';
import { fileURLToPath } from 'url';
import { DBGpClient } from './dbgp-client.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// build/ -> mcp-server -> debugger-tool -> repo root
const DEFAULT_EXE = path.resolve(__dirname, '..', '..', '..', 'bin', 'AutoHotkey64.exe');

/** Convert a WSL /mnt/<drive>/ path to a Windows path; pass anything else through. */
export function toWindowsPath(p: string): string {
  const m = p.match(/^\/mnt\/([a-z])\/(.*)$/i);
  if (m) return `${m[1].toUpperCase()}:\\${m[2].replace(/\//g, '\\')}`;
  return p;
}

export interface LaunchOptions {
  exe?: string;
  args?: string[];
  breakOnException?: boolean;   // default true
  redirectStreams?: boolean;    // default true; false only for fake-exe tests
  initTimeoutMs?: number;       // default 10000
}

export interface LaunchResult {
  pid: number;
  initAttributes: Record<string, string>;
}

export interface ExitInfo {
  code: number | null;
}

export class ScriptLauncher {
  private child: ChildProcess | null = null;
  private exitInfo: ExitInfo | null = null;
  private rawStderr = '';
  private scriptPath = '';

  constructor(private client: DBGpClient) {}

  isRunning(): boolean {
    return this.child !== null && this.exitInfo === null;
  }

  getPid(): number | null {
    return this.child?.pid ?? null;
  }

  getScriptPath(): string {
    return this.scriptPath;
  }

  getExitInfo(): ExitInfo | null {
    return this.exitInfo;
  }

  /** Raw bytes the child wrote to its stderr pipe (engine diagnostics, not DBGp). */
  getRawStderr(clear = false): string {
    const value = this.rawStderr;
    if (clear) this.rawStderr = '';
    return value;
  }

  async launch(script: string, opts: LaunchOptions = {}): Promise<LaunchResult> {
    if (this.isRunning()) {
      throw new Error(`A script is already running (pid ${this.getPid()}). Call terminate_script first.`);
    }

    const exe = opts.exe ?? process.env.AHK_EXE ?? DEFAULT_EXE;
    // Only translate to a Windows path when targeting a Windows binary.
    const scriptArg = exe.toLowerCase().endsWith('.exe') ? toWindowsPath(script) : script;

    const child = spawn(exe, ['/Debug=stdio', scriptArg, ...(opts.args ?? [])], {
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    this.child = child;
    this.exitInfo = null;
    this.rawStderr = '';
    this.scriptPath = scriptArg;

    child.stderr!.on('data', (chunk: Buffer) => {
      this.rawStderr += chunk.toString('utf-8');
    });

    child.on('exit', (code) => {
      this.exitInfo = { code };
      this.client.detach();
    });

    const initPromise = new Promise<Record<string, string>>((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error(`Timed out waiting for DBGp init from ${exe}`)),
        opts.initTimeoutMs ?? 10000
      );
      this.client.once('init', (attrs: Record<string, string>) => {
        clearTimeout(timer);
        resolve(attrs);
      });
      child.once('error', (err) => {
        clearTimeout(timer);
        reject(new Error(`Failed to start ${exe}: ${err.message}`));
      });
      child.once('exit', (code) => {
        clearTimeout(timer);
        reject(new Error(`Process exited before DBGp init (code ${code}). Stderr: ${this.rawStderr.trim()}`));
      });
    });

    this.client.attachStream(child.stdout!, child.stdin!);

    let initAttributes: Record<string, string>;
    try {
      initAttributes = await initPromise;
    } catch (err) {
      this.child = null;
      child.kill();
      throw err;
    }

    // In stdio mode the protocol shares the pipe with script output:
    // redirect stdout/stderr into DBGp <stream> packets so nothing pollutes framing.
    if (opts.redirectStreams !== false) {
      await this.client.sendRawCommand('stdout -c 2');
      await this.client.sendRawCommand('stderr -c 2');
    }

    // Break on uncaught exceptions so capture/inspect works before the process dies.
    if (opts.breakOnException !== false) {
      await this.client.sendRawCommand('breakpoint_set -t exception');
    }

    return { pid: child.pid!, initAttributes };
  }

  async terminate(): Promise<ExitInfo> {
    const child = this.child;
    if (!child || this.exitInfo) {
      return this.exitInfo ?? { code: null };
    }

    const exited = new Promise<void>((resolve) => child.once('exit', () => resolve()));

    try {
      await this.client.stop();
    } catch {
      // stop may fail if the session is wedged; fall through to kill
    }

    const result = await Promise.race([
      exited.then(() => true),
      new Promise<boolean>((resolve) => setTimeout(() => resolve(false), 2000)),
    ]);
    if (!result) {
      child.kill();
      await Promise.race([exited, new Promise((resolve) => setTimeout(resolve, 1000))]);
    }

    return this.exitInfo ?? { code: null };
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd debugger-tool/mcp-server && npm test
```

Expected: all tests pass (15 total).

- [ ] **Step 6: Commit**

```bash
git add debugger-tool/mcp-server/src/launcher.ts debugger-tool/mcp-server/test/fixtures/fake-ahk.js debugger-tool/mcp-server/test/launcher.test.js
git commit -m "feat(mcp): add ScriptLauncher child-process supervisor for /Debug=stdio"
```

---

### Task 4: MCP tools — launch_script, terminate_script, get_script_output

**Files:**
- Modify: `debugger-tool/mcp-server/src/index.ts`

- [ ] **Step 1: Import launcher and create instance**

In `src/index.ts`, change line 18:

```ts
import { DBGpClient, ErrorInfo } from './dbgp-client.js';
import { ScriptLauncher } from './launcher.js';
```

After `const client = new DBGpClient(9000);` (line 24), add:

```ts
const launcher = new ScriptLauncher(client);
```

- [ ] **Step 2: Add Zod schemas**

After `WorkspaceSymbolsSchema` (line 117), add:

```ts
const LaunchScriptSchema = z.object({
  script: z.string().describe('Path to the .ahk script (Windows path or WSL /mnt/<drive>/ path)'),
  exe: z.string().optional().describe('Path to AutoHotkey64.exe (default: repo bin/AutoHotkey64.exe, or AHK_EXE env var)'),
  args: z.array(z.string()).optional().describe('Extra command-line arguments passed to the script'),
  break_on_exception: z.boolean().optional().describe('Break on uncaught exceptions (default: true)'),
});

const GetScriptOutputSchema = z.object({
  clear: z.boolean().optional().describe('Clear buffered output after reading (default: false)'),
});
```

- [ ] **Step 3: Register tools in the ListTools handler**

In the `tools:` array (inside the handler starting line 253), add as the FIRST entries (before `debug_run`):

```ts
      // Process Supervision (stdio transport)
      {
        name: 'launch_script',
        description: 'Launch an AutoHotkey script as a supervised child process with the debugger attached over stdio (no port 9000 needed). Script starts paused; call debug_run to begin execution.',
        inputSchema: {
          type: 'object',
          properties: {
            script: { type: 'string', description: 'Path to the .ahk script (Windows or WSL /mnt path)' },
            exe: { type: 'string', description: 'Path to AutoHotkey64.exe (optional)' },
            args: { type: 'array', items: { type: 'string' }, description: 'Extra script arguments' },
            break_on_exception: { type: 'boolean', description: 'Break on uncaught exceptions (default: true)' },
          },
          required: ['script'],
        },
      },
      {
        name: 'terminate_script',
        description: 'Stop and kill the script launched via launch_script',
        inputSchema: { type: 'object', properties: {}, required: [] },
      },
      {
        name: 'get_script_output',
        description: 'Get the launched script\'s buffered stdout/stderr, run state, and exit code',
        inputSchema: {
          type: 'object',
          properties: {
            clear: { type: 'boolean', description: 'Clear buffers after reading (default: false)' },
          },
          required: [],
        },
      },
```

- [ ] **Step 4: Add tool handlers**

In the CallTool switch (after the `requiresDebugger` gate — do NOT add the new tools to `requiresDebugger`; they must work without a connection), add before `case 'debug_run':`:

```ts
      // Process Supervision
      case 'launch_script': {
        const params = LaunchScriptSchema.parse(args);
        const result = await launcher.launch(params.script, {
          exe: params.exe,
          args: params.args,
          breakOnException: params.break_on_exception,
        });
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                status: 'launched',
                pid: result.pid,
                transport: 'stdio',
                script: launcher.getScriptPath(),
                note: 'Script is paused before auto-execute. Call debug_run to start it; use get_script_output to read its stdout/stderr.',
              }, null, 2),
            },
          ],
        };
      }

      case 'terminate_script': {
        if (!launcher.getPid()) {
          return {
            content: [{ type: 'text', text: 'No script has been launched via launch_script.' }],
          };
        }
        const exit = await launcher.terminate();
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({ status: 'terminated', exit_code: exit.code }, null, 2),
            },
          ],
        };
      }

      case 'get_script_output': {
        const params = GetScriptOutputSchema.parse(args);
        const clear = params.clear ?? false;
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                running: launcher.isRunning(),
                pid: launcher.getPid(),
                exit: launcher.getExitInfo(),
                stdout: client.getOutput('stdout', clear),
                stderr: client.getOutput('stderr', clear) + launcher.getRawStderr(clear),
              }, null, 2),
            },
          ],
        };
      }
```

- [ ] **Step 5: Update startup log in main()**

Replace lines 1176-1177:

```ts
  console.error(`Listening for AutoHotkey on port 9000 (legacy TCP mode)`);
  console.error('Preferred: use the launch_script tool to spawn scripts over stdio.');
  console.error('Legacy: start AutoHotkey manually with: AutoHotkey.exe /Debug your_script.ahk');
```

- [ ] **Step 6: Build and run all tests**

```bash
cd debugger-tool/mcp-server && npm test
```

Expected: clean build, all 15 tests pass.

- [ ] **Step 7: Commit**

```bash
git add debugger-tool/mcp-server/src/index.ts
git commit -m "feat(mcp): add launch_script/terminate_script/get_script_output tools"
```

---

### Task 5: Integration test against the real engine

**Files:**
- Create: `debugger-tool/mcp-server/test/integration-launch.test.js`

Runs only when `bin/AutoHotkey64.exe` exists (skips cleanly elsewhere, e.g. CI on Linux).

- [ ] **Step 1: Write the integration test**

Create `debugger-tool/mcp-server/test/integration-launch.test.js`:

```js
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

const FIXTURE = path.join(__dirname, 'fixtures', 'integration-hello.ahk');

test('real engine: launch, run, stream stdout, clean exit', { skip: !HAVE_EXE }, async () => {
  fs.writeFileSync(FIXTURE, 'Print("hello-from-integration")\r\nExitApp(0)\r\n');
  const client = new DBGpClient(0);
  const launcher = new ScriptLauncher(client);

  try {
    const result = await launcher.launch(FIXTURE, { exe: EXE });
    assert.equal(result.initAttributes.language.toLowerCase(), 'autohotkey');

    const response = await client.run();
    assert.equal(response.status, 'stopping');

    // give the process a moment to flush and exit
    await new Promise((resolve) => setTimeout(resolve, 1000));
    assert.match(client.getOutput('stdout'), /hello-from-integration/);
    assert.equal(launcher.isRunning(), false);
    assert.equal(launcher.getExitInfo()?.code, 0);
  } finally {
    await launcher.terminate();
    fs.rmSync(FIXTURE, { force: true });
  }
});

test('real engine: exception breaks instead of dying', { skip: !HAVE_EXE }, async () => {
  fs.writeFileSync(FIXTURE, 'x := 1\r\nthrow Error("integration boom")\r\n');
  const client = new DBGpClient(0);
  const launcher = new ScriptLauncher(client);

  try {
    await launcher.launch(FIXTURE, { exe: EXE });
    const response = await client.run();
    assert.equal(response.status, 'break');

    const stack = await client.getStackTrace();
    assert.ok(stack.length >= 1);
    assert.equal(stack[0].lineno, 2);
  } finally {
    await launcher.terminate();
    fs.rmSync(FIXTURE, { force: true });
  }
});
```

- [ ] **Step 2: Run tests**

```bash
cd debugger-tool/mcp-server && npm test
```

Expected: all tests pass. The two integration tests run for real (the exe exists in this repo at `bin/AutoHotkey64.exe`); they spawn the Windows binary from WSL via interop. If `response.status` differs from expectations (e.g. `break` vs `stopping` semantics), inspect with `console.error(response)` and adjust assertions to the engine's actual behavior — the engine is the source of truth.

- [ ] **Step 3: Commit**

```bash
git add debugger-tool/mcp-server/test/integration-launch.test.js
git commit -m "test(mcp): integration tests for stdio launch against the real engine"
```

---

### Task 6: Documentation

**Files:**
- Modify: `AHK_V2_WORKFLOW_TECHNICAL.md`
- Modify: `debugger-tool/mcp-server/CLAUDE.md`
- Modify: `.claude/` session hook is generated elsewhere — skip; root `CLAUDE.md` gets one line.

- [ ] **Step 1: Add new sections to AHK_V2_WORKFLOW_TECHNICAL.md**

Insert after the "### 5. Run console output tests" section (after line 63), as new workflow entries:

```markdown
### 6. Launch under MCP supervision (stdio debugger, preferred)

The MCP server can spawn the engine itself — no port 9000, no listen-first ordering:

- MCP tool `launch_script` runs `bin\AutoHotkey64.exe /Debug=stdio script.ahk` as a child process.
- DBGp frames travel over the child's stdin/stdout; script `Print()`/stdout output is
  redirected into DBGp `<stream>` packets (`stdout -c 2`) and read via `get_script_output`.
- The script starts paused before auto-execute; `debug_run` begins execution.
- An exception breakpoint is set by default, so uncaught errors break for inspection
  (stack, variables, eval) instead of killing the process.

### 7. Run generated code from stdin (no temp file)

The engine accepts `*` as the script name and reads source from stdin:

```powershell
echo 'Print("hi")' | bin\AutoHotkey64.exe /ErrorStdOut *
```

Useful for validating or running harness-generated snippets without touching disk.
Combine with `check` for syntax-only validation of a snippet.

### 8. Interrupt a running script: break → eval → run

DBGp advertises `supports_async=1`, so a busy script can be interrupted at any time:

1. Send `break` (MCP: `debug_command` with `break`) — script pauses wherever it is.
2. Inspect or mutate: `evaluate`, `variables_get`, `property_set`.
3. Send `run` to resume.

This is the supported "REPL into a running process" pattern; it works even when the
script's own message loop is busy (unlike any in-script listener approach).

### 9. NDJSON event stream convention

For machine-readable script telemetry, emit one JSON object per line on stdout using
single-argument `Print()` (single-arg form never passes through Format, so literal
braces survive):

```autohotkey
Print('{"event":"start","detail":"loading config"}')
Print('{"event":"progress","step":3,"total":10}')
```

A supervising harness reads these from `get_script_output` (stdio launch) or the
process stdout (plain console run) and parses each line independently. Errors arrive
on the same model via `/Diag=json` on stderr.
```

Then renumber nothing else — the doc's later "## Technical Details by Feature" headings are independent.

- [ ] **Step 2: Update debugger-tool/mcp-server/CLAUDE.md**

After the "## Available Tools" heading, add a new first table section:

```markdown
### Process Supervision (preferred entry point)

| Tool | Description |
|------|-------------|
| `launch_script` | Spawn AutoHotkey64.exe /Debug=stdio with the script as a supervised child. No port 9000. Script starts paused; call `debug_run`. Sets an exception breakpoint by default. |
| `terminate_script` | Stop and kill the launched script. |
| `get_script_output` | Buffered stdout/stderr (via DBGp stream packets), run state, exit code. |
```

And replace the "Autonomous Error Fix Loop" code block with:

```
1. Claude calls: launch_script {"script": "C:\\path\\script.ahk"}
2. Claude calls: debug_run (starts execution; returns status=break on uncaught error)
3. On break: stack_trace + variables_get + evaluate to diagnose
4. Claude calls: apply_fix with the fix
5. Claude calls: terminate_script, then launch_script again to verify
   (Legacy TCP mode still works: user runs AutoHotkey64.exe /Debug script.ahk manually.)
```

- [ ] **Step 3: Add one line to root CLAUDE.md**

In the "## Running Scripts" code block of `CLAUDE.md` (repo root), add after the `/Debug` lines:

```bash
# Preferred from MCP: launch_script tool spawns the engine itself over /Debug=stdio (no port 9000)

# Run a generated snippet from stdin without a temp file
echo 'Print("hi")' | bin/AutoHotkey64.exe /ErrorStdOut *
```

- [ ] **Step 4: Commit**

```bash
git add AHK_V2_WORKFLOW_TECHNICAL.md debugger-tool/mcp-server/CLAUDE.md CLAUDE.md
git commit -m "docs: stdio supervision workflow, stdin-* execution, break/eval/run pattern, NDJSON convention"
```

---

### Task 7: Final verification

- [ ] **Step 1: Full test run**

```bash
cd debugger-tool/mcp-server && npm test
```

Expected: build clean, all unit + integration tests pass.

- [ ] **Step 2: Smoke-test the stdin-* doc claim**

```bash
echo 'Print("stdin-works")' | /mnt/c/Users/uphol/Documents/Design/Coding/AutoHotkey/bin/AutoHotkey64.exe /ErrorStdOut *
```

Expected: prints `stdin-works`, exit 0. If the engine does not support `*` (feature is stock v2 — `ScriptKindStdIn`, `source/script.cpp:1466`), remove workflow section 7 from the doc before committing.

- [ ] **Step 3: Push branch and open PR**

```bash
git push -u origin feat/stdio-supervisor
gh pr create --repo TrueCrimeDev/AutoHotkey --base alpha --title "feat(mcp): stdio child-process supervisor for harness-owned debugging" --body "..."
```
