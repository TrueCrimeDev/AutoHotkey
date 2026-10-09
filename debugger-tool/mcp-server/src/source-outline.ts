/**
 * Line-based symbol scan behind the source_outline and workspace_symbols tools.
 * Kept out of index.ts so the scan can be unit-tested without starting the server.
 *
 * One definition per line: a header is recognised from its first identifier, a
 * balanced parameter list (nested brackets and string literals included) and what
 * follows it: `{`, `=>`, or nothing when the next code line opens the body with `{`.
 * Brace depth is tracked so members directly inside a class body are reported as
 * methods and properties. Keywords (`class`, `static`, control flow) match in any
 * letter case, as the engine reads them. ast_outline remains the real parse.
 */

import * as fs from 'fs/promises';
import * as path from 'path';

export type SymbolKind = 'function' | 'class' | 'method' | 'property' | 'hotkey' | 'label';

export type SourceSymbol = {
  kind: SymbolKind;
  name: string;
  line: number;
  text: string;
  file?: string;
};

const AHK_EXTENSIONS = new Set(['.ahk', '.ah2']);
const CONTROL_FLOW = new Set(['if', 'while', 'for', 'loop', 'switch', 'catch', 'try', 'else']);
const IDENTIFIER = /^[A-Za-z_]\w*/;

// Index just past the quote closing the literal that opens at `start`, or -1 when unterminated.
// A backtick escapes the next character, so `" and `' do not close the literal.
function skipString(line: string, start: number): number {
  const quote = line[start];
  for (let i = start + 1; i < line.length; i++) {
    if (line[i] === '`') {
      i++;
      continue;
    }
    if (line[i] === quote)
      return i + 1;
  }
  return -1;
}

// Drops a trailing `;` comment (one at line start or after whitespace) that is outside string literals.
function stripComment(line: string): string {
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"' || ch === "'") {
      const end = skipString(line, i);
      if (end < 0)
        return line;
      i = end - 1;
      continue;
    }
    if (ch === ';' && (i === 0 || /\s/.test(line[i - 1])))
      return line.slice(0, i);
  }
  return line;
}

// Index just past the bracket matching the opener at `start`, honouring nested brackets of every
// kind and string literals; -1 when the line does not close it.
function skipBalanced(line: string, start: number): number {
  const closer = line[start] === '(' ? ')' : line[start] === '[' ? ']' : '}';
  let depth = 0;
  for (let i = start; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"' || ch === "'") {
      const end = skipString(line, i);
      if (end < 0)
        return -1;
      i = end - 1;
      continue;
    }
    if (ch === '(' || ch === '[' || ch === '{') {
      depth++;
    } else if (ch === ')' || ch === ']' || ch === '}') {
      depth--;
      if (depth === 0)
        return ch === closer ? i + 1 : -1;
    }
  }
  return -1;
}

// Net change in brace depth over one line, ignoring braces inside string literals.
function braceDelta(line: string): number {
  let delta = 0;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"' || ch === "'") {
      const end = skipString(line, i);
      if (end < 0)
        break;
      i = end - 1;
      continue;
    }
    if (ch === '{')
      delta++;
    else if (ch === '}')
      delta--;
  }
  return delta;
}

// Tracks /* ... */ blocks across trimmed lines; the returned function says whether a line is comment.
function blockCommentTracker(): (trimmed: string) => boolean {
  let inBlock = false;
  return (trimmed: string): boolean => {
    if (inBlock) {
      if (trimmed.startsWith('*/') || trimmed.endsWith('*/'))
        inBlock = false;
      return true;
    }
    if (trimmed.startsWith('/*')) {
      inBlock = !trimmed.endsWith('*/');
      return true;
    }
    return false;
  };
}

// The next line with code on it, trimmed and without its comment; '' when none remains.
function nextCodeLine(lines: string[], from: number): string {
  const isComment = blockCommentTracker();
  for (let i = from; i < lines.length; i++) {
    const trimmed = lines[i].trim();
    if (isComment(trimmed))
      continue;
    const line = stripComment(trimmed).trimEnd();
    if (line)
      return line;
  }
  return '';
}

// What follows a definition header: its body opener on this line, or 'next' when the line ends there.
function bodyMarker(tail: string): 'brace' | 'arrow' | 'next' | null {
  if (tail === '')
    return 'next';
  if (tail.startsWith('{'))
    return 'brace';
  if (tail.startsWith('=>'))
    return 'arrow';
  return null;
}

type Match = { kind: SymbolKind; name: string; needsBrace: boolean };

function matchDefinition(line: string, inClassBody: boolean): Match | null {
  const classMatch = /^class\s+([A-Za-z_]\w*)\b/i.exec(line);
  if (classMatch)
    return { kind: 'class', name: classMatch[1], needsBrace: false };

  let rest = line;
  if (inClassBody) {
    const staticMatch = /^static\s+(?=[A-Za-z_])/i.exec(rest);
    if (staticMatch)
      rest = rest.slice(staticMatch[0].length);
  }

  const ident = IDENTIFIER.exec(rest);
  if (ident) {
    const name = ident[0];
    let pos = name.length;
    while (pos < rest.length && /\s/.test(rest[pos]))
      pos++;
    const opener = rest[pos];
    if (opener === '(' || (inClassBody && opener === '[')) {
      const end = skipBalanced(rest, pos);
      const body = end < 0 ? null : bodyMarker(rest.slice(end).trim());
      if (body && !CONTROL_FLOW.has(name.toLowerCase())) {
        const kind: SymbolKind = opener === '[' ? 'property' : inClassBody ? 'method' : 'function';
        return { kind, name, needsBrace: body === 'next' };
      }
    } else if (inClassBody) {
      const body = bodyMarker(rest.slice(pos));
      if (body)
        return { kind: 'property', name, needsBrace: body === 'next' };
    }
  }

  const hotkeyMatch = /^([^;\s][^:]*?)::/.exec(line);
  if (hotkeyMatch)
    return { kind: 'hotkey', name: hotkeyMatch[1].trim(), needsBrace: false };

  const labelMatch = /^([A-Za-z_]\w*)\s*:\s*$/.exec(line);
  if (labelMatch && labelMatch[1].toLowerCase() !== 'case' && labelMatch[1].toLowerCase() !== 'default')
    return { kind: 'label', name: labelMatch[1], needsBrace: false };

  return null;
}

export function parseSourceOutline(content: string): SourceSymbol[] {
  const lines = content.split(/\r?\n/);
  const symbols: SourceSymbol[] = [];
  const isComment = blockCommentTracker();
  // Brace depth at which each open class body's members sit, innermost last.
  const classBodies: number[] = [];
  let depth = 0;

  for (let idx = 0; idx < lines.length; idx++) {
    const rawLine = lines[idx];
    const trimmed = rawLine.trim();
    if (isComment(trimmed))
      continue;
    const line = stripComment(trimmed).trimEnd();
    if (!line)
      continue;

    const depthBefore = depth;
    depth += braceDelta(line);
    while (classBodies.length > 0 && depth < classBodies[classBodies.length - 1])
      classBodies.pop();
    const inClassBody = classBodies.length > 0 && depthBefore === classBodies[classBodies.length - 1];

    const match = matchDefinition(line, inClassBody);
    if (!match)
      continue;
    if (match.needsBrace && !nextCodeLine(lines, idx + 1).startsWith('{'))
      continue;
    symbols.push({ kind: match.kind, name: match.name, line: idx + 1, text: rawLine });
    if (match.kind === 'class')
      classBodies.push(depthBefore + 1);
  }

  return symbols;
}

export async function getSourceOutline(file: string): Promise<SourceSymbol[]> {
  const content = await fs.readFile(file, 'utf-8');
  return parseSourceOutline(content);
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

export async function getWorkspaceSymbols(root: string, query = '', maxResults = 200): Promise<SourceSymbol[]> {
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
