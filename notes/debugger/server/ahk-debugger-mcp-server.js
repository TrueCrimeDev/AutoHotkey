#!/usr/bin/env node

/**
 * AutoHotkey v2 Debugger MCP Server
 *
 * This MCP server intercepts DBGp (Xdebug Protocol) traffic from AutoHotkey v2
 * and provides tools/resources for caching, analyzing, and querying debug events.
 *
 * Usage:
 *   node ahk-debugger-mcp-server.js [--port 9002] [--cache-size 1000]
 *
 * Environment Variables:
 *   AHK_DEBUGGER_PORT - Port to listen on (default: 9002)
 *   AHK_DEBUGGER_FORWARD_HOST - Forward to real debugger (optional)
 *   AHK_DEBUGGER_FORWARD_PORT - Forward port (optional)
 */

const net = require('net');
const { EventEmitter } = require('events');
const xml2js = require('xml2js');

// ============================================================================
// EVENT CACHE - Stores all debug events with indexing
// ============================================================================

class DebugEventCache extends EventEmitter {
  constructor(maxSize = 1000) {
    super();
    this.events = [];
    this.maxSize = maxSize;
    this.byTransactionId = new Map();
    this.byCommand = new Map();
    this.breakpoints = new Map();
    this.stackSnapshots = [];
    this.errorEvents = [];
    this.variableSnapshots = [];
    this.startTime = Date.now();
  }

  addEvent(event) {
    // Enforce max size with FIFO eviction
    if (this.events.length >= this.maxSize) {
      const removed = this.events.shift();
      if (removed.transactionId) {
        this.byTransactionId.delete(removed.transactionId);
      }
    }

    this.events.push(event);

    // Index by transaction_id
    if (event.transactionId) {
      this.byTransactionId.set(event.transactionId, event);
    }

    // Index by command
    if (event.command) {
      if (!this.byCommand.has(event.command)) {
        this.byCommand.set(event.command, []);
      }
      this.byCommand.get(event.command).push(event);
    }

    // Track breakpoints
    if (event.command === 'breakpoint_set' || event.command === 'breakpoint_list') {
      if (event.breakpointId) {
        this.breakpoints.set(event.breakpointId, event);
      }
    }

    // Snapshot stack on breaks
    if (event.status === 'break') {
      this.stackSnapshots.push({
        timestamp: event.timestamp,
        depth: event.stackDepth,
        reason: event.reason,
        file: event.file,
        line: event.line,
        transactionId: event.transactionId
      });
    }

    // Track errors
    if (event.type === 'error' || event.status === 'error') {
      this.errorEvents.push(event);
    }

    // Snapshot variables on context_get
    if (event.command === 'context_get') {
      this.variableSnapshots.push({
        timestamp: event.timestamp,
        context: event.context,
        variables: event.variables,
        transactionId: event.transactionId
      });
    }

    this.emit('event', event);
  }

  getEventsByCommand(command) {
    return this.byCommand.get(command) || [];
  }

  getEventByTransactionId(id) {
    return this.byTransactionId.get(id);
  }

  getBreakpoints() {
    return Array.from(this.breakpoints.values());
  }

  getStackHistory() {
    return this.stackSnapshots;
  }

  getErrors() {
    return this.errorEvents;
  }

  getVariableSnapshots() {
    return this.variableSnapshots;
  }

  getStats() {
    return {
      totalEvents: this.events.length,
      uptime: Date.now() - this.startTime,
      commandCounts: Object.fromEntries(
        Array.from(this.byCommand.entries()).map(([cmd, events]) => [cmd, events.length])
      ),
      breakpointCount: this.breakpoints.size,
      errorCount: this.errorEvents.length,
      stackSnapshotCount: this.stackSnapshots.length
    };
  }

  clear() {
    this.events = [];
    this.byTransactionId.clear();
    this.byCommand.clear();
    this.breakpoints.clear();
    this.stackSnapshots = [];
    this.errorEvents = [];
    this.variableSnapshots = [];
  }
}

// ============================================================================
// DBGp PARSER - Parses Xdebug Protocol messages
// ============================================================================

class DBGpParser {
  constructor() {
    this.xmlParser = new xml2js.Parser({ explicitArray: false });
  }

  /**
   * Parse DBGp message format: "length\0<?xml...?>\0"
   */
  parseMessage(buffer) {
    const str = buffer.toString('utf8');
    const nullIndex = str.indexOf('\0');

    if (nullIndex === -1) {
      return null; // Incomplete message
    }

    const length = parseInt(str.substring(0, nullIndex));
    const xmlStart = nullIndex + 1;
    const xmlEnd = xmlStart + length;

    if (str.length < xmlEnd + 1) {
      return null; // Incomplete message
    }

    const xml = str.substring(xmlStart, xmlEnd);
    return {
      length,
      xml,
      raw: buffer.slice(0, xmlEnd + 1)
    };
  }

  /**
   * Parse XML response into structured event
   */
  async parseXML(xml) {
    try {
      const result = await this.xmlParser.parseStringPromise(xml);
      const response = result.response || result.init || result.stream;

      if (!response) {
        return { type: 'unknown', raw: xml };
      }

      const event = {
        type: Object.keys(result)[0],
        timestamp: Date.now(),
        command: response.$.command,
        transactionId: response.$.transaction_id,
        status: response.$.status,
        reason: response.$.reason,
        raw: xml
      };

      // Extract common attributes
      if (response.$.status) event.status = response.$.status;
      if (response.$.reason) event.reason = response.$.reason;
      if (response.$.depth) event.stackDepth = parseInt(response.$.depth);
      if (response.$.filename) event.file = response.$.filename;
      if (response.$.lineno) event.line = parseInt(response.$.lineno);
      if (response.$.id) event.breakpointId = response.$.id;
      if (response.$.context) event.context = response.$.context;

      // Parse properties/variables
      if (response.property) {
        event.variables = Array.isArray(response.property)
          ? response.property
          : [response.property];
      }

      // Parse stack
      if (response.stack) {
        event.stack = Array.isArray(response.stack)
          ? response.stack
          : [response.stack];
      }

      // Parse breakpoints
      if (response.breakpoint) {
        event.breakpoints = Array.isArray(response.breakpoint)
          ? response.breakpoint
          : [response.breakpoint];
      }

      return event;
    } catch (err) {
      return {
        type: 'parse_error',
        error: err.message,
        raw: xml
      };
    }
  }
}

// ============================================================================
// DBGp PROXY - Intercepts and forwards DBGp traffic
// ============================================================================

class DBGpProxy {
  constructor(listenPort = 9002, forwardHost = null, forwardPort = null) {
    this.listenPort = listenPort;
    this.forwardHost = forwardHost;
    this.forwardPort = forwardPort;
    this.cache = new DebugEventCache();
    this.parser = new DBGpParser();
    this.clients = new Map();
    this.server = null;
  }

  start() {
    return new Promise((resolve, reject) => {
      this.server = net.createServer((socket) => {
        this.handleConnection(socket);
      });

      this.server.listen(this.listenPort, () => {
        console.log(`[DBGp Proxy] Listening on port ${this.listenPort}`);
        if (this.forwardHost && this.forwardPort) {
          console.log(`[DBGp Proxy] Forwarding to ${this.forwardHost}:${this.forwardPort}`);
        }
        resolve();
      });

      this.server.on('error', reject);
    });
  }

  stop() {
    return new Promise((resolve) => {
      if (this.server) {
        this.server.close(resolve);
      } else {
        resolve();
      }
    });
  }

  handleConnection(socket) {
    const clientId = `${socket.remoteAddress}:${socket.remotePort}`;
    console.log(`[DBGp Proxy] Client connected: ${clientId}`);

    const client = {
      socket,
      id: clientId,
      buffer: Buffer.alloc(0),
      remoteSocket: null
    };

    this.clients.set(clientId, client);

    // Connect to remote debugger if forwarding
    if (this.forwardHost && this.forwardPort) {
      client.remoteSocket = net.createConnection(
        this.forwardPort,
        this.forwardHost,
        () => {
          console.log(`[DBGp Proxy] Connected to remote: ${this.forwardHost}:${this.forwardPort}`);
        }
      );

      client.remoteSocket.on('data', (data) => {
        this.handleRemoteData(client, data);
      });

      client.remoteSocket.on('error', (err) => {
        console.error(`[DBGp Proxy] Remote error: ${err.message}`);
      });

      client.remoteSocket.on('end', () => {
        console.log(`[DBGp Proxy] Remote disconnected`);
        socket.end();
      });
    }

    socket.on('data', (data) => {
      this.handleClientData(client, data);
    });

    socket.on('error', (err) => {
      console.error(`[DBGp Proxy] Client error: ${err.message}`);
    });

    socket.on('end', () => {
      console.log(`[DBGp Proxy] Client disconnected: ${clientId}`);
      this.clients.delete(clientId);
      if (client.remoteSocket) {
        client.remoteSocket.end();
      }
    });
  }

  async handleClientData(client, data) {
    // Append to buffer
    client.buffer = Buffer.concat([client.buffer, data]);

    // Try to parse complete messages
    while (client.buffer.length > 0) {
      const message = this.parser.parseMessage(client.buffer);

      if (!message) {
        break; // Incomplete message
      }

      // Parse and cache the event
      const event = await this.parser.parseXML(message.xml);
      this.cache.addEvent(event);

      console.log(`[DBGp Proxy] Received: ${event.command || event.type}`);

      // Forward to remote if connected
      if (client.remoteSocket) {
        client.remoteSocket.write(message.raw);
      }

      // Remove processed message from buffer
      client.buffer = client.buffer.slice(message.raw.length);
    }
  }

  async handleRemoteData(client, data) {
    // Parse and cache
    const message = this.parser.parseMessage(data);
    if (message) {
      const event = await this.parser.parseXML(message.xml);
      this.cache.addEvent(event);
      console.log(`[DBGp Proxy] Forwarding: ${event.command || event.type}`);
    }

    // Send to client
    client.socket.write(data);
  }

  getCache() {
    return this.cache;
  }
}

// ============================================================================
// MCP SERVER - Model Context Protocol interface
// ============================================================================

class DBGpMCPServer {
  constructor(proxy) {
    this.proxy = proxy;
    this.cache = proxy.getCache();
  }

  /**
   * MCP Tools - Functions that can be called
   */
  getTools() {
    return [
      {
        name: 'get_debug_events',
        description: 'Retrieve cached debug events with optional filtering',
        inputSchema: {
          type: 'object',
          properties: {
            command: {
              type: 'string',
              description: 'Filter by DBGp command (e.g., "breakpoint_set", "context_get")'
            },
            limit: {
              type: 'number',
              description: 'Maximum number of events to return (default: 100)'
            },
            offset: {
              type: 'number',
              description: 'Offset for pagination (default: 0)'
            }
          }
        }
      },
      {
        name: 'get_breakpoints',
        description: 'Get all breakpoints that have been set',
        inputSchema: { type: 'object', properties: {} }
      },
      {
        name: 'get_stack_history',
        description: 'Get stack snapshots from all break events',
        inputSchema: { type: 'object', properties: {} }
      },
      {
        name: 'get_errors',
        description: 'Get all error events',
        inputSchema: { type: 'object', properties: {} }
      },
      {
        name: 'get_variables',
        description: 'Get variable snapshots from context_get events',
        inputSchema: {
          type: 'object',
          properties: {
            limit: {
              type: 'number',
              description: 'Maximum snapshots to return'
            }
          }
        }
      },
      {
        name: 'get_stats',
        description: 'Get cache statistics and event counts',
        inputSchema: { type: 'object', properties: {} }
      },
      {
        name: 'clear_cache',
        description: 'Clear all cached events',
        inputSchema: { type: 'object', properties: {} }
      }
    ];
  }

  /**
   * MCP Resources - Data that can be read
   */
  getResources() {
    return [
      {
        uri: 'debug://events',
        name: 'All Debug Events',
        description: 'Complete list of all cached debug events',
        mimeType: 'application/json'
      },
      {
        uri: 'debug://breakpoints',
        name: 'Breakpoints',
        description: 'Current breakpoints',
        mimeType: 'application/json'
      },
      {
        uri: 'debug://stack-history',
        name: 'Stack History',
        description: 'Stack snapshots over time',
        mimeType: 'application/json'
      },
      {
        uri: 'debug://variables',
        name: 'Variables',
        description: 'Variable states from last break',
        mimeType: 'application/json'
      },
      {
        uri: 'debug://errors',
        name: 'Errors',
        description: 'All error events',
        mimeType: 'application/json'
      },
      {
        uri: 'debug://stats',
        name: 'Statistics',
        description: 'Cache statistics',
        mimeType: 'application/json'
      }
    ];
  }

  /**
   * Handle tool calls
   */
  async callTool(name, args) {
    switch (name) {
      case 'get_debug_events': {
        const command = args.command;
        const limit = args.limit || 100;
        const offset = args.offset || 0;

        let events = command
          ? this.cache.getEventsByCommand(command)
          : this.cache.events;

        events = events.slice(offset, offset + limit);
        return { events, count: events.length };
      }

      case 'get_breakpoints': {
        return { breakpoints: this.cache.getBreakpoints() };
      }

      case 'get_stack_history': {
        return { stackHistory: this.cache.getStackHistory() };
      }

      case 'get_errors': {
        return { errors: this.cache.getErrors() };
      }

      case 'get_variables': {
        const limit = args.limit || 50;
        const snapshots = this.cache.getVariableSnapshots().slice(-limit);
        return { variableSnapshots: snapshots };
      }

      case 'get_stats': {
        return this.cache.getStats();
      }

      case 'clear_cache': {
        this.cache.clear();
        return { message: 'Cache cleared' };
      }

      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  }

  /**
   * Handle resource reads
   */
  async readResource(uri) {
    switch (uri) {
      case 'debug://events':
        return JSON.stringify(this.cache.events, null, 2);

      case 'debug://breakpoints':
        return JSON.stringify(this.cache.getBreakpoints(), null, 2);

      case 'debug://stack-history':
        return JSON.stringify(this.cache.getStackHistory(), null, 2);

      case 'debug://variables': {
        const lastBreak = this.cache.events
          .reverse()
          .find(e => e.status === 'break');
        return JSON.stringify(lastBreak?.variables || {}, null, 2);
      }

      case 'debug://errors':
        return JSON.stringify(this.cache.getErrors(), null, 2);

      case 'debug://stats':
        return JSON.stringify(this.cache.getStats(), null, 2);

      default:
        throw new Error(`Unknown resource: ${uri}`);
    }
  }
}

// ============================================================================
// MAIN - Start the server
// ============================================================================

async function main() {
  const listenPort = parseInt(process.env.AHK_DEBUGGER_PORT || '9002');
  const forwardHost = process.env.AHK_DEBUGGER_FORWARD_HOST;
  const forwardPort = process.env.AHK_DEBUGGER_FORWARD_PORT
    ? parseInt(process.env.AHK_DEBUGGER_FORWARD_PORT)
    : null;

  const proxy = new DBGpProxy(listenPort, forwardHost, forwardPort);
  const mcpServer = new DBGpMCPServer(proxy);

  await proxy.start();

  // Simple HTTP interface for testing
  const http = require('http');
  const httpServer = http.createServer((req, res) => {
    res.setHeader('Content-Type', 'application/json');

    if (req.url === '/api/events') {
      res.end(JSON.stringify(proxy.getCache().events));
    } else if (req.url === '/api/stats') {
      res.end(JSON.stringify(proxy.getCache().getStats()));
    } else if (req.url === '/api/breakpoints') {
      res.end(JSON.stringify(proxy.getCache().getBreakpoints()));
    } else if (req.url === '/api/tools') {
      res.end(JSON.stringify(mcpServer.getTools()));
    } else {
      res.statusCode = 404;
      res.end(JSON.stringify({ error: 'Not found' }));
    }
  });

  httpServer.listen(9003, () => {
    console.log('[HTTP API] Listening on http://localhost:9003');
  });

  console.log('[MCP Server] Ready');
  console.log('Tools available:', mcpServer.getTools().map(t => t.name));
  console.log('Resources available:', mcpServer.getResources().map(r => r.uri));
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});

module.exports = { DBGpProxy, DBGpMCPServer, DebugEventCache, DBGpParser };
