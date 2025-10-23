# AutoHotkey v2 Debugger Interception - Practical Example

## Quick Start: 3-Step Setup

### Step 1: Start the MCP Proxy Server

```bash
# Install dependencies
npm install xml2js

# Start the proxy on port 9002
node ahk-debugger-mcp-server.js --port 9002

# Or with forwarding to real debugger
AHK_DEBUGGER_FORWARD_HOST=localhost \
AHK_DEBUGGER_FORWARD_PORT=9003 \
node ahk-debugger-mcp-server.js --port 9002
```

### Step 2: Configure AutoHotkey to Use Proxy

**Option A: Environment Variable (Recommended)**
```batch
set AHK_DEBUGGER_PROXY_HOST=localhost
set AHK_DEBUGGER_PROXY_PORT=9002
AutoHotkey.exe /Debug localhost:9002 your_script.ahk
```

**Option B: Direct Connection**
```batch
AutoHotkey.exe /Debug localhost:9002 your_script.ahk
```

### Step 3: Connect Your IDE

Configure your IDE (VS Code, PhpStorm, etc.) to connect to:
- **Host**: localhost
- **Port**: 9002 (or 9003 if forwarding)

---

## Example: Monitoring Debug Events

### Real-Time Event Monitoring

```javascript
// monitor-debugger.js
const net = require('net');
const { parseStringPromise } = require('xml2js');

class DebuggerMonitor {
  constructor(port = 9002) {
    this.port = port;
    this.events = [];
    this.breakpoints = new Map();
  }

  async start() {
    const server = net.createServer(async (socket) => {
      console.log('IDE connected');

      socket.on('data', async (data) => {
        const str = data.toString('utf8');
        console.log('Received:', str.substring(0, 100) + '...');

        // Parse DBGp message
        const nullIndex = str.indexOf('\0');
        if (nullIndex > -1) {
          const xml = str.substring(str.indexOf('<?xml'), nullIndex);
          try {
            const parsed = await parseStringPromise(xml);
            this.handleEvent(parsed);
          } catch (e) {
            console.error('Parse error:', e.message);
          }
        }
      });

      socket.on('end', () => {
        console.log('IDE disconnected');
      });
    });

    server.listen(this.port, () => {
      console.log(`Monitor listening on port ${this.port}`);
    });
  }

  handleEvent(parsed) {
    const response = parsed.response || parsed.init;
    if (!response) return;

    const event = {
      timestamp: new Date(),
      command: response.$.command,
      status: response.$.status,
      reason: response.$.reason,
      transactionId: response.$['transaction_id']
    };

    // Track breakpoints
    if (response.breakpoint) {
      const bp = response.breakpoint;
      const id = bp.$.id;
      this.breakpoints.set(id, {
        file: bp.$.filename,
        line: bp.$.lineno,
        state: bp.$.state
      });
      console.log(`[BREAKPOINT] ${bp.$.filename}:${bp.$.lineno}`);
    }

    // Track breaks
    if (event.status === 'break') {
      console.log(`[BREAK] Reason: ${event.reason}`);
      if (response.stack) {
        const stack = Array.isArray(response.stack)
          ? response.stack
          : [response.stack];
        stack.forEach((frame, i) => {
          console.log(`  [${i}] ${frame.$.where} @ ${frame.$.filename}:${frame.$.lineno}`);
        });
      }
    }

    this.events.push(event);
  }
}

// Start monitoring
const monitor = new DebuggerMonitor(9002);
monitor.start();
```

Run it:
```bash
node monitor-debugger.js
```

---

## Example: Caching Errors and Breakpoints

### Error Cache Implementation

```javascript
// error-cache.js
class DebuggerErrorCache {
  constructor() {
    this.errors = [];
    this.breakpoints = [];
    this.variables = new Map();
    this.stackTraces = [];
  }

  addError(event) {
    const error = {
      timestamp: new Date(),
      type: event.reason,
      file: event.filename,
      line: event.lineno,
      message: event.message,
      stack: event.stack
    };
    this.errors.push(error);
    console.log(`[ERROR] ${error.file}:${error.line} - ${error.message}`);
  }

  addBreakpoint(event) {
    this.breakpoints.push({
      id: event.id,
      file: event.filename,
      line: event.lineno,
      state: event.state,
      timestamp: new Date()
    });
  }

  captureVariables(event) {
    if (event.variables) {
      const vars = {};
      event.variables.forEach(v => {
        vars[v.$.name] = {
          type: v.$.type,
          value: v.$.value,
          children: v.$.children
        };
      });
      this.variables.set(event.transactionId, vars);
    }
  }

  captureStack(event) {
    if (event.stack) {
      this.stackTraces.push({
        timestamp: new Date(),
        transactionId: event.transactionId,
        frames: event.stack.map(f => ({
          level: f.$.level,
          type: f.$.type,
          filename: f.$.filename,
          lineno: f.$.lineno,
          where: f.$.where
        }))
      });
    }
  }

  getErrorReport() {
    return {
      totalErrors: this.errors.length,
      errors: this.errors,
      breakpoints: this.breakpoints,
      stackTraces: this.stackTraces,
      generatedAt: new Date()
    };
  }

  exportJSON(filename) {
    const fs = require('fs');
    fs.writeFileSync(filename, JSON.stringify(this.getErrorReport(), null, 2));
    console.log(`Report exported to ${filename}`);
  }
}

module.exports = DebuggerErrorCache;
```

---

## Example: Integration with VS Code

### VS Code Extension Configuration

```json
{
  "launch": {
    "version": "0.2.0",
    "configurations": [
      {
        "name": "AutoHotkey with Proxy",
        "type": "php",
        "request": "launch",
        "port": 9002,
        "pathMapping": {
          "/": "${workspaceFolder}/"
        },
        "xdebugSettings": {
          "max_data": 65535,
          "show_hidden": 1,
          "max_children": 100
        }
      }
    ]
  }
}
```

---

## Example: Real-Time Slack Notifications

### Notify on Breakpoints

```javascript
// slack-notifier.js
const axios = require('axios');

class SlackNotifier {
  constructor(webhookUrl) {
    this.webhookUrl = webhookUrl;
  }

  async notifyBreakpoint(event) {
    const message = {
      text: `🔴 Debugger Breakpoint Hit`,
      blocks: [
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: `*File:* \`${event.filename}:${event.lineno}\`\n*Reason:* ${event.reason}`
          }
        },
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: `*Time:* ${new Date().toISOString()}`
          }
        }
      ]
    };

    try {
      await axios.post(this.webhookUrl, message);
    } catch (e) {
      console.error('Slack notification failed:', e.message);
    }
  }

  async notifyError(event) {
    const message = {
      text: `❌ Debugger Error`,
      blocks: [
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: `*Error:* ${event.message}\n*File:* \`${event.filename}:${event.lineno}\``
          }
        }
      ]
    };

    try {
      await axios.post(this.webhookUrl, message);
    } catch (e) {
      console.error('Slack notification failed:', e.message);
    }
  }
}

module.exports = SlackNotifier;
```

---

## Example: Database Logging

### Store Debug Events in SQLite

```javascript
// db-logger.js
const sqlite3 = require('sqlite3').verbose();

class DebuggerDBLogger {
  constructor(dbPath = 'debugger_events.db') {
    this.db = new sqlite3.Database(dbPath);
    this.initDB();
  }

  initDB() {
    this.db.serialize(() => {
      this.db.run(`
        CREATE TABLE IF NOT EXISTS events (
          id INTEGER PRIMARY KEY,
          timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
          type TEXT,
          command TEXT,
          status TEXT,
          reason TEXT,
          filename TEXT,
          lineno INTEGER,
          data TEXT
        )
      `);

      this.db.run(`
        CREATE TABLE IF NOT EXISTS breakpoints (
          id INTEGER PRIMARY KEY,
          bp_id TEXT UNIQUE,
          filename TEXT,
          lineno INTEGER,
          state TEXT,
          hit_count INTEGER DEFAULT 0,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      `);

      this.db.run(`
        CREATE TABLE IF NOT EXISTS errors (
          id INTEGER PRIMARY KEY,
          timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
          filename TEXT,
          lineno INTEGER,
          message TEXT,
          stack TEXT
        )
      `);
    });
  }

  logEvent(event) {
    this.db.run(
      `INSERT INTO events (type, command, status, reason, filename, lineno, data)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [
        event.type,
        event.command,
        event.status,
        event.reason,
        event.filename,
        event.lineno,
        JSON.stringify(event)
      ]
    );
  }

  logBreakpoint(bp) {
    this.db.run(
      `INSERT OR REPLACE INTO breakpoints (bp_id, filename, lineno, state)
       VALUES (?, ?, ?, ?)`,
      [bp.id, bp.filename, bp.lineno, bp.state]
    );
  }

  logError(error) {
    this.db.run(
      `INSERT INTO errors (filename, lineno, message, stack)
       VALUES (?, ?, ?, ?)`,
      [error.filename, error.lineno, error.message, JSON.stringify(error.stack)]
    );
  }

  getErrorStats() {
    return new Promise((resolve, reject) => {
      this.db.all(
        `SELECT filename, COUNT(*) as count FROM errors GROUP BY filename ORDER BY count DESC`,
        (err, rows) => {
          if (err) reject(err);
          else resolve(rows);
        }
      );
    });
  }

  close() {
    this.db.close();
  }
}

module.exports = DebuggerDBLogger;
```

---

## Example: Complete Integration

### All-in-One Debugger Interceptor

```javascript
// complete-interceptor.js
const net = require('net');
const { parseStringPromise } = require('xml2js');
const DebuggerErrorCache = require('./error-cache');
const SlackNotifier = require('./slack-notifier');
const DebuggerDBLogger = require('./db-logger');

class CompleteDebuggerInterceptor {
  constructor(options = {}) {
    this.port = options.port || 9002;
    this.forwardHost = options.forwardHost;
    this.forwardPort = options.forwardPort;
    this.slackWebhook = options.slackWebhook;

    this.cache = new DebuggerErrorCache();
    this.dbLogger = new DebuggerDBLogger(options.dbPath || 'debugger.db');
    this.slack = this.slackWebhook ? new SlackNotifier(this.slackWebhook) : null;
  }

  async start() {
    const server = net.createServer((ideSocket) => {
      console.log('[INTERCEPTOR] IDE connected');

      let debuggerSocket = null;

      // If forwarding, connect to real debugger
      if (this.forwardHost && this.forwardPort) {
        debuggerSocket = net.createConnection(
          this.forwardPort,
          this.forwardHost,
          () => {
            console.log('[INTERCEPTOR] Connected to real debugger');
          }
        );

        debuggerSocket.on('data', (data) => {
          // Log and forward to IDE
          this.logData('DEBUGGER->IDE', data);
          ideSocket.write(data);
        });

        debuggerSocket.on('error', (err) => {
          console.error('[INTERCEPTOR] Debugger error:', err);
        });
      }

      ideSocket.on('data', async (data) => {
        // Log and parse
        this.logData('IDE->DEBUGGER', data);
        await this.processData(data);

        // Forward to real debugger if connected
        if (debuggerSocket) {
          debuggerSocket.write(data);
        }
      });

      ideSocket.on('end', () => {
        console.log('[INTERCEPTOR] IDE disconnected');
        if (debuggerSocket) debuggerSocket.end();
      });

      ideSocket.on('error', (err) => {
        console.error('[INTERCEPTOR] IDE error:', err);
      });
    });

    server.listen(this.port, () => {
      console.log(`[INTERCEPTOR] Listening on port ${this.port}`);
    });
  }

  async processData(data) {
    const str = data.toString('utf8');
    const nullIndex = str.indexOf('\0');

    if (nullIndex > -1) {
      const xmlStart = str.indexOf('<?xml');
      if (xmlStart > -1) {
        const xml = str.substring(xmlStart, nullIndex);
        try {
          const parsed = await parseStringPromise(xml);
          await this.handleParsedEvent(parsed);
        } catch (e) {
          console.error('[INTERCEPTOR] Parse error:', e.message);
        }
      }
    }
  }

  async handleParsedEvent(parsed) {
    const response = parsed.response || parsed.init;
    if (!response) return;

    const event = {
      timestamp: new Date(),
      command: response.$.command,
      status: response.$.status,
      reason: response.$.reason,
      transactionId: response.$['transaction_id'],
      filename: response.$.filename,
      lineno: response.$.lineno
    };

    // Log to database
    this.dbLogger.logEvent(event);

    // Handle breakpoints
    if (response.breakpoint) {
      const bp = response.breakpoint;
      this.cache.addBreakpoint(bp);
      this.dbLogger.logBreakpoint(bp);

      if (this.slack) {
        await this.slack.notifyBreakpoint({
          filename: bp.$.filename,
          lineno: bp.$.lineno,
          reason: event.reason
        });
      }
    }

    // Handle errors
    if (event.status === 'error' || event.reason === 'error') {
      this.cache.addError(event);
      this.dbLogger.logError(event);

      if (this.slack) {
        await this.slack.notifyError(event);
      }
    }

    // Capture variables and stack
    this.cache.captureVariables(event);
    this.cache.captureStack(event);
  }

  logData(direction, data) {
    const str = data.toString('utf8');
    console.log(`[${direction}] ${str.substring(0, 80)}...`);
  }
}

// Start
const interceptor = new CompleteDebuggerInterceptor({
  port: 9002,
  forwardHost: 'localhost',
  forwardPort: 9003,
  slackWebhook: process.env.SLACK_WEBHOOK_URL,
  dbPath: 'debugger_events.db'
});

interceptor.start();
```

Run it:
```bash
SLACK_WEBHOOK_URL=https://hooks.slack.com/... node complete-interceptor.js
```

---

## Troubleshooting

### Issue: "Connection refused"
- Ensure MCP server is running: `node ahk-debugger-mcp-server.js`
- Check port is not in use: `netstat -an | grep 9002`

### Issue: "No events captured"
- Verify environment variables are set correctly
- Check AutoHotkey is compiled with `CONFIG_DEBUGGER`
- Ensure `/Debug` flag is passed to AutoHotkey

### Issue: "XML parse errors"
- Some DBGp messages may not be valid XML
- Add error handling in `parseStringPromise` calls
- Log raw data for debugging

### Issue: "Forwarding not working"
- Verify real debugger is listening on specified port
- Check firewall rules
- Test connection: `telnet localhost 9003`

---

## Performance Considerations

1. **Event Cache Size**: Default 1000 events, adjust with `--cache-size`
2. **Database Indexing**: Add indexes on frequently queried columns
3. **Slack Rate Limiting**: Implement backoff for high-frequency events
4. **Memory Usage**: Monitor with `process.memoryUsage()`

---

## Next Steps

1. Modify AutoHotkey source to add logging hooks
2. Deploy MCP server to production
3. Integrate with your monitoring/alerting system
4. Build custom dashboards for debug event visualization
