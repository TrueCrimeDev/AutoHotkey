#!/usr/bin/env node

/**
 * AHK Error Agent - Headless error capture for AI coding agents
 *
 * Connects to AutoHotkey debugger, captures runtime errors with full context,
 * and outputs AI-readable reports for automated code fixing.
 */

import * as fs from 'fs';
import * as path from 'path';
import { DBGpHandler, StackFrame, Variable } from './dbgp-handler';

// ============================================================================
// Types
// ============================================================================

interface ErrorReport {
  timestamp: string;
  script: string;
  error: {
    type: string;
    message: string;
    line: number;
    file: string;
    sourceCode?: string;
  };
  stackTrace: StackFrame[];
  variables: {
    local: Variable[];
    global: Variable[];
  };
  context: {
    surroundingCode: string[];
    suggestion?: string;
  };
}

interface AgentOptions {
  port: number;
  outputFormat: 'json' | 'markdown' | 'both';
  outputFile?: string;
  watchMode: boolean;
  verbose: boolean;
  maxDepth: number;
  includeGlobals: boolean;
}

// ============================================================================
// Error Report Generator
// ============================================================================

class ErrorReportGenerator {
  constructor(private options: AgentOptions) {}

  async generateReport(
    handler: DBGpHandler,
    initData: any,
    exceptionData: any
  ): Promise<ErrorReport> {
    // Get stack trace
    const stackTrace = await handler.getStackTrace();

    // Get error location from top frame
    const topFrame = stackTrace[0];
    const errorFile = topFrame?.filename || initData?.fileuri?.replace('file:///', '') || 'unknown';
    const errorLine = topFrame?.lineno || 0;

    // Get local and global variables
    const localVars = await handler.getVariables(0, this.options.maxDepth);
    const globalVars = this.options.includeGlobals
      ? await handler.getVariables(1, this.options.maxDepth)
      : [];

    // Get surrounding source code
    const surroundingCode = await this.getSurroundingCode(handler, errorFile, errorLine);

    // Extract error message from exception data
    const errorMessage = this.extractErrorMessage(exceptionData);

    const report: ErrorReport = {
      timestamp: new Date().toISOString(),
      script: errorFile,
      error: {
        type: 'RuntimeException',
        message: errorMessage,
        line: errorLine,
        file: errorFile,
        sourceCode: surroundingCode[Math.min(4, surroundingCode.length - 1)] // The error line
      },
      stackTrace,
      variables: {
        local: localVars,
        global: globalVars
      },
      context: {
        surroundingCode,
        suggestion: this.generateSuggestion(errorMessage, localVars)
      }
    };

    return report;
  }

  private async getSurroundingCode(
    handler: DBGpHandler,
    file: string,
    line: number
  ): Promise<string[]> {
    const startLine = Math.max(1, line - 5);
    const endLine = line + 5;

    try {
      const source = await handler.getSource(file, startLine, endLine);
      return source.split('\n').map((code, idx) => {
        const lineNum = startLine + idx;
        const marker = lineNum === line ? '>>> ' : '    ';
        return `${marker}${lineNum}: ${code}`;
      });
    } catch {
      // Fall back to reading file directly
      try {
        const content = fs.readFileSync(file, 'utf-8');
        const lines = content.split('\n');
        const result: string[] = [];

        for (let i = startLine - 1; i < Math.min(endLine, lines.length); i++) {
          const lineNum = i + 1;
          const marker = lineNum === line ? '>>> ' : '    ';
          result.push(`${marker}${lineNum}: ${lines[i]}`);
        }

        return result;
      } catch {
        return [`>>> ${line}: (source unavailable)`];
      }
    }
  }

  private extractErrorMessage(exceptionData: any): string {
    // Try to extract message from exception breakpoint response
    if (exceptionData._raw) {
      // Look for error message in various formats
      const msgMatch = exceptionData._raw.match(/message="([^"]*)"/);
      if (msgMatch) {
        return Buffer.from(msgMatch[1], 'base64').toString('utf-8');
      }
    }
    return exceptionData.reason || 'Unknown error';
  }

  private generateSuggestion(errorMessage: string, localVars: Variable[]): string {
    const suggestions: string[] = [];

    // Property access error
    if (errorMessage.includes('no property') || errorMessage.includes('undefined')) {
      const propMatch = errorMessage.match(/property "(\w+)"/i);
      if (propMatch) {
        suggestions.push(`The property "${propMatch[1]}" does not exist on the object.`);
        suggestions.push(`Check if the object was properly initialized.`);
        suggestions.push(`Available local variables: ${localVars.map(v => v.name).join(', ')}`);
      }
    }

    // Type error
    if (errorMessage.includes('type') || errorMessage.includes('String') || errorMessage.includes('Integer')) {
      suggestions.push(`Type mismatch detected. Verify the data types of your variables.`);
    }

    // Uninitialized variable
    if (errorMessage.includes('unset') || errorMessage.includes('VarUnset')) {
      suggestions.push(`A variable is being used before it was assigned a value.`);
    }

    return suggestions.join('\n') || 'Review the error context and stack trace for debugging.';
  }

  formatAsMarkdown(report: ErrorReport): string {
    let md = `## Runtime Error Report

**Timestamp:** ${report.timestamp}
**Script:** \`${report.script}\`

### Error Details

- **Type:** ${report.error.type}
- **Message:** ${report.error.message}
- **Location:** \`${report.error.file}:${report.error.line}\`

### Source Code Context

\`\`\`autohotkey
${report.context.surroundingCode.join('\n')}
\`\`\`

### Stack Trace

| Level | Function | Location |
|-------|----------|----------|
${report.stackTrace.map(f =>
  `| ${f.level} | ${f.where || '(main)'} | ${path.basename(f.filename)}:${f.lineno} |`
).join('\n')}

### Local Variables

${report.variables.local.length > 0
  ? report.variables.local.map(v => `- **${v.name}** (${v.type}): \`${this.truncate(v.value, 100)}\``).join('\n')
  : '_(no local variables)_'}

${report.variables.global.length > 0 ? `
### Global Variables

${report.variables.global.map(v => `- **${v.name}** (${v.type}): \`${this.truncate(v.value, 100)}\``).join('\n')}
` : ''}

### Suggested Fix

${report.context.suggestion}

---
_Report generated by AHK Error Agent for AI coding assistance_
`;

    return md;
  }

  formatAsJson(report: ErrorReport): string {
    return JSON.stringify(report, null, 2);
  }

  private truncate(str: string, maxLen: number): string {
    if (str.length <= maxLen) return str;
    return str.substring(0, maxLen - 3) + '...';
  }
}

// ============================================================================
// Main Agent
// ============================================================================

class AHKErrorAgent {
  private handler: DBGpHandler;
  private generator: ErrorReportGenerator;
  private options: AgentOptions;

  constructor(options: Partial<AgentOptions> = {}) {
    this.options = {
      port: options.port || 9000,
      outputFormat: options.outputFormat || 'markdown',
      outputFile: options.outputFile,
      watchMode: options.watchMode ?? false,
      verbose: options.verbose ?? false,
      maxDepth: options.maxDepth ?? 2,
      includeGlobals: options.includeGlobals ?? true
    };

    this.handler = new DBGpHandler(this.options.port);
    this.generator = new ErrorReportGenerator(this.options);
  }

  async start(): Promise<void> {
    this.log('AHK Error Agent starting...');
    this.log(`Listening on port ${this.options.port}`);
    this.log('Start AutoHotkey with: AutoHotkey.exe /Debug script.ahk\n');

    await this.handler.listen();

    if (this.options.watchMode) {
      this.log('Watch mode enabled - will restart after each session\n');
      await this.watchLoop();
    } else {
      await this.handleSession();
    }
  }

  private async watchLoop(): Promise<void> {
    while (true) {
      try {
        await this.handleSession();
        this.log('\n--- Session ended, waiting for next connection ---\n');
      } catch (err) {
        this.log(`Session error: ${err}`);
      }
    }
  }

  private async handleSession(): Promise<void> {
    return new Promise((resolve, reject) => {
      let initData: any;
      let sessionResolved = false;

      this.handler.on('connected', async (init) => {
        initData = init;
        this.log(`Connected: ${init.fileuri || 'unknown script'}`);

        try {
          // Set exception breakpoint to catch all errors
          await this.handler.setExceptionBreakpoint();
          this.log('Exception breakpoint set');

          // Run the script
          const response = await this.handler.run();
          this.log(`Script running... (status: ${response.status})`);

          // If script completed without exception
          if (response.status === 'stopped' && !sessionResolved) {
            sessionResolved = true;
            this.output('# Script completed successfully - no errors detected\n');
            resolve();
          }
        } catch (err) {
          if (!sessionResolved) {
            sessionResolved = true;
            reject(err);
          }
        }
      });

      this.handler.on('exception', async (exceptionData) => {
        this.log('Exception caught! Generating report...\n');

        try {
          const report = await this.generator.generateReport(
            this.handler,
            initData,
            exceptionData
          );

          this.outputReport(report);

          // Stop the script after capturing error
          await this.handler.stop();
        } catch (err) {
          this.log(`Error generating report: ${err}`);
        }
      });

      this.handler.on('stopped', () => {
        if (!sessionResolved) {
          sessionResolved = true;
          resolve();
        }
      });

      this.handler.on('disconnected', () => {
        this.log('Disconnected');
        if (!sessionResolved) {
          sessionResolved = true;
          resolve();
        }
      });

      this.handler.on('error', (err) => {
        this.log(`Error: ${err}`);
        if (!sessionResolved) {
          sessionResolved = true;
          reject(err);
        }
      });
    });
  }

  private outputReport(report: ErrorReport): void {
    let output = '';

    if (this.options.outputFormat === 'json' || this.options.outputFormat === 'both') {
      output += this.generator.formatAsJson(report);
      if (this.options.outputFormat === 'both') {
        output += '\n\n---\n\n';
      }
    }

    if (this.options.outputFormat === 'markdown' || this.options.outputFormat === 'both') {
      output += this.generator.formatAsMarkdown(report);
    }

    this.output(output);
  }

  private output(text: string): void {
    if (this.options.outputFile) {
      fs.appendFileSync(this.options.outputFile, text + '\n');
      this.log(`Report written to ${this.options.outputFile}`);
    } else {
      console.log(text);
    }
  }

  private log(message: string): void {
    if (this.options.verbose) {
      console.error(`[AHK-Error-Agent] ${message}`);
    }
  }

  close(): void {
    this.handler.close();
  }
}

// ============================================================================
// CLI
// ============================================================================

function printHelp(): void {
  console.log(`
AHK Error Agent - Headless error capture for AI coding agents

Usage: ahk-error-agent [options]

Options:
  -p, --port <number>      Port to listen on (default: 9000)
  -f, --format <type>      Output format: json, markdown, both (default: markdown)
  -o, --output <file>      Write output to file instead of stdout
  -w, --watch              Watch mode - restart after each session
  -g, --no-globals         Don't include global variables in report
  -d, --depth <number>     Max property inspection depth (default: 2)
  -v, --verbose            Verbose logging to stderr
  -h, --help               Show this help

Examples:
  # Basic usage - output markdown to stdout
  ahk-error-agent

  # JSON output to file for AI consumption
  ahk-error-agent -f json -o errors.json -w

  # Verbose mode with watch
  ahk-error-agent -v -w

Then run your AutoHotkey script with:
  AutoHotkey.exe /Debug your_script.ahk
`);
}

function parseArgs(): AgentOptions {
  const args = process.argv.slice(2);
  const options: Partial<AgentOptions> = {};

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    switch (arg) {
      case '-p':
      case '--port':
        options.port = parseInt(args[++i], 10);
        break;
      case '-f':
      case '--format':
        options.outputFormat = args[++i] as any;
        break;
      case '-o':
      case '--output':
        options.outputFile = args[++i];
        break;
      case '-w':
      case '--watch':
        options.watchMode = true;
        break;
      case '-g':
      case '--no-globals':
        options.includeGlobals = false;
        break;
      case '-d':
      case '--depth':
        options.maxDepth = parseInt(args[++i], 10);
        break;
      case '-v':
      case '--verbose':
        options.verbose = true;
        break;
      case '-h':
      case '--help':
        printHelp();
        process.exit(0);
    }
  }

  return {
    port: options.port || 9000,
    outputFormat: options.outputFormat || 'markdown',
    outputFile: options.outputFile,
    watchMode: options.watchMode ?? false,
    verbose: options.verbose ?? false,
    maxDepth: options.maxDepth ?? 2,
    includeGlobals: options.includeGlobals ?? true
  };
}

// Main entry point
const options = parseArgs();
const agent = new AHKErrorAgent(options);

process.on('SIGINT', () => {
  console.error('\nShutting down...');
  agent.close();
  process.exit(0);
});

agent.start().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
