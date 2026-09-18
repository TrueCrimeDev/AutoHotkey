"""Exercise downloaded documentation examples against an explicitly selected engine."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--engine', required=True)
args = parser.parse_args()
engine = str(Path(args.engine).resolve())
examples = Path(__file__).resolve().parents[1] / 'public' / 'examples'
records = []

def run(name, command, expected_code=0, expected_text=None):
    process = subprocess.run([engine, *command], cwd=examples, capture_output=True, encoding='utf-8', timeout=20)
    assert process.returncode == expected_code, f'{name}: exit {process.returncode}; {process.stderr}'
    if expected_text is not None:
        assert expected_text in process.stdout, f'{name}: missing expected output {expected_text!r}'
    records.append({'name': name, 'exit': process.returncode, 'status': 'pass'})
    return process

for file in examples.glob('*.ahk'):
    run('parse ' + file.name, ['check', str(file)])
evidence = json.loads((examples / 'ai-error-feedback.json').read_text(encoding='utf-8'))
result = run('AI feedback error', ['/Headless', '/Diag=json', 'error-demo.ahk'], 10)
assert result.stdout == '', repr(result.stdout)
diagnostic = json.loads(result.stderr)
diagnostic['file'] = Path(diagnostic['file']).name
assert diagnostic == evidence['failedRun']['diagnostic'], diagnostic
original = (examples / 'error-demo.ahk').read_text(encoding='utf-8').splitlines()
corrected = (examples / 'error-demo-fixed.ahk').read_text(encoding='utf-8').splitlines()
response = evidence['claude']
assert original[response['line'] - 1] == response['original']
original[response['line'] - 1] = response['replacement']
assert original == corrected, 'The downloadable correction must match Claude\'s response'
result = run('AI feedback corrected rerun', ['/Headless', '/Diag=json', 'error-demo-fixed.ahk'])
assert result.stdout == '' and result.stderr == '', (result.stdout, result.stderr)
with tempfile.TemporaryDirectory() as td:
    assertion = Path(td) / 'verify-error-fix.ahk'
    assertion.write_text(
        f'#Include {examples / "error-demo-fixed.ahk"}\n'
        'if attempts != 3\n    throw Error("Expected attempts = 3")\n', encoding='utf-8')
    run('AI feedback corrected value', ['/Headless', 'test', str(assertion)])
result = run('stdout walkthrough', ['/Headless', '/Trace', 'stdout-demo.ahk'])
assert result.stdout == 'Hello, terminal!\nAnswer: 42\nDone.\n', repr(result.stdout)
assert result.stderr.splitlines() == [
    '[trace] stdout-demo.ahk:2  Print("Hello, terminal!")',
    '[trace] stdout-demo.ahk:3  value := 40 + 2',
    '[trace] stdout-demo.ahk:4  Print("Answer: {}", value)',
    '[trace] stdout-demo.ahk:5  Print("Done.")',
], repr(result.stderr)
run('double assertion', ['/Headless', 'test', 'double.test.ahk'], expected_text='PASS: Double(21) = 42')
result = run('JSON CLI', ['/Headless', '/Diag=json', 'json-summary.ahk', '{"name":"demo","count":21}'])
assert json.loads(result.stdout) == {'name': 'demo', 'doubled': 42}
result = run('invalid JSON diagnostic', ['/Headless', '/Diag=json', 'json-summary.ahk', '{'], 10)
assert any(json.loads(line).get('kind') == 'diagnostic' for line in result.stderr.splitlines() if line.strip())
run('worker process', ['/Headless', 'test', 'parent.ahk'], expected_text='PASS: worker returned 42')
run('six-feature fixture', ['/Headless', 'test', 'feature_demo.ahk'], expected_text='26 assertions, 0 failed')
print(json.dumps({'checks': len(records), 'results': records}, indent=2))
