import * as net from 'net';
import { EventEmitter } from 'events';
import { DBGpFramer } from '@ahk/dbgp-protocol';

export interface Variable {
  name: string;
  fullname: string;
  type: string;
  value: string;
  children?: Variable[];
}

export interface StackFrame {
  level: number;
  type: string;
  filename: string;
  lineno: number;
  where?: string;
  cmdbegin?: string;
  cmdend?: string;
}

export class DBGpHandler extends EventEmitter {
  private server: net.Server | null = null;
  private socket: net.Socket | null = null;
  private framer = new DBGpFramer();
  private transactionId = 1;
  private pendingCommands: Map<number, { resolve: Function; reject: Function }> = new Map();
  private initData: any = null;

  constructor(private port: number, private commandTimeoutMs: number = 10000) {
    super();
  }

  async listen(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.server = net.createServer((socket) => {
        if (this.socket) {
          socket.destroy();
          return;
        }
        this.framer.reset();
        this.socket = socket;

        socket.on('data', (data) => { if (this.socket === socket) this.handleData(data); });
        socket.on('end', () => {
          if (this.socket === socket) this.disconnect(new Error('Debugger disconnected'));
        });
        socket.on('close', () => {
          if (this.socket === socket) this.disconnect(new Error('Debugger disconnected'));
        });
        socket.on('error', (err) => {
          if (this.socket !== socket) return;
          this.disconnect(err);
          this.emit('error', err);
        });
      });

      this.server.listen(this.port, '127.0.0.1', () => {
        resolve();
      });

      this.server.on('error', reject);
    });
  }

  private handleData(data: Buffer): void {
    try {
      for (const message of this.framer.push(data)) this.handleMessage(message);
    } catch (error) {
      this.disconnect(error as Error);
      this.emit('error', error);
    }
  }

  private disconnect(reason: Error): void {
    const socket = this.socket;
    this.socket = null;
    this.initData = null;
    this.framer.reset();
    for (const pending of this.pendingCommands.values()) pending.reject(reason);
    this.pendingCommands.clear();
    socket?.destroy();
    if (socket) this.emit('disconnected');
  }

  private handleMessage(xml: string): void {
    // Check for init message
    if (xml.includes('<init ')) {
      this.initData = this.parseXmlAttributes(xml, 'init');
      this.emit('connected', this.initData);
      return;
    }

    // Check for response
    if (xml.includes('<response ')) {
      const attrs = this.parseXmlAttributes(xml, 'response');
      const tid = parseInt(attrs.transaction_id, 10);

      const pending = this.pendingCommands.get(tid);
      if (pending) {
        this.pendingCommands.delete(tid);
        pending.resolve({ ...attrs, _raw: xml });
      }

      // Check if this is a break response (exception hit)
      if (attrs.status === 'break' && attrs.reason === 'exception') {
        this.emit('exception', { ...attrs, _raw: xml });
      }

      // Script stopped
      if (attrs.status === 'stopped') {
        this.emit('stopped', attrs);
      }
    }

    // Emit raw message for debugging
    this.emit('message', xml);
  }

  private parseXmlAttributes(xml: string, tagName: string): Record<string, string> {
    const attrs: Record<string, string> = {};
    const regex = new RegExp(`<${tagName}([^>]*)`, 'i');
    const match = xml.match(regex);

    if (match) {
      const attrStr = match[1];
      const attrRegex = /(\w+)="([^"]*)"/g;
      let attrMatch;
      while ((attrMatch = attrRegex.exec(attrStr)) !== null) {
        attrs[attrMatch[1]] = attrMatch[2];
      }
    }

    return attrs;
  }

  async sendCommand(command: string): Promise<any> {
    if (!this.socket) {
      throw new Error('Not connected');
    }

    const tid = this.transactionId++;
    const fullCommand = `${command} -i ${tid}\0`;

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingCommands.delete(tid);
        reject(new Error(`Command timeout: ${command}`));
      }, this.commandTimeoutMs);

      this.pendingCommands.set(tid, {
        resolve: (result: any) => {
          clearTimeout(timeout);
          resolve(result);
        },
        reject: (err: any) => {
          clearTimeout(timeout);
          this.pendingCommands.delete(tid);
          reject(err);
        }
      });

      try {
        this.socket!.write(fullCommand, error => {
          if (error) this.pendingCommands.get(tid)?.reject(error);
        });
      } catch (error) {
        this.pendingCommands.get(tid)?.reject(error);
      }
    });
  }

  // === Debug Commands ===

  async setExceptionBreakpoint(): Promise<any> {
    return this.sendCommand('breakpoint_set -t exception -x "*"');
  }

  async run(): Promise<any> {
    return this.sendCommand('run');
  }

  async stepInto(): Promise<any> {
    return this.sendCommand('step_into');
  }

  async getStackTrace(): Promise<StackFrame[]> {
    const response = await this.sendCommand('stack_get');
    return this.parseStackFrames(response._raw || '');
  }

  async getVariables(contextId: number, depth: number = 2): Promise<Variable[]> {
    const response = await this.sendCommand(`context_get -c ${contextId} -d ${depth}`);
    return this.parseProperties(response._raw || '');
  }

  async getProperty(name: string, depth: number = 2): Promise<Variable | null> {
    try {
      const encoded = Buffer.from(name).toString('base64');
      const response = await this.sendCommand(`property_get -n ${name} -d ${depth}`);
      const props = this.parseProperties(response._raw || '');
      return props[0] || null;
    } catch {
      return null;
    }
  }

  async getSource(file: string, beginLine: number, endLine: number): Promise<string> {
    try {
      const fileUri = `file:///${file.replace(/\\/g, '/')}`;
      const response = await this.sendCommand(`source -f ${fileUri} -b ${beginLine} -e ${endLine}`);

      // Extract base64 encoded source
      const match = response._raw?.match(/<source[^>]*>([^<]*)<\/source>/);
      if (match && match[1]) {
        return Buffer.from(match[1], 'base64').toString('utf-8');
      }
      return '';
    } catch {
      return '';
    }
  }

  async getStatus(): Promise<any> {
    return this.sendCommand('status');
  }

  async stop(): Promise<void> {
    try {
      await this.sendCommand('stop');
    } catch {
      // Ignore errors on stop
    }
  }

  // === Parsing Helpers ===

  private parseStackFrames(xml: string): StackFrame[] {
    const frames: StackFrame[] = [];
    const stackRegex = /<stack\s+([^>]*)\/?>/g;
    let match;

    while ((match = stackRegex.exec(xml)) !== null) {
      const attrs = this.parseAttributes(match[1]);
      frames.push({
        level: parseInt(attrs.level, 10) || 0,
        type: attrs.type || 'file',
        filename: decodeURIComponent(attrs.filename || '').replace('file:///', ''),
        lineno: parseInt(attrs.lineno, 10) || 0,
        where: attrs.where,
        cmdbegin: attrs.cmdbegin,
        cmdend: attrs.cmdend
      });
    }

    return frames;
  }

  private parseProperties(xml: string, depth: number = 0): Variable[] {
    const variables: Variable[] = [];

    // Match property elements (including self-closing and with children)
    const propRegex = /<property\s+([^>]*)(?:\/>|>([^]*?)<\/property>)/g;
    let match;

    while ((match = propRegex.exec(xml)) !== null) {
      const attrs = this.parseAttributes(match[1]);
      const content = match[2] || '';

      const variable: Variable = {
        name: attrs.name || '',
        fullname: attrs.fullname || attrs.name || '',
        type: attrs.type || 'undefined',
        value: ''
      };

      // Decode value
      if (content && !content.includes('<property')) {
        variable.value = Buffer.from(content.trim(), 'base64').toString('utf-8');
      } else if (attrs.type === 'object' || attrs.type === 'array') {
        variable.value = `[${attrs.classname || attrs.type}]`;
        // Parse nested properties
        if (content.includes('<property') && depth < 3) {
          variable.children = this.parseProperties(content, depth + 1);
        }
      }

      variables.push(variable);
    }

    return variables;
  }

  private parseAttributes(attrStr: string): Record<string, string> {
    const attrs: Record<string, string> = {};
    const regex = /(\w+)="([^"]*)"/g;
    let match;
    while ((match = regex.exec(attrStr)) !== null) {
      attrs[match[1]] = match[2];
    }
    return attrs;
  }

  close(): void {
    this.disconnect(new Error('Debugger connection closed'));
    if (this.server) {
      this.server.close();
      this.server = null;
    }
  }
}

