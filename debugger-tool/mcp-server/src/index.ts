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
import * as path from 'path';
import Anthropic from '@anthropic-ai/sdk';

const client = new DBGpClient(9000);

// === Claude API (lazy init) ===

let anthropicClient: Anthropic | null = null;

function getAnthropicClient(): Anthropic {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error('ANTHROPIC_API_KEY environment variable not set');
  if (!anthropicClient) anthropicClient = new Anthropic({ apiKey });
  return anthropicClient;
}

// === Variable Watch State ===

interface WatchEntry {
  name: string;
  lastValue: string | null;
  lastType: string | null;
}

const watchList: Map<string, WatchEntry> = new Map();
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

const DebugCommandSchema = z.object({
  command: z.string().describe('Raw DBGp command without transaction id, for example: feature_get -n language_name'),
});

const SourceOutlineSchema = z.object({
  file: z.string().describe('Path to the AutoHotkey source file'),
});

const WatchAddSchema = z.object({
  name: z.string().describe('Variable name or expression to watch'),
});

const WatchRemoveSchema = z.object({
  name: z.string().describe('Variable name or expression to remove'),
});

const WorkspaceSymbolsSchema = z.object({
  root: z.string().optional().describe('Workspace root to scan (defaults to current working directory)'),
  query: z.string().optional().describe('Optional case-insensitive symbol filter'),
  max_results: z.number().optional().describe('Maximum symbols to return (default: 200)'),
});

type SourceSymbol = {
  kind: 'function' | 'class' | 'hotkey' | 'label';
  name: string;
  line: number;
  text: string;
  file?: string;
};

const AHK_EXTENSIONS = new Set(['.ahk', '.ah2']);

async function getSourceOutline(file: string): Promise<SourceSymbol[]> {
  const content = await fs.readFile(file, 'utf-8');
  const lines = content.split(/\r?\n/);
  const symbols: SourceSymbol[] = [];
  const controlFlow = new Set(['if', 'while', 'for', 'loop', 'switch', 'catch', 'try', 'else']);

  lines.forEach((rawLine, idx) => {
    const lineNo = idx + 1;
    const line = rawLine.trim();
    if (!line || line.startsWith(';'))
      return;

    const classMatch = line.match(/^class\s+([A-Za-z_]\w*)\b/);
    if (classMatch) {
      symbols.push({ kind: 'class', name: classMatch[1], line: lineNo, text: rawLine });
      return;
    }

    const fnMatch = line.match(/^([A-Za-z_]\w*)\s*\(([^)]*)\)\s*(\{|=>|$)/);
    if (fnMatch && !controlFlow.has(fnMatch[1].toLowerCase())) {
      symbols.push({ kind: 'function', name: fnMatch[1], line: lineNo, text: rawLine });
      return;
    }

    const hotkeyMatch = line.match(/^([^;\s][^:]*?)::/);
    if (hotkeyMatch) {
      symbols.push({ kind: 'hotkey', name: hotkeyMatch[1].trim(), line: lineNo, text: rawLine });
      return;
    }

    const labelMatch = line.match(/^([A-Za-z_]\w*)\s*:\s*(?:;.*)?$/);
    if (labelMatch && labelMatch[1].toLowerCase() !== 'case' && labelMatch[1].toLowerCase() !== 'default') {
      symbols.push({ kind: 'label', name: labelMatch[1], line: lineNo, text: rawLine });
    }
  });

  return symbols;
}

async function listAhkFiles(root: string, maxFiles: number): Promise<string[]> {
  const files: string[] = [];
  const skipDirs = new Set(['.git', 'node_modules', 'build', 'dist', 'bin_debug', 'build_mingw']);

  const walk = async (dir: string): Promise<void> => {
    if (files.length >= maxFiles)
      return;
    const entries = await fs.readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (files.length >= maxFiles)
        return;
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (!skipDirs.has(entry.name))
          await walk(fullPath);
        continue;
      }
      if (entry.isFile() && AHK_EXTENSIONS.has(path.extname(entry.name).toLowerCase()))
        files.push(fullPath);
    }
  };

  await walk(root);
  return files;
}

async function getWorkspaceSymbols(root: string, query = '', maxResults = 200): Promise<SourceSymbol[]> {
  const files = await listAhkFiles(root, Math.max(maxResults * 2, 500));
  const needle = query.trim().toLowerCase();
  const symbols: SourceSymbol[] = [];

  for (const file of files) {
    if (symbols.length >= maxResults)
      break;
    const outline = await getSourceOutline(file);
    for (const symbol of outline) {
      if (symbols.length >= maxResults)
        break;
      if (!needle || symbol.name.toLowerCase().includes(needle)) {
        symbols.push({
          ...symbol,
          file,
        });
      }
    }
  }

  return symbols;
}

// === Watch Helpers ===

interface WatchSnapshot {
  name: string;
  value: string;
  previous: string | null;
  changed: boolean;
}

async function snapshotWatches(): Promise<WatchSnapshot[]> {
  if (watchList.size === 0 || !client.isConnected()) return [];

  const snapshots: WatchSnapshot[] = [];
  for (const [name, entry] of watchList) {
    let value: string;
    try {
      value = await client.evaluateExpression(name);
    } catch {
      value = '<error>';
    }
    if (!value && value !== '') value = '<undefined>';

    const changed = entry.lastValue !== null && entry.lastValue !== value;
    const previous = entry.lastValue;

    entry.lastValue = value;
    entry.lastType = typeof value;

    snapshots.push({ name, value, previous, changed });
  }
  return snapshots;
}

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
      {
        name: 'debug_command',
        description: 'Send a raw DBGp command and return parsed attributes plus raw XML',
        inputSchema: {
          type: 'object',
          properties: {
            command: { type: 'string', description: 'DBGp command without transaction id' },
          },
          required: ['command'],
        },
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
        name: 'source_outline',
        description: 'Extract classes, functions, hotkeys, and labels from an AutoHotkey source file',
        inputSchema: {
          type: 'object',
          properties: {
            file: { type: 'string', description: 'Path to the AutoHotkey source file' },
          },
          required: ['file'],
        },
      },
      {
        name: 'workspace_symbols',
        description: 'Scan workspace AutoHotkey files and return symbol index (optionally filtered)',
        inputSchema: {
          type: 'object',
          properties: {
            root: { type: 'string', description: 'Workspace root (defaults to current working directory)' },
            query: { type: 'string', description: 'Optional symbol name filter' },
            max_results: { type: 'number', description: 'Maximum symbols to return (default: 200)' },
          },
          required: [],
        },
      },
      // Watch / Change Notifications
      {
        name: 'watch_add',
        description: 'Add a variable or expression to the watch list for change tracking during stepping',
        inputSchema: {
          type: 'object',
          properties: {
            name: { type: 'string', description: 'Variable name or expression to watch' },
          },
          required: ['name'],
        },
      },
      {
        name: 'watch_remove',
        description: 'Remove a variable or expression from the watch list',
        inputSchema: {
          type: 'object',
          properties: {
            name: { type: 'string', description: 'Variable name or expression to remove' },
          },
          required: ['name'],
        },
      },
      {
        name: 'watch_list',
        description: 'List all watched variables with current values and change status',
        inputSchema: { type: 'object', properties: {}, required: [] },
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

  const requiresDebugger = new Set([
    'debug_run',
    'debug_step_into',
    'debug_step_over',
    'debug_step_out',
    'debug_stop',
    'debug_status',
    'debug_command',
    'breakpoint_set',
    'breakpoint_remove',
    'breakpoint_list',
    'variables_get',
    'evaluate',
    'stack_trace',
    'capture_error',
    'watch_list',
  ]);

  if (!client.isConnected() && requiresDebugger.has(name)) {
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
        const watches = await snapshotWatches();
        const result: any = {
          status: response.status,
          line: response.lineno || null,
        };
        if (watches.length > 0) result.watches = watches;
        return {
          content: [
            {
              type: 'text',
              text: watches.length > 0
                ? JSON.stringify(result, null, 2)
                : `Stepped into. Status: ${response.status}, Line: ${response.lineno || 'unknown'}`,
            },
          ],
        };
      }

      case 'debug_step_over': {
        const response = await client.stepOver();
        const watches = await snapshotWatches();
        const result: any = {
          status: response.status,
          line: response.lineno || null,
        };
        if (watches.length > 0) result.watches = watches;
        return {
          content: [
            {
              type: 'text',
              text: watches.length > 0
                ? JSON.stringify(result, null, 2)
                : `Stepped over. Status: ${response.status}, Line: ${response.lineno || 'unknown'}`,
            },
          ],
        };
      }

      case 'debug_step_out': {
        const response = await client.stepOut();
        const watches = await snapshotWatches();
        const result: any = {
          status: response.status,
        };
        if (watches.length > 0) result.watches = watches;
        return {
          content: [
            {
              type: 'text',
              text: watches.length > 0
                ? JSON.stringify(result, null, 2)
                : `Stepped out. Status: ${response.status}`,
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

      case 'debug_command': {
        const params = DebugCommandSchema.parse(args);
        const response = await client.sendRawCommand(params.command.trim());
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                command: params.command,
                parsed: response,
                raw: response._raw || '',
              }, null, 2),
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
          try {
            const apiClient = getAnthropicClient();
            const response = await apiClient.messages.create({
              model: 'claude-sonnet-4-5-20250929',
              max_tokens: 1024,
              messages: [{ role: 'user', content: analysisPrompt }],
            });
            const analysisText = response.content[0].type === 'text'
              ? response.content[0].text : '';

            let analysis: any;
            try {
              analysis = JSON.parse(analysisText);
            } catch {
              analysis = { raw: analysisText };
            }

            return {
              content: [
                {
                  type: 'text',
                  text: JSON.stringify({
                    status: 'analyzed',
                    error,
                    analysis,
                    raw_response: analysisText,
                  }, null, 2),
                },
              ],
            };
          } catch (apiErr) {
            return {
              content: [
                {
                  type: 'text',
                  text: JSON.stringify({
                    status: 'api_error',
                    message: apiErr instanceof Error ? apiErr.message : String(apiErr),
                    analysis_prompt: analysisPrompt,
                  }),
                },
              ],
            };
          }
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

      case 'source_outline': {
        const params = SourceOutlineSchema.parse(args);
        const symbols = await getSourceOutline(params.file);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({ file: params.file, count: symbols.length, symbols }, null, 2),
            },
          ],
        };
      }

      case 'workspace_symbols': {
        const params = WorkspaceSymbolsSchema.parse(args);
        const root = params.root ? path.resolve(params.root) : process.cwd();
        const maxResults = params.max_results ?? 200;
        const symbols = await getWorkspaceSymbols(root, params.query, maxResults);
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({
                root,
                query: params.query ?? '',
                count: symbols.length,
                symbols,
              }, null, 2),
            },
          ],
        };
      }

      // === Watch Tools ===

      case 'watch_add': {
        const params = WatchAddSchema.parse(args);
        if (watchList.has(params.name)) {
          return {
            content: [{ type: 'text', text: `Already watching: ${params.name}` }],
          };
        }
        watchList.set(params.name, { name: params.name, lastValue: null, lastType: null });
        return {
          content: [{ type: 'text', text: `Watching: ${params.name} (${watchList.size} total)` }],
        };
      }

      case 'watch_remove': {
        const params = WatchRemoveSchema.parse(args);
        const removed = watchList.delete(params.name);
        return {
          content: [{
            type: 'text',
            text: removed
              ? `Removed watch: ${params.name} (${watchList.size} remaining)`
              : `Not found: ${params.name}`,
          }],
        };
      }

      case 'watch_list': {
        const snapshots = await snapshotWatches();
        if (snapshots.length === 0) {
          return {
            content: [{ type: 'text', text: 'No watches configured. Use watch_add to start tracking variables.' }],
          };
        }
        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify({ count: snapshots.length, watches: snapshots }, null, 2),
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
    watchList.clear();
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
