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
run('double assertion', ['/Headless', 'test', 'double.test.ahk'], expected_text='PASS: Double(21) = 42')
result = run('JSON CLI', ['/Headless', '/Diag=json', 'json-summary.ahk', '{"name":"demo","count":21}'])
assert json.loads(result.stdout) == {'name': 'demo', 'doubled': 42}
result = run('invalid JSON diagnostic', ['/Headless', '/Diag=json', 'json-summary.ahk', '{'], 10)
assert any(json.loads(line).get('kind') == 'diagnostic' for line in result.stderr.splitlines() if line.strip())
run('worker process', ['/Headless', 'test', 'parent.ahk'], expected_text='PASS: worker returned 42')
run('six-feature fixture', ['/Headless', 'test', 'feature_demo.ahk'], expected_text='26 assertions, 0 failed')
print(json.dumps({'checks': len(records), 'results': records}, indent=2))
