/**
 * DBGp Client - speaks DBGp to AutoHotkey over any stream pair
 * (TCP socket or a child process's stdio when launched with /Debug=stdio).
 */

import * as net from 'net';
import { EventEmitter } from 'events';
import { DbgpFrameParser, classifyPacket } from './dbgp-parser.js';

export interface DebugResponse {
  command: string;
  transaction_id: string;
  status?: string;
  reason?: string;
  [key: string]: any;
}

export interface Breakpoint {
  id: string;
  file: string;
  line: number;
  state?: string;
}

export interface Variable {
  name: string;
  fullname: string;
  type: string;
  value: string;
}

export interface StackFrame {
  level: number;
  type: string;
  filename: string;
  lineno: number;
  where?: string;
}

export interface ErrorInfo {
  error_type: string;
  message: string;
  file: string;
  line: number;
  source_context: Array<{ line: number; text: string; is_error_line?: boolean }>;
  stack_trace: StackFrame[];
  local_variables: Variable[];
  global_variables: Variable[];
  timestamp: number;
}

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

  /**
   * Parse XML response from AutoHotkey
   */
  private parseResponse(xml: string): DebugResponse {
    const response: DebugResponse = {
      command: '',
      transaction_id: ''
    };

    // Extract attributes from main response tag
    const responseMatch = xml.match(/<response([^>]*)>/);
    if (responseMatch) {
      const attrs = responseMatch[1];
      const attrRegex = /(\w+)="([^"]*)"/g;
      let match;
      while ((match = attrRegex.exec(attrs)) !== null) {
        response[match[1]] = match[2];
      }
    }

    // Store raw XML for further parsing
    response._raw = xml;

    return response;
  }

  /**
   * Extract property elements from XML
   */
  private parseProperties(xml: string): Variable[] {
    const variables: Variable[] = [];
    const propRegex = /<property([^>]*)>([^<]*)<\/property>/g;
    let match;

    while ((match = propRegex.exec(xml)) !== null) {
      const attrs = match[1];
      const value = match[2];

      const variable: any = {};
      const attrRegex = /(\w+)="([^"]*)"/g;
      let attrMatch;
      while ((attrMatch = attrRegex.exec(attrs)) !== null) {
        variable[attrMatch[1]] = attrMatch[2];
      }

      // Decode base64 value if present
      if (value) {
        variable.value = Buffer.from(value, 'base64').toString('utf-8');
      }

      variables.push(variable as Variable);
    }

    return variables;
  }

  /**
   * Extract stack frames from XML
   */
  private parseStack(xml: string): StackFrame[] {
    const frames: StackFrame[] = [];
    const stackRegex = /<stack([^>]*)\/>/g;
    let match;

    while ((match = stackRegex.exec(xml)) !== null) {
      const attrs = match[1];
      const frame: any = {};

      const attrRegex = /(\w+)="([^"]*)"/g;
      let attrMatch;
      while ((attrMatch = attrRegex.exec(attrs)) !== null) {
        const key = attrMatch[1];
        const val = attrMatch[2];
        frame[key] = key === 'level' || key === 'lineno' ? parseInt(val) : val;
      }

      frames.push(frame as StackFrame);
    }

    return frames;
  }

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

  // === Breakpoint Commands ===

  async setBreakpoint(file: string, line: number, condition?: string): Promise<Breakpoint> {
    let cmd = `breakpoint_set -t line -f file:///${file.replace(/\\/g, '/')} -n ${line}`;
    if (condition) {
      cmd += ` -condition ${Buffer.from(condition).toString('base64')}`;
    }

    const response = await this.sendCommand(cmd);
    return {
      id: response.id || '',
      file,
      line,
      state: response.state
    };
  }

  async removeBreakpoint(id: string): Promise<void> {
    await this.sendCommand(`breakpoint_remove -d ${id}`);
  }

  async listBreakpoints(): Promise<Breakpoint[]> {
    const response = await this.sendCommand('breakpoint_list');
    // Parse breakpoint list from XML
    const breakpoints: Breakpoint[] = [];
    const xml = response._raw || '';
    const bpRegex = /<breakpoint([^>]*)\/>/g;
    let match;

    while ((match = bpRegex.exec(xml)) !== null) {
      const attrs = match[1];
      const bp: any = {};

      const attrRegex = /(\w+)="([^"]*)"/g;
      let attrMatch;
      while ((attrMatch = attrRegex.exec(attrs)) !== null) {
        bp[attrMatch[1]] = attrMatch[2];
      }

      if (bp.id && bp.filename) {
        breakpoints.push({
          id: bp.id,
          file: bp.filename.replace('file:///', ''),
          line: parseInt(bp.lineno) || 0,
          state: bp.state
        });
      }
    }

    return breakpoints;
  }

  // === Variable Inspection ===

  async getVariables(contextId: number = 0): Promise<Variable[]> {
    const response = await this.sendCommand(`context_get -c ${contextId}`);
    return this.parseProperties(response._raw || '');
  }

  async evaluateExpression(expression: string): Promise<string> {
    const encoded = Buffer.from(expression).toString('base64');
    const response = await this.sendCommand(`eval -- ${encoded}`);

    const variables = this.parseProperties(response._raw || '');
    return variables.length > 0 ? variables[0].value : '';
  }

  // === Stack Inspection ===

  async getStackTrace(): Promise<StackFrame[]> {
    const response = await this.sendCommand('stack_get');
    return this.parseStack(response._raw || '');
  }

  // === Utility ===

  isConnected(): boolean {
    return this.connected;
  }

  async close(): Promise<void> {
    this.detach();
    if (this.server) {
      this.server.close();
      this.server = null;
    }
  }

  // === Error Queue Management ===

  /**
   * Queue an error for later retrieval
   */
  queueError(error: ErrorInfo): void {
    this.errorQueue.push(error);
    if (this.errorQueue.length > this.errorQueueMaxSize) {
      this.errorQueue.shift();
    }

    // Resolve any waiting promises
    if (this.errorWaiters.length > 0) {
      const waiter = this.errorWaiters.shift();
      waiter?.(error);
    }

    this.emit('error_captured', error);
  }

  /**
   * Wait for the next error (blocking)
   */
  async waitForError(timeoutMs: number = 30000): Promise<ErrorInfo | null> {
    // Check if there's already an error in queue
    if (this.errorQueue.length > 0) {
      return this.errorQueue.shift() || null;
    }

    // Wait for next error
    return new Promise((resolve) => {
      const timeout = setTimeout(() => {
        const idx = this.errorWaiters.indexOf(resolve as any);
        if (idx > -1) this.errorWaiters.splice(idx, 1);
        resolve(null);
      }, timeoutMs);

      this.errorWaiters.push((error) => {
        clearTimeout(timeout);
        resolve(error);
      });
    });
  }

  /**
   * Get all queued errors without removing them
   */
  getQueuedErrors(): ErrorInfo[] {
    return [...this.errorQueue];
  }

  /**
   * Clear the error queue
   */
  clearErrorQueue(): void {
    this.errorQueue = [];
  }

  /**
   * Capture error with full context - called when exception breakpoint hits
   */
  async captureErrorContext(file: string, line: number, errorType: string, message: string): Promise<ErrorInfo> {
    // Get source context by reading file
    const sourceContext = await this.getSourceContext(file, line, 5);

    // Get stack trace
    const stackTrace = await this.getStackTrace();

    // Get variables
    const localVars = await this.getVariables(0);
    const globalVars = await this.getVariables(1);

    const errorInfo: ErrorInfo = {
      error_type: errorType,
      message,
      file,
      line,
      source_context: sourceContext,
      stack_trace: stackTrace,
      local_variables: localVars,
      global_variables: globalVars,
      timestamp: Date.now(),
    };

    this.queueError(errorInfo);
    return errorInfo;
  }

  /**
   * Get source context from a file
   */
  async getSourceContext(file: string, line: number, radius: number = 3): Promise<Array<{ line: number; text: string; is_error_line?: boolean }>> {
    const fs = await import('fs/promises');
    try {
      const content = await fs.readFile(file, 'utf-8');
      const lines = content.split(/\r?\n/);
      const result: Array<{ line: number; text: string; is_error_line?: boolean }> = [];

      const start = Math.max(0, line - radius - 1);
      const end = Math.min(lines.length, line + radius);

      for (let i = start; i < end; i++) {
        result.push({
          line: i + 1,
          text: lines[i],
          is_error_line: i + 1 === line,
        });
      }

      return result;
    } catch {
      return [{ line, text: '(source unavailable)', is_error_line: true }];
    }
  }
}
