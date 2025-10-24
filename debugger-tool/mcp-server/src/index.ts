#!/usr/bin/env node

/**
 * MCP Server for AutoHotkey v2 Debugging
 *
 * Connects AI tools (Cursor, Claude Desktop, etc.) to AutoHotkey debugger
 * via Model Context Protocol (MCP) and Debug Adapter Protocol (DBGp).
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { DBGpClient } from './dbgp-client.js';
import { z } from 'zod';

const client = new DBGpClient(9000);
const server = new Server(
  {
    name: 'mcp-autohotkey-debug',
    version: '0.1.0',
  },
  {
    capabilities: {
      tools: {},
      resources: {},
    },
  }
);

// === Tool Schemas ===

const SetBreakpointSchema = z.object({
  file: z.string().describe('File path'),
  line: z.number().describe('Line number'),
  condition: z.string().optional().describe('Optional condition expression'),
});

const RemoveBreakpointSchema = z.object({
  id: z.string().describe('Breakpoint ID'),
});

const EvaluateSchema = z.object({
  expression: z.string().describe('Expression to evaluate'),
});

// === MCP Tools ===

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      // Debug Control
      {
        name: 'debug_run',
        description: 'Continue execution until next breakpoint or end',
        inputSchema: { type: 'object', properties: {}, required: [] },
      },
      {
        name: 'debug_step_into',
        description: 'Step into function (line by line, enter functions)',
        inputSchema: { type: 'object', properties: {}, required: [] },
      },
      {
        name: 'debug_step_over',
        description: 'Step over function (line by line, skip functions)',
        inputSchema: { type: 'object', properties: {}, required: [] },
      },
      {
        name: 'debug_step_out',
        description: 'Step out of current function',
        inputSchema: { type: 'object', properties: {}, required: [] },
      },
      {
        name: 'debug_stop',
        description: 'Stop debug session',
        inputSchema: { type: 'object', properties: {}, required: [] },
      },
      {
        name: 'debug_status',
        description: 'Get current debug session status',
        inputSchema: { type: 'object', properties: {}, required: [] },
      },

      // Breakpoints
      {
        name: 'breakpoint_set',
        description: 'Set a breakpoint at file:line with optional condition',
        inputSchema: {
          type: 'object',
          properties: {
            file: { type: 'string', description: 'File path' },
            line: { type: 'number', description: 'Line number' },
            condition: { type: 'string', description: 'Optional condition' },
          },
          required: ['file', 'line'],
        },
      },
      {
        name: 'breakpoint_remove',
        description: 'Remove a breakpoint by ID',
        inputSchema: {
          type: 'object',
          properties: {
            id: { type: 'string', description: 'Breakpoint ID' },
          },
          required: ['id'],
        },
      },
      {
        name: 'breakpoint_list',
        description: 'List all breakpoints',
        inputSchema: { type: 'object', properties: {}, required: [] },
      },

      // Variables
      {
        name: 'variables_get',
        description: 'Get all variables in current scope',
        inputSchema: {
          type: 'object',
          properties: {
            context: {
              type: 'number',
              description: 'Context ID (0=local, 1=global)',
              default: 0,
            },
          },
          required: [],
        },
      },
      {
        name: 'evaluate',
        description: 'Evaluate an expression in current context',
        inputSchema: {
          type: 'object',
          properties: {
            expression: { type: 'string', description: 'Expression to evaluate' },
          },
          required: ['expression'],
        },
      },

      // Stack
      {
        name: 'stack_trace',
        description: 'Get current call stack',
        inputSchema: { type: 'object', properties: {}, required: [] },
      },
    ],
  };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (!client.isConnected()) {
    return {
      content: [
        {
          type: 'text',
          text: 'Error: Not connected to AutoHotkey debugger. Start AutoHotkey with /Debug flag.',
        },
      ],
    };
  }

  try {
    switch (name) {
      // Debug Control
      case 'debug_run': {
        const response = await client.run();
        return {
          content: [
            {
              type: 'text',
              text: `Execution continued. Status: ${response.status}, Reason: ${response.reason}`,
            },
          ],
        };
      }

      case 'debug_step_into': {
        const response = await client.stepInto();
        return {
          content: [
            {
              type: 'text',
              text: `Stepped into. Status: ${response.status}, Line: ${response.lineno || 'unknown'}`,
            },
          ],
        };
      }

      case 'debug_step_over': {
        const response = await client.stepOver();
        return {
          content: [
            {
              type: 'text',
              text: `Stepped over. Status: ${response.status}, Line: ${response.lineno || 'unknown'}`,
            },
          ],
        };
      }

      case 'debug_step_out': {
        const response = await client.stepOut();
        return {
          content: [
            {
              type: 'text',
              text: `Stepped out. Status: ${response.status}`,
            },
          ],
        };
      }

      case 'debug_stop': {
        await client.stop();
        return {
          content: [{ type: 'text', text: 'Debug session stopped' }],
        };
      }

      case 'debug_status': {
        const response = await client.getStatus();
        return {
          content: [
            {
              type: 'text',
              text: `Status: ${response.status}, Reason: ${response.reason || 'N/A'}`,
            },
          ],
        };
      }

      // Breakpoints
      case 'breakpoint_set': {
        const params = SetBreakpointSchema.parse(args);
        const bp = await client.setBreakpoint(params.file, params.line, params.condition);
        return {
          content: [
            {
              type: 'text',
              text: `Breakpoint set: ID=${bp.id}, ${bp.file}:${bp.line}`,
            },
          ],
        };
      }

      case 'breakpoint_remove': {
        const params = RemoveBreakpointSchema.parse(args);
        await client.removeBreakpoint(params.id);
        return {
          content: [{ type: 'text', text: `Breakpoint ${params.id} removed` }],
        };
      }

      case 'breakpoint_list': {
        const breakpoints = await client.listBreakpoints();
        const list = breakpoints
          .map((bp) => `  ${bp.id}: ${bp.file}:${bp.line} (${bp.state})`)
          .join('\n');
        return {
          content: [
            {
              type: 'text',
              text: `Breakpoints (${breakpoints.length}):\n${list || '  (none)'}`,
            },
          ],
        };
      }

      // Variables
      case 'variables_get': {
        const context = (args as any).context || 0;
        const variables = await client.getVariables(context);
        const list = variables
          .map((v) => `  ${v.name} = ${v.value} (${v.type})`)
          .join('\n');
        return {
          content: [
            {
              type: 'text',
              text: `Variables in context ${context}:\n${list || '  (none)'}`,
            },
          ],
        };
      }

      case 'evaluate': {
        const params = EvaluateSchema.parse(args);
        const result = await client.evaluateExpression(params.expression);
        return {
          content: [
            {
              type: 'text',
              text: `${params.expression} = ${result}`,
            },
          ],
        };
      }

      // Stack
      case 'stack_trace': {
        const stack = await client.getStackTrace();
        const trace = stack
          .map((frame) => `  #${frame.level} ${frame.where || 'main'} at ${frame.filename}:${frame.lineno}`)
          .join('\n');
        return {
          content: [
            {
              type: 'text',
              text: `Call Stack:\n${trace || '  (empty)'}`,
            },
          ],
        };
      }

      default:
        return {
          content: [{ type: 'text', text: `Unknown tool: ${name}` }],
          isError: true,
        };
    }
  } catch (error) {
    return {
      content: [
        {
          type: 'text',
          text: `Error: ${error instanceof Error ? error.message : String(error)}`,
        },
      ],
      isError: true,
    };
  }
});

// === MCP Resources ===

server.setRequestHandler(ListResourcesRequestSchema, async () => {
  return {
    resources: [
      {
        uri: 'ahk://breakpoints',
        name: 'Current Breakpoints',
        description: 'List of all active breakpoints',
        mimeType: 'text/plain',
      },
      {
        uri: 'ahk://variables',
        name: 'Current Variables',
        description: 'Variables in current scope',
        mimeType: 'text/plain',
      },
      {
        uri: 'ahk://stack',
        name: 'Call Stack',
        description: 'Current call stack trace',
        mimeType: 'text/plain',
      },
      {
        uri: 'ahk://status',
        name: 'Debug Status',
        description: 'Current debug session status',
        mimeType: 'text/plain',
      },
    ],
  };
});

server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
  const uri = request.params.uri;

  if (!client.isConnected()) {
    return {
      contents: [
        {
          uri,
          mimeType: 'text/plain',
          text: 'Not connected to AutoHotkey debugger',
        },
      ],
    };
  }

  try {
    switch (uri) {
      case 'ahk://breakpoints': {
        const breakpoints = await client.listBreakpoints();
        const text = breakpoints
          .map((bp) => `${bp.id}: ${bp.file}:${bp.line} (${bp.state})`)
          .join('\n') || '(no breakpoints)';
        return {
          contents: [{ uri, mimeType: 'text/plain', text }],
        };
      }

      case 'ahk://variables': {
        const variables = await client.getVariables(0);
        const text = variables
          .map((v) => `${v.name} = ${v.value} (${v.type})`)
          .join('\n') || '(no variables)';
        return {
          contents: [{ uri, mimeType: 'text/plain', text }],
        };
      }

      case 'ahk://stack': {
        const stack = await client.getStackTrace();
        const text = stack
          .map((f) => `#${f.level} ${f.where || 'main'} at ${f.filename}:${f.lineno}`)
          .join('\n') || '(empty stack)';
        return {
          contents: [{ uri, mimeType: 'text/plain', text }],
        };
      }

      case 'ahk://status': {
        const response = await client.getStatus();
        const text = `Status: ${response.status}\nReason: ${response.reason || 'N/A'}`;
        return {
          contents: [{ uri, mimeType: 'text/plain', text }],
        };
      }

      default:
        return {
          contents: [
            {
              uri,
              mimeType: 'text/plain',
              text: `Unknown resource: ${uri}`,
            },
          ],
        };
    }
  } catch (error) {
    return {
      contents: [
        {
          uri,
          mimeType: 'text/plain',
          text: `Error: ${error instanceof Error ? error.message : String(error)}`,
        },
      ],
    };
  }
});

// === Server Lifecycle ===

async function main() {
  console.error('Starting MCP AutoHotkey Debug Server...');

  // Start listening for AutoHotkey
  await client.listen();
  console.error(`Listening for AutoHotkey on port 9000`);
  console.error('Start AutoHotkey with: AutoHotkey.exe /Debug your_script.ahk');

  client.on('connected', () => {
    console.error('AutoHotkey connected!');
  });

  client.on('disconnected', () => {
    console.error('AutoHotkey disconnected');
  });

  client.on('error', (err) => {
    console.error('DBGp Error:', err);
  });

  // Start MCP server
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('MCP Server ready for AI tool connection');
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
