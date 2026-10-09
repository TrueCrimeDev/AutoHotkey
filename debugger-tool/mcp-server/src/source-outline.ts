/**
 * Line-based symbol scan behind the source_outline and workspace_symbols tools.
 * Kept out of index.ts so the scan can be unit-tested without starting the server.
 */

import * as fs from 'fs/promises';
import * as path from 'path';

export type SourceSymbol = {
  kind: 'function' | 'class' | 'hotkey' | 'label';
  name: string;
  line: number;
  text: string;
  file?: string;
};

const AHK_EXTENSIONS = new Set(['.ahk', '.ah2']);

export function parseSourceOutline(content: string): SourceSymbol[] {
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
