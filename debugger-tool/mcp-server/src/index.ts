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
import { DBGpClient, ErrorInfo } from './dbgp-client.js';
import { z } from 'zod';
import * as fs from 'fs/promises';

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

const CaptureErrorSchema = z.object({
  timeout: z.number().optional().describe('Timeout in milliseconds (default: 30000)'),
});

const AnalyzeErrorSchema = z.object({
  error: z.any().describe('Error object from capture_error'),
  use_api: z.boolean().optional().describe('If true, call Claude API directly (requires API key)'),
});

const ApplyFixSchema = z.object({
  file: z.string().describe('Path to the file'),
  line: z.number().describe('Line number to replace'),
  original: z.string().describe('Original text (for verification)'),
  replacement: z.string().describe('New text'),
});

const GetSourceContextSchema = z.object({
  file: z.string().describe('Path to the file'),
  line: z.number().describe('Center line number'),
  radius: z.number().optional().describe('Lines before/after (default: 5)'),
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

      // === LLM Debugger Tools ===
      {
        name: 'capture_error',
        description: 'Wait for the next error from the debugger and return full context including source, stack trace, and variables',
        inputSchema: {
          type: 'object',
          properties: {
            timeout: { type: 'number', description: 'Timeout in ms (default: 30000)' },
          },
          required: [],
        },
      },
      {
        name: 'analyze_error',
        description: 'Analyze an error and return structured data for LLM analysis or call Claude API directly',
        inputSchema: {
          type: 'object',
          properties: {
            error: { type: 'object', description: 'Error object from capture_error' },
            use_api: { type: 'boolean', description: 'If true, call Claude API directly' },
          },
          required: ['error'],
        },
      },
      {
        name: 'apply_fix',
        description: 'Apply a code fix directly to a file (auto-applies, no confirmation)',
        inputSchema: {
          type: 'object',
          properties: {
            file: { type: 'string', description: 'Path to the file' },
            line: { type: 'number', description: 'Line number to replace' },
            original: { type: 'string', description: 'Original text (for verification)' },
            replacement: { type: 'string', description: 'New text' },
          },
          required: ['file', 'line', 'original', 'replacement'],
        },
      },
      {
        name: 'get_source_context',
        description: 'Get source code lines around a specific line in a file',
        inputSchema: {
          type: 'object',
          properties: {
            file: { type: 'string', description: 'Path to the file' },
            line: { type: 'number', description: 'Center line number' },
            radius: { type: 'number', description: 'Lines before/after (default: 5)' },
          },
          required: ['file', 'line'],
        },
      },
      {
        name: 'list_errors',
        description: 'List all queued errors without removing them',
        inputSchema: { type: 'object', properties: {}, required: [] },
      },
      {
        name: 'clear_errors',
        description: 'Clear the error queue',
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

      // === LLM Debugger Tools ===

      case 'capture_error': {
        const params = CaptureErrorSchema.parse(args);
        const timeout = params.timeout || 30000;
        const error = await client.waitForError(timeout);

        if (!error) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({ status: 'timeout', message: 'No error captured within timeout period' }),
              },
            ],
          };
        }

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(error, null, 2),
            },
          ],
        };
      }

      case 'analyze_error': {
        const params = AnalyzeErrorSchema.parse(args);
        const error = params.error as ErrorInfo;
        const useApi = params.use_api || false;

        // Build analysis prompt
        const sourceLines = error.source_context
          .map((l) => `${l.is_error_line ? '>>> ' : '    '}${l.line}: ${l.text}`)
          .join('\n');

        const stackLines = error.stack_trace
          .map((f) => `  #${f.level} ${f.where || 'main'} at ${f.filename}:${f.lineno}`)
          .join('\n');

        const localVars = error.local_variables
          .map((v) => `  ${v.name} = ${v.value} (${v.type})`)
          .join('\n');

        const analysisPrompt = `Analyze this AutoHotkey v2 error:

ERROR: ${error.error_type}
MESSAGE: ${error.message}
FILE: ${error.file}
LINE: ${error.line}

SOURCE CONTEXT:
${sourceLines}

STACK TRACE:
${stackLines || '  (empty)'}

LOCAL VARIABLES:
${localVars || '  (none)'}

Provide:
1. Root cause diagnosis
2. Suggested fix (exact line replacement)
3. Confidence level (0-1)

Format response as JSON:
{
  "diagnosis": "...",
  "root_cause": "...",
  "suggested_fix": {
    "file": "${error.file}",
    "line": ${error.line},
    "original": "...",
    "replacement": "..."
  },
  "confidence": 0.0
}`;

        if (useApi) {
          // TODO: Call Claude API directly when API key is configured
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  status: 'api_not_configured',
                  message: 'Claude API integration not yet configured. Use use_api=false for client-side analysis.',
                  analysis_prompt: analysisPrompt,
                }),
              },
            ],
          };
        }

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                error,
                analysis_prompt: analysisPrompt,
                suggested_context: [error.file],
              }, null, 2),
            },
          ],
        };
      }

      case 'apply_fix': {
        const params = ApplyFixSchema.parse(args);

        try {
          // Read the file
          const content = await fs.readFile(params.file, 'utf-8');
          const lines = content.split(/\r?\n/);

          // Verify line exists
          if (params.line < 1 || params.line > lines.length) {
            return {
              content: [
                {
                  type: 'text',
                  text: JSON.stringify({
                    success: false,
                    error: `Line ${params.line} out of range (file has ${lines.length} lines)`,
                  }),
                },
              ],
              isError: true,
            };
          }

          // Verify original matches
          const actualLine = lines[params.line - 1];
          if (actualLine.trim() !== params.original.trim()) {
            return {
              content: [
                {
                  type: 'text',
                  text: JSON.stringify({
                    success: false,
                    error: 'Original line does not match',
                    expected: params.original,
                    actual: actualLine,
                  }),
                },
              ],
              isError: true,
            };
          }

          // Apply the fix
          lines[params.line - 1] = params.replacement;
          const newContent = lines.join('\n');
          await fs.writeFile(params.file, newContent, 'utf-8');

          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: true,
                  file: params.file,
                  line: params.line,
                  applied: params.replacement,
                }),
              },
            ],
          };
        } catch (err) {
          return {
            content: [
              {
                type: 'text',
                text: JSON.stringify({
                  success: false,
                  error: err instanceof Error ? err.message : String(err),
                }),
              },
            ],
            isError: true,
          };
        }
      }

      case 'get_source_context': {
        const params = GetSourceContextSchema.parse(args);
        const radius = params.radius || 5;
        const context = await client.getSourceContext(params.file, params.line, radius);

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({ file: params.file, line: params.line, context }, null, 2),
            },
          ],
        };
      }

      case 'list_errors': {
        const errors = client.getQueuedErrors();
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({ count: errors.length, errors }, null, 2),
            },
          ],
        };
      }

      case 'clear_errors': {
        client.clearErrorQueue();
        return {
          content: [{ type: 'text', text: 'Error queue cleared' }],
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
