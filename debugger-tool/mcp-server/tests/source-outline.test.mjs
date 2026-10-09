import assert from 'node:assert/strict';
import { test } from 'node:test';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { parseSourceOutline, getWorkspaceSymbols } from '../build/source-outline.js';

// One fixture, line numbers are load-bearing: the tests below name them.
const FIXTURE = `#Requires AutoHotkey v2.1-alpha.33

Double(x) => x * 2
Clamp(v, lo := (0 + 1), hi := Max(10, 20)) => Min(Max(v, lo), hi)
Join(parts, sep := ", ", suffix := "x)") {
    return ""
}
Build(opts := Map(), flags := (1 | 2)) {
}
Describe(a := 'it\`'s)', b := "q\`"x)") => a b
Allman(a)
{
}
Commented(a) ; trailing note
{
}
MsgBox(Format("{}", 1))
Print("hi")
if (Allman(1)) {
}
/*
Hidden(a) => a
*/
class Shape {
    __New(w := (1 + 1), h := Map()) {
    }
    Area() => this.w * this.h
    static Unit() => Shape(1, 1)
    Width => this.w
    Item[i] => this.cells[i]
    static Count => 0
    Height {
        get => this.h
        set => this.h := value
    }
    Cell[i, j := (1)] {
        get => 0
    }
    class Inner {
        Ping() => "pong"
    }
    Last() {
        Print("x")
    }
}
^j::Send("{Enter}")
MyLabel:
Later() => 1
`;

const outline = () => parseSourceOutline(FIXTURE).map(s => `${s.kind} ${s.name} ${s.line}`);

test('top-level fat-arrow functions are functions on their own line', () => {
  const found = outline();
  assert.ok(found.includes('function Double 3'), found.join('\n'));
  assert.ok(found.includes('function Later 48'), found.join('\n'));
});

test('parenthesized default parameters do not hide a function', () => {
  const found = outline();
  assert.ok(found.includes('function Clamp 4'), 'Clamp: nested parens before =>');
  assert.ok(found.includes('function Build 8'), 'Build: Map() and (1 | 2) before {');
});

test('string literals holding a closing paren do not end the parameter list', () => {
  const found = outline();
  assert.ok(found.includes('function Join 5'), 'Join: ")" inside a double-quoted default');
  assert.ok(found.includes('function Describe 10'), 'Describe: backtick-escaped quotes and ")" in both quote styles');
});

test('class members are methods and properties, fat-arrow or braced', () => {
  const found = outline();
  for (const expected of [
    'method __New 25', 'method Area 27', 'method Unit 28', 'property Width 29', 'property Item 30',
    'property Count 31', 'property Height 32', 'property Cell 36', 'class Inner 39', 'method Ping 40',
    'method Last 42',
  ])
    assert.ok(found.includes(expected), `${expected} missing from:\n${found.join('\n')}`);
  assert.ok(!found.some(s => / get /.test(s) || / set /.test(s)), 'getter/setter bodies are not symbols');
});

test('call statements and block comments are not definitions', () => {
  const found = outline();
  for (const line of [17, 18, 19, 22, 43])
    assert.ok(!found.some(s => s.endsWith(` ${line}`)), `line ${line} reported: ${found.join(', ')}`);
  assert.ok(found.includes('function Allman 11'), 'Allman brace on the next line');
  assert.ok(found.includes('function Commented 14'), 'trailing comment before an Allman brace');
});

test('full outline of the fixture', () => {
  assert.deepEqual(outline(), [
    'function Double 3',
    'function Clamp 4',
    'function Join 5',
    'function Build 8',
    'function Describe 10',
    'function Allman 11',
    'function Commented 14',
    'class Shape 24',
    'method __New 25',
    'method Area 27',
    'method Unit 28',
    'property Width 29',
    'property Item 30',
    'property Count 31',
    'property Height 32',
    'property Cell 36',
    'class Inner 39',
    'method Ping 40',
    'method Last 42',
    'hotkey ^j 46',
    'label MyLabel 47',
    'function Later 48',
  ]);
});

test('workspace_symbols carries the new kinds and the file path', async () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ahk-outline-'));
  try {
    fs.writeFileSync(path.join(root, 'shape.ahk'), 'class Shape {\n    Area(scale := (1)) => this.w * scale\n}\n');
    fs.mkdirSync(path.join(root, 'node_modules'));
    fs.writeFileSync(path.join(root, 'node_modules', 'skip.ahk'), 'Area() => 0\n');
    const symbols = await getWorkspaceSymbols(root, 'area');
    assert.deepEqual(symbols.map(s => [s.kind, s.name, s.line, path.basename(s.file)]), [['method', 'Area', 2, 'shape.ahk']]);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
