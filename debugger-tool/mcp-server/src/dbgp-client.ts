/**
 * DBGp Client - Connects to AutoHotkey debugger via DBGp protocol
 */

import * as net from 'net';
import { EventEmitter } from 'events';

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

export class DBGpClient extends EventEmitter {
  private server: net.Server | null = null;
  private socket: net.Socket | null = null;
  private transactionId = 1;
  private port: number;
  private buffer = '';
  private connected = false;

  constructor(port: number = 9000) {
    super();
    this.port = port;
  }

  /**
   * Start listening for AutoHotkey connection
   */
  async listen(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.server = net.createServer((socket) => {
        this.socket = socket;
        this.connected = true;
        this.emit('connected');

        socket.on('data', (data) => this.handleData(data));
        socket.on('end', () => {
          this.connected = false;
          this.emit('disconnected');
        });
        socket.on('error', (err) => this.emit('error', err));
      });

      this.server.listen(this.port, '127.0.0.1', () => {
        this.emit('listening', this.port);
        resolve();
      });

      this.server.on('error', reject);
    });
  }

  /**
   * Handle incoming data from AutoHotkey
   */
  private handleData(data: Buffer): void {
    this.buffer += data.toString();

    // DBGp messages are null-terminated with length prefix
    while (true) {
      const nullIdx = this.buffer.indexOf('\0');
      if (nullIdx === -1) break;

      const message = this.buffer.substring(0, nullIdx);
      this.buffer = this.buffer.substring(nullIdx + 1);

      // Parse length prefix if present
      if (message.match(/^\d+\0/)) {
        const parts = message.split('\0', 2);
        if (parts.length === 2) {
          this.emit('message', parts[1]);
        }
      } else {
        this.emit('message', message);
      }
    }
  }

  /**
   * Send DBGp command
   */
  private async sendCommand(command: string): Promise<DebugResponse> {
    if (!this.socket || !this.connected) {
      throw new Error('Not connected to AutoHotkey debugger');
    }

    const tid = this.transactionId++;
    const fullCommand = `${command} -i ${tid}\0`;

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Command timeout'));
      }, 5000);

      const handler = (message: string) => {
        if (message.includes(`transaction_id="${tid}"`)) {
          clearTimeout(timeout);
          this.off('message', handler);
          resolve(this.parseResponse(message));
        }
      };

      this.on('message', handler);
      this.socket!.write(fullCommand);
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

  async run(): Promise<DebugResponse> {
    return this.sendCommand('run');
  }

  async stepInto(): Promise<DebugResponse> {
    return this.sendCommand('step_into');
  }

  async stepOver(): Promise<DebugResponse> {
    return this.sendCommand('step_over');
  }

  async stepOut(): Promise<DebugResponse> {
    return this.sendCommand('step_out');
  }

  async stop(): Promise<DebugResponse> {
    return this.sendCommand('stop');
  }

  async getStatus(): Promise<DebugResponse> {
    return this.sendCommand('status');
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
    if (this.socket) {
      this.socket.end();
      this.socket = null;
    }
    if (this.server) {
      this.server.close();
      this.server = null;
    }
    this.connected = false;
  }
}
