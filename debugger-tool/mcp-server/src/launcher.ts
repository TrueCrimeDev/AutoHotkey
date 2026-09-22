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
