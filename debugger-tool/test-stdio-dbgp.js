#!/usr/bin/env node

/**
 * test-stdio-dbgp.js — Interactive test harness for AutoHotkey's /Debug=stdio transport.
 *
 * Spawns AutoHotkey64.exe with /Debug=stdio, parses DBGp messages from stdout,
 * and lets you send commands interactively via the terminal.
 *
 * Usage:
 *   node test-stdio-dbgp.js [script.ahk]
 *
 * Default script: Alpha22_Example.ahk (relative to this file's parent dir)
 *
 * Commands:
 *   status                        - Get debugger status
 *   run                           - Continue execution
 *   step_into                     - Step into
 *   step_over                     - Step over
 *   step_out                      - Step out
 *   breakpoint_set -t line -f <file> -n <line>
 *   breakpoint_list               - List all breakpoints
 *   stack_get                     - Get call stack
 *   context_get -c 0              - Get local variables
 *   context_get -c 1              - Get global variables
 *   property_get -n <varname>     - Get a variable's value
 *   source -f <fileuri>           - Get source code
 *   stop                          - Stop execution
 *   <any raw DBGp command>        - Sent as-is
 *   quit / exit                   - Kill process and exit
 */

const { spawn } = require('child_process');
const path = require('path');
const readline = require('readline');

// --- Config ---
const AHK_EXE = path.resolve(__dirname, '..', 'bin', 'AutoHotkey64.exe');
const DEFAULT_SCRIPT = path.resolve(__dirname, '..', 'examples', 'Alpha22_Example.ahk');
const scriptPath = process.argv[2]
  ? path.resolve(process.argv[2])
  : DEFAULT_SCRIPT;

let transactionId = 1;

// --- DBGp message parser ---
// DBGp framing: <length>\0<xml_data>\0
// We accumulate raw bytes and extract complete messages.

class DBGpParser {
  constructor() {
    this.buffer = Buffer.alloc(0);
  }

  /** Feed raw bytes, returns array of parsed XML strings */
  feed(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    const messages = [];

    for (;;) {
      // Find the first null byte (end of length prefix)
      const nullPos = this.buffer.indexOf(0);
      if (nullPos === -1) break;

      const lengthStr = this.buffer.slice(0, nullPos).toString('ascii');
      const dataLength = parseInt(lengthStr, 10);
      if (isNaN(dataLength)) {
        // Corrupted framing — skip this byte and try again
        this.buffer = this.buffer.slice(1);
        continue;
      }

      // Check if we have the full message: length_prefix + \0 + data + \0
      const totalNeeded = nullPos + 1 + dataLength + 1;
      if (this.buffer.length < totalNeeded) break; // Wait for more data

      const xmlData = this.buffer.slice(nullPos + 1, nullPos + 1 + dataLength).toString('utf-8');
      this.buffer = this.buffer.slice(totalNeeded);
      messages.push(xmlData);
    }

    return messages;
  }
}

// --- Simple XML formatter (indent for readability) ---
function formatXml(xml) {
  // Strip the <?xml ...?> declaration for cleaner output
  const stripped = xml.replace(/<\?xml[^?]*\?>/, '').trim();
  let indent = 0;
  return stripped.replace(/(>)(<)(\/*)/g, '$1\n$2$3')
    .split('\n')
    .map(line => {
      if (line.match(/^<\//)) indent = Math.max(0, indent - 1);
      const pad = '  '.repeat(indent);
      if (line.match(/^<[^/]/) && !line.match(/\/>$/)) indent++;
      return pad + line;
    })
    .join('\n');
}

// --- Main ---
console.log(`\x1b[36m--- AutoHotkey Stdio DBGp Test Harness ---\x1b[0m`);
console.log(`Exe:    ${AHK_EXE}`);
console.log(`Script: ${scriptPath}`);
console.log('');

const ahk = spawn(AHK_EXE, ['/Debug=stdio', scriptPath], {
  stdio: ['pipe', 'pipe', 'pipe'],
});

const parser = new DBGpParser();

ahk.stdout.on('data', (chunk) => {
  const messages = parser.feed(chunk);
  for (const xml of messages) {
    console.log(`\x1b[32m<< RESPONSE\x1b[0m`);
    console.log(formatXml(xml));
    console.log('');
    rl.prompt();
  }
});

ahk.stderr.on('data', (chunk) => {
  const text = chunk.toString().trim();
  if (text) {
    console.log(`\x1b[33m[stderr]\x1b[0m ${text}`);
  }
});

ahk.on('close', (code) => {
  console.log(`\n\x1b[36mAutoHotkey exited with code ${code}\x1b[0m`);
  process.exit(0);
});

ahk.on('error', (err) => {
  console.error(`Failed to start AutoHotkey: ${err.message}`);
  process.exit(1);
});

// --- Interactive command input ---
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  prompt: '\x1b[35mdbgp>\x1b[0m ',
});

// Wait a moment for the init message, then show prompt
setTimeout(() => rl.prompt(), 300);

rl.on('line', (line) => {
  const input = line.trim();
  if (!input) {
    rl.prompt();
    return;
  }

  if (input === 'quit' || input === 'exit') {
    console.log('Killing AutoHotkey...');
    ahk.kill();
    process.exit(0);
  }

  // Append transaction_id if not already present
  let command = input;
  if (!command.includes('-i ')) {
    command += ` -i ${transactionId++}`;
  }

  // Send command as null-terminated string
  const buf = Buffer.from(command + '\0', 'utf-8');
  ahk.stdin.write(buf);

  console.log(`\x1b[34m>> ${command}\x1b[0m`);
});

rl.on('close', () => {
  ahk.kill();
  process.exit(0);
});
