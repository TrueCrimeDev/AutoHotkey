"""Build an AutoHotkey2.Syntaxes folder that teaches thqby's AutoHotkey2 LSP this fork's additions.

Usage: python tools/vscode/gen_syntaxes.py [--lsp-dir DIR] [--out DIR] [--fork FILE]

vscode-autohotkey2-lsp (checked on 3.0.10, server/dist/server.js, function $r)
reads these files from the folder named by the AutoHotkey2.Syntaxes setting:

  [<locale>/]ahk2.d.ahk   the built-in declarations: REPLACES the extension's
                          syntaxes/ahk2.d.ahk (the bundled file is read only
                          when the folder has none)
  [<locale>/]ahk2.json    directives, keywords, keys, texts and options:
                          REPLACES syntaxes/ahk2.json the same way
  *.snippet.json          ADDED to the set above (root of the folder only)
  [<locale>/]ahk2_h.d.ahk, ahk2_h.json, winapi.d.ahk, winapi.json
                          same replace rule, but read only for AutoHotkey_H
                          (an interpreter that has A_ThreadID; this fork has not)
  ahk2_common.json, ahk2.tmLanguage.json
                          never read from the folder; the extension's own copies
                          are always used

<locale> is the VS Code display language in lower case: the server tries
<folder>/<locale>/<name> first (zh-tw also tries zh-cn/) and then
<folder>/<name>. Because the replacement is wholesale, this script copies the
extension's whole syntaxes folder and then appends the declarations of the
fork's fork.d.ahk to every ahk2.d.ahk in the copy and the fork's directives to
every ahk2.json, so the result is the bundled set plus the fork. The server
enforces @since tags in the declaration file it treats as built in, so the
fork's @since tags (which name "+Console" versions it would not understand) are
rewritten as plain text.

Running it again rewrites the same output (the copy starts from the extension's
files each time), and fork-syntaxes.json in the output folder records what was
generated so a later run can drop files an older extension version produced.
Re-run it after the extension updates, then "Developer: Reload Window".
"""

import argparse
import glob
import json
import os
from pathlib import Path
import re
import shutil
import sys


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = "fork-syntaxes.json"
REGION_START = ";@region fork"
# Snippet entries in the shape the extension's ahk2.json uses (the server reads
# body, description, prefix and syntax; prefix defaults to the trimmed body).
DIRECTIVES = [
    {
        "body": "#EnableEval",
        "description": "Enables the fork's Eval(Expression) built-in for this script; the same as the /Eval command-line switch. Without either, every Eval call throws Error: \"Eval is disabled (add #EnableEval to your script or pass /Eval)\". Top-of-script scope, like #Requires. AutoHotkey 2.1-alpha.33+Console fork only.",
        "prefix": "#EnableEval",
        "syntax": "#EnableEval",
    },
    {
        "body": "#CrashLog ${1:Path}",
        "description": "Writes the fork's structured crash log ([START], [ERROR], [EXIT] records with the script stack) to Path for this script; the same as the /CrashLog=Path command-line switch, and the directive wins when both are given. Quoted paths are accepted. Top-of-script scope, like #Requires. AutoHotkey 2.1-alpha.33+Console fork only.",
        "prefix": "#CrashLog",
        "syntax": "#CrashLog Path",
    },
]


def default_lsp_dir():
    """The newest installed thqby.vscode-autohotkey2-lsp-* extension folder that has syntaxes/ahk2.d.ahk."""
    home = os.environ.get("USERPROFILE") or str(Path.home())
    found = []
    for folder in glob.glob(os.path.join(home, ".vscode", "extensions", "thqby.vscode-autohotkey2-lsp-*")):
        if not os.path.isfile(os.path.join(folder, "syntaxes", "ahk2.d.ahk")):
            continue
        suffix = os.path.basename(folder).rsplit("-", 1)[-1]
        found.append((tuple(int(p) if p.isdigit() else 0 for p in suffix.split(".")), folder))
    return Path(max(found)[1]) if found else None


def default_out():
    home = os.environ.get("USERPROFILE") or str(Path.home())
    return Path(home) / "Documents" / "Design" / "Coding" / "AutoHotkey" / "vscode-syntaxes"


def lsp_version(lsp_dir):
    try:
        return json.loads((lsp_dir / "package.json").read_text(encoding="utf-8")).get("version", "unknown")
    except (OSError, ValueError):
        return lsp_dir.name.rsplit("-", 1)[-1]


def newline_of(text):
    return "\r\n" if "\r\n" in text else "\n"


def fork_declarations(fork_text):
    """fork.d.ahk from its first ;@region on, with @since tags rewritten as text.

    The header above the first region explains how to load the file on its
    own (;@include, ;@reference), which does not apply inside ahk2.d.ahk.
    Returns (text, engine version, top-level names)."""
    lines = fork_text.splitlines()
    start = next((i for i, line in enumerate(lines) if line.startswith(";@region")), 0)
    body = [re.sub(r"^(\s*\*\s*)@since\s+(\S+)", r"\1Since engine \2.", line) for line in lines[start:]]
    engine = re.search(r'A_AhkVersion\s*=\s*"([^"]+)"', fork_text)
    names = [m.group(1) or m.group(2) for m in re.finditer(r"^(?:class (\w+)|(\w+)\()", "\n".join(body), re.M)]
    return "\n".join(body).strip("\n"), engine.group(1) if engine else "unknown", names


def strip_fork_region(text):
    """Remove a fork region a previous run appended (only when the source folder was itself generated)."""
    pos = text.find(REGION_START)
    return text[:pos].rstrip("\r\n") if pos >= 0 else text


def append_declarations(path, decls, engine, lsp_ver, lsp_dir):
    bundled = strip_fork_region(path.read_bytes().decode("utf-8-sig"))  # bytes: keep the file's CRLF
    nl = newline_of(bundled)
    block = [
        "",
        "",
        f"{REGION_START} (AutoHotkey {engine})",
        "; Appended by tools/vscode/gen_syntaxes.py from the fork's fork.d.ahk.",
        f"; Everything above this region is vscode-autohotkey2-lsp {lsp_ver}'s own {path.name}",
        f"; copied from {lsp_dir}. Regenerate after the extension updates.",
        decls.replace("\r\n", "\n"),
        ";@endregion",
        "",
    ]
    path.write_text(bundled.rstrip("\r\n") + "\n".join(block).replace("\n", nl), encoding="utf-8", newline="")


def add_directives(path):
    raw = path.read_bytes().decode("utf-8-sig")
    data = json.loads(raw)
    directives = [d for d in data.setdefault("directives", [])
                  if (d.get("prefix") or d["body"].strip().split()[0]).lower()
                  not in {d["prefix"].lower() for d in DIRECTIVES}]
    directives.extend(DIRECTIVES)
    data["directives"] = directives
    nl = newline_of(raw)
    text = json.dumps(data, ensure_ascii=False, indent="\t").replace("\n", nl) + nl
    path.write_text(text, encoding="utf-8", newline="")
    return len(directives) - len(DIRECTIVES)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--lsp-dir", type=Path, help="extension folder (default: newest "
                        "%%USERPROFILE%%\\.vscode\\extensions\\thqby.vscode-autohotkey2-lsp-*)")
    parser.add_argument("--out", type=Path, default=default_out(),
                        help="output folder for AutoHotkey2.Syntaxes (default: %(default)s)")
    parser.add_argument("--fork", type=Path, default=ROOT / "fork.d.ahk",
                        help="the fork's declaration file (default: %(default)s)")
    args = parser.parse_args(argv)

    lsp_dir = args.lsp_dir or default_lsp_dir()
    if lsp_dir is None:
        print("No thqby.vscode-autohotkey2-lsp-* extension with syntaxes/ahk2.d.ahk under "
              "%USERPROFILE%\\.vscode\\extensions; pass --lsp-dir.", file=sys.stderr)
        return 2
    lsp_dir = lsp_dir.resolve()
    syntaxes = lsp_dir / "syntaxes"
    if not (syntaxes / "ahk2.d.ahk").is_file() or not (syntaxes / "ahk2.json").is_file():
        print(f"{syntaxes} lacks ahk2.d.ahk or ahk2.json; is {lsp_dir} the extension folder?", file=sys.stderr)
        return 2
    if not args.fork.is_file():
        print(f"Fork declaration file not found: {args.fork}", file=sys.stderr)
        return 2
    out = args.out.resolve()
    if out == syntaxes or syntaxes in out.parents or out in syntaxes.parents:
        print(f"--out {out} must be outside the extension's syntaxes folder {syntaxes}", file=sys.stderr)
        return 2

    decls, engine, names = fork_declarations(args.fork.read_text(encoding="utf-8-sig"))
    lsp_ver = lsp_version(lsp_dir)

    previous = set()
    manifest_path = out / MANIFEST
    if manifest_path.is_file():
        try:
            previous = set(json.loads(manifest_path.read_text(encoding="utf-8")).get("files", []))
        except ValueError:
            previous = set()

    out.mkdir(parents=True, exist_ok=True)
    produced = []
    for src in sorted(p for p in syntaxes.rglob("*") if p.is_file()):
        rel = src.relative_to(syntaxes)
        dst = out / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        produced.append(rel.as_posix())
    for stale in sorted(previous - set(produced)):
        try:
            (out / stale).unlink()
        except OSError:
            pass

    report = []
    for rel in produced:
        path = out / rel
        if path.name.lower() == "ahk2.d.ahk":
            append_declarations(path, decls, engine, lsp_ver, lsp_dir)
            report.append(f"  {rel}: the extension's declarations + {len(names)} from fork.d.ahk "
                          f"({', '.join(names)})")
        elif path.name.lower() == "ahk2.json":
            kept = add_directives(path)
            report.append(f"  {rel}: {kept} directives + "
                          f"{', '.join(d['prefix'] for d in DIRECTIVES)}")

    manifest_path.write_text(json.dumps({
        "generator": "tools/vscode/gen_syntaxes.py",
        "lsp_dir": str(lsp_dir),
        "lsp_version": lsp_ver,
        "engine": engine,
        "fork_file": str(args.fork.resolve()),
        "files": produced,
    }, indent=2) + "\n", encoding="utf-8")

    print(f"Wrote {len(produced)} files to {out} (vscode-autohotkey2-lsp {lsp_ver}, AutoHotkey {engine}):")
    print("\n".join(report))
    print("Add to settings.json (user: %APPDATA%\\Code\\User\\settings.json, or a workspace .vscode\\settings.json):")
    print(f'    "AutoHotkey2.Syntaxes": {json.dumps(str(out))}')
    print('Then run "Developer: Reload Window". Re-run this script after the extension updates.')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
