#!/usr/bin/env python3
"""Pre-commit checks for scripts/setup.sh and the libraries it sources from scripts/lib/*.sh.

Every check prints `file:line: message` for each problem, so a failure points at the line to fix.

  syntax          bash -n on setup.sh and lib/*.sh
  shellcheck      shellcheck at SHELLCHECK_SEVERITY (default: warning) on setup.sh with every lib spliced in at its
                  `source` line (shellcheck does not report problems inside sourced files, and misreads a lib on
                  its own); findings are mapped back to the real file and line. Skipped when it is not installed
  libs            every lib/*.sh is sourced by setup.sh, every `source` points at a file, no function is defined twice
  registry        UTILITY_REGISTRY tags vs the tags in ansible/k8s-utilities-playbook.yaml, and the registries'
                  master.yaml keys vs master.yaml (a new utility or option cannot be forgotten in setup.sh)
  yaml-layout     no column-0 comment or stray line inside a master.yaml / worker.yaml block: the shell YAML
                  helpers stop reading a block there, so everything below it silently disappears from `config`
  stale-phrases   wording that was corrected once and must not come back (scripts/checks/stale-phrases.txt)
  cli             help screens and listings exit 0 with output; `config validate`, `plan` and `completion`;
                  --dry-run when ansible is installed
  completion      the generated completion script is valid bash and lists every command of main(), every utility
                  tag of UTILITY_REGISTRY and every flag of parse_ansible_opts

Usage: python3 scripts/checks/check_setup.py [--root DIR] [--only a,b] [--skip a,b]
Exit code 1 when a check fails. Needs only python3 (already required by ansible).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

CHECKS = ["syntax", "shellcheck", "libs", "registry", "yaml-layout", "stale-phrases", "cli", "completion"]
IGNORED_TAGS = {"always", "never", "all", "tagged", "untagged"}  # reserved Ansible tags, not utilities
TEXT_SUFFIXES = {".md", ".yaml", ".yml", ".sh", ".j2", ".py", ".txt", ".cfg", ".env"}
SKIP_DIRS = ("_site/", "vendor/", ".claude/", ".git/", "archives/", "examples/argocd-apps/archives/")


def shell_files(root):
    files = [root / "scripts/setup.sh"]
    lib = root / "scripts/lib"
    if lib.is_dir():
        files += sorted(lib.glob("*.sh"))
    return [f for f in files if f.exists()]


def rel(root, path):
    return str(Path(path).relative_to(root))


def run(cmd, root, timeout=120):
    return subprocess.run(cmd, cwd=root, capture_output=True, text=True, timeout=timeout)


# ------------------------------------------------------------------ registries
def registry_entries(root, name):
    """Entries of the bash array NAME=( "a|b|..." ... ) across setup.sh and lib/*.sh: [(fields, file, line)]."""
    found = []
    for f in shell_files(root):
        inside = False
        for no, line in enumerate(f.read_text().splitlines(), 1):
            if not inside:
                inside = re.match(rf"^{name}=\(\s*$", line) is not None
                continue
            if line.strip() == ")":
                inside = False
                continue
            m = re.match(r'^\s+"(.*)"\s*$', line)
            if m:
                found.append((m.group(1).split("|"), f, no))
    return found


def yaml_children(text, top, indent=2):
    """Keys at `indent` spaces inside the 0-indent block `top:`; mirrors the shell helpers (_yblock/_ysub)."""
    keys, inside = {}, False
    for no, line in enumerate(text.splitlines(), 1):
        if not inside:
            inside = line.rstrip() == f"{top}:" or line.startswith(f"{top}:")
            continue
        if line and not line.startswith(" "):
            break
        m = re.match(rf"^ {{{indent}}}([A-Za-z][A-Za-z0-9]*):", line)
        if m:
            keys[m.group(1)] = no
    return keys


# ------------------------------------------------------------------ checks
def check_syntax(root):
    problems = []
    for f in shell_files(root):
        r = run(["bash", "-n", str(f)], root)
        if r.returncode != 0:
            # bash prints "<abs path>: line N: message"; show it as "<relative path>:N: message"
            for l in r.stderr.strip().splitlines():
                m = re.match(rf"^{re.escape(str(f))}: line (\d+): (.*)$", l)
                problems.append(f"{rel(root, f)}:{m.group(1)}: {m.group(2)}" if m else f"{rel(root, f)}: {l}")
    return problems


def build_monolith(root):
    """setup.sh with each `source "$SCRIPT_DIR/lib/x.sh"` line replaced by the lib's lines.
    Returns (lines, origin) where origin[i] = (relative file, line number) of lines[i]."""
    lines, origin = [], []
    setup = root / "scripts/setup.sh"
    for no, line in enumerate(setup.read_text().splitlines(), 1):
        m = re.match(r'^\s*source\s+"\$SCRIPT_DIR/lib/([A-Za-z0-9_.-]+)"', line)
        lib = root / "scripts/lib" / m.group(1) if m else None
        if lib is not None and lib.exists():
            for lno, l in enumerate(lib.read_text().splitlines(), 1):
                lines.append(l)
                origin.append((rel(root, lib), lno))
        else:
            lines.append(line)
            origin.append((rel(root, setup), no))
    return lines, origin


def check_shellcheck(root):
    exe = shutil.which("shellcheck")
    if not exe:
        return None  # skipped
    severity = os.environ.get("SHELLCHECK_SEVERITY", "warning")
    lines, origin = build_monolith(root)
    with tempfile.TemporaryDirectory() as tmp:
        mono = Path(tmp) / "setup-with-libs.sh"
        mono.write_text("\n".join(lines) + "\n")
        r = run([exe, "-s", "bash", "-S", severity, "-f", "gcc", str(mono)], root, 300)
    if r.returncode == 0:
        return []
    problems = []
    for l in r.stdout.splitlines():
        m = re.match(r"^.*?setup-with-libs\.sh:(\d+):(\d+): (.*)$", l)
        if m and 1 <= int(m.group(1)) <= len(origin):
            f, no = origin[int(m.group(1)) - 1]
            problems.append(f"{f}:{no}:{m.group(2)}: {m.group(3)}")
        elif l.strip():
            problems.append(l)
    return problems


def check_libs(root):
    problems = []
    setup = root / "scripts/setup.sh"
    lib = root / "scripts/lib"
    if not lib.is_dir():
        return problems
    sourced = {}
    for no, line in enumerate(setup.read_text().splitlines(), 1):
        m = re.match(r'^\s*source\s+"\$SCRIPT_DIR/lib/([A-Za-z0-9_.-]+)"', line)
        if m:
            sourced[m.group(1)] = no
    on_disk = {f.name for f in lib.glob("*.sh")}
    for name, no in sorted(sourced.items(), key=lambda kv: kv[1]):
        if name not in on_disk:
            problems.append(f"scripts/setup.sh:{no}: sources scripts/lib/{name}, which does not exist")
    for name in sorted(on_disk - set(sourced)):
        problems.append(f"scripts/lib/{name}:1: not sourced by scripts/setup.sh, so none of its functions exist at run time")
    seen = {}
    for f in shell_files(root):
        for no, line in enumerate(f.read_text().splitlines(), 1):
            m = re.match(r"^([A-Za-z_][A-Za-z_0-9]*)\(\)\s*\{", line)
            if not m:
                continue
            fn = m.group(1)
            if fn in seen:
                problems.append(f"{rel(root, f)}:{no}: function {fn}() is already defined at {seen[fn]}; the later definition silently wins")
            else:
                seen[fn] = f"{rel(root, f)}:{no}"
    return problems


def check_registry(root):
    problems = []
    play = root / "ansible/k8s-utilities-playbook.yaml"
    master = (root / "ansible/inventories/host_vars/master.yaml").read_text()

    # tags used by the utilities playbook
    used = {}
    lines = play.read_text().splitlines()
    for no, line in enumerate(lines, 1):
        m = re.match(r"^\s*tags:\s*(.*)$", line)
        if not m:
            continue
        v = m.group(1).strip()
        if v.startswith("["):
            for t in (x.strip().strip("'\"") for x in v.strip("[]").split(",") if x.strip()):
                used.setdefault(t, no)
        elif v:
            used.setdefault(v.strip("'\""), no)
        else:  # block list on the following lines
            indent = len(line) - len(line.lstrip())
            for j in range(no, len(lines)):
                item = re.match(rf"^\s{{{indent + 1},}}- (.+)$", lines[j])
                if not item:
                    break
                used.setdefault(item.group(1).strip().strip("'\""), j + 1)
    used = {t: n for t, n in used.items() if t not in IGNORED_TAGS}

    util = registry_entries(root, "UTILITY_REGISTRY")
    if not util:
        return ["scripts/lib: UTILITY_REGISTRY not found in setup.sh or lib/*.sh: the check cannot compare anything"]
    reg_tags = {f[0]: (f, path, no) for f, path, no in util}
    reg_file = rel(root, util[0][1])
    for tag, no in sorted(used.items(), key=lambda kv: kv[1]):
        if tag not in reg_tags:
            problems.append(f"ansible/k8s-utilities-playbook.yaml:{no}: tag '{tag}' has no UTILITY_REGISTRY entry in {reg_file} "
                            f"(`utils --list` and the help would not show it)")
    utilities = yaml_children(master, "utilities")
    for tag, (fields, path, no) in reg_tags.items():
        if tag not in used:
            problems.append(f"{rel(root, path)}:{no}: UTILITY_REGISTRY tag '{tag}' is not used by ansible/k8s-utilities-playbook.yaml")
        key = fields[1] if len(fields) > 1 else ""
        if key not in utilities:
            problems.append(f"{rel(root, path)}:{no}: UTILITY_REGISTRY tag '{tag}' names utilities.{key}, which is not in master.yaml")

    # SETUP_REGISTRY_* keys must exist in their cluster block of master.yaml
    for name, top in (("KIND", "kindCluster"), ("K3S", "k3sCluster"), ("RKE2", "rke2Cluster")):
        keys = yaml_children(master, top)
        for fields, path, no in registry_entries(root, f"SETUP_REGISTRY_{name}"):
            if fields[0] not in keys:
                problems.append(f"{rel(root, path)}:{no}: SETUP_REGISTRY_{name} option '{fields[0]}' is not a key of {top} in master.yaml")
    return problems


def check_yaml_layout(root):
    problems = []
    for name in ("master.yaml", "worker.yaml"):
        path = root / "ansible/inventories/host_vars" / name
        if not path.exists():
            continue
        in_block = False
        for no, line in enumerate(path.read_text().splitlines(), 1):
            if re.match(r"^[A-Za-z][A-Za-z0-9]*:\s*$", line):
                in_block = True
                continue
            if in_block and line and not line.startswith((" ", "\t")):
                if line.startswith("#"):
                    problems.append(f"ansible/inventories/host_vars/{name}:{no}: column-0 comment inside a block: setup.sh stops "
                                    f"reading the block here, so `config` hides everything below it. Indent it by two spaces")
                else:
                    problems.append(f"ansible/inventories/host_vars/{name}:{no}: unexpected column-0 line inside a block: {line[:60]!r}")
    return problems


def tracked_files(root):
    try:
        r = subprocess.run(["git", "ls-files", "-z"], cwd=root, capture_output=True, text=True, timeout=60)
        if r.returncode == 0 and r.stdout:
            return [root / p for p in r.stdout.split("\0") if p]
    except (OSError, subprocess.SubprocessError):
        pass
    return [Path(d) / f for d, _, fs in os.walk(root) for f in fs]


def check_stale_phrases(root):
    spec = root / "scripts/checks/stale-phrases.txt"
    if not spec.exists():
        return []
    rules = []
    for no, line in enumerate(spec.read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            return [f"scripts/checks/stale-phrases.txt:{no}: expected `regex<TAB>message[<TAB>skip-prefixes]`"]
        rules.append((re.compile(parts[0]), parts[1], tuple(x for x in (parts[2].split(",") if len(parts) > 2 else []) if x)))
    problems = []
    for f in tracked_files(root):
        r = rel(root, f)
        if f.suffix not in TEXT_SUFFIXES or r.startswith(SKIP_DIRS) or "/archives/" in r or not f.is_file():
            continue
        try:
            text = f.read_text()
        except (UnicodeDecodeError, OSError):
            continue
        for rx, msg, skip in rules:
            if r.startswith(skip) or r == "scripts/checks/stale-phrases.txt":
                continue
            for no, line in enumerate(text.splitlines(), 1):
                if rx.search(line):
                    problems.append(f"{r}:{no}: {msg}")
    return problems


def check_cli(root):
    problems = []
    setup = "./scripts/setup.sh"
    plain = [["help"], ["kind", "help"], ["k3s", "help"], ["rke2", "help"], ["config", "help"], ["versions", "help"],
             ["config", "--list"], ["config", "--list", "utils"], ["config", "validate"],
             ["doctor", "help"], ["plan", "help"], ["plan", "kind"], ["plan", "k3s"], ["plan", "rke2"], ["plan", "utils"],
             ["completion", "help"], ["completion", "bash"], ["completion", "zsh"]]
    dry = [["kind", "setup", "--dry-run"], ["k3s", "setup", "--dry-run"], ["rke2", "setup", "--dry-run"],
           ["kind", "utils", "certmanager", "--dry-run"]]
    cases = plain + (dry if shutil.which("ansible-playbook") else [])
    for args in cases:
        try:
            r = run([setup] + args, root, 90)
        except subprocess.TimeoutExpired:
            problems.append(f"scripts/setup.sh: `{' '.join(args)}` did not finish in 90 s")
            continue
        if r.returncode != 0:
            tail = (r.stderr or r.stdout).strip().splitlines()[-1:] or ["(no output)"]
            problems.append(f"scripts/setup.sh: `{' '.join(args)}` exited {r.returncode}: {tail[0][:140]}")
        elif not r.stdout.strip():
            problems.append(f"scripts/setup.sh: `{' '.join(args)}` printed nothing")
    return problems


def check_completion(root):
    """The generated completion must know every command, utility tag and ansible flag the CLI has."""
    r = run(["./scripts/setup.sh", "completion", "bash"], root, 90)
    if r.returncode != 0 or not r.stdout.strip():
        return [f"scripts/lib/completion.sh: `completion bash` exited {r.returncode} with " + ("no output" if not r.stdout.strip() else "output")]
    script = r.stdout
    problems = []
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "completion.bash"
        out.write_text(script)
        n = run(["bash", "-n", str(out)], root)
        if n.returncode != 0:
            problems += [f"generated completion script: {l}" for l in n.stderr.strip().splitlines()]

    # commands: every `name) cmd_x` case of main() (help excluded: it takes no arguments)
    main_cmds = set()
    for no, line in enumerate((root / "scripts/setup.sh").read_text().splitlines(), 1):
        m = re.match(r"^\s+([a-z0-9][a-z0-9-]*)\)\s+cmd_[a-z0-9_]+", line)
        if m:
            main_cmds.add(m.group(1))
    m = re.search(r'words="([^"]*) --debug"', script)
    offered = set(m.group(1).split()) if m else set()
    for c in sorted(main_cmds - offered):
        problems.append(f"scripts/setup.sh: command '{c}' is in main() but not offered by the completion (is it listed in show_help COMMANDS?)")
    for c in sorted(offered - main_cmds - {"help"}):
        problems.append(f"scripts/setup.sh: the completion offers '{c}', which main() does not handle")

    # utility tags
    for fields, path, no in registry_entries(root, "UTILITY_REGISTRY"):
        if not re.search(rf"(?<![A-Za-z0-9_-]){re.escape(fields[0])}(?![A-Za-z0-9_-])", script):
            problems.append(f"{rel(root, path)}:{no}: utility tag '{fields[0]}' is missing from the completion")

    # ansible flags of parse_ansible_opts
    flags = set()
    for f in shell_files(root):
        text = f.read_text()
        a = text.find("parse_ansible_opts() {")
        if a >= 0:
            flags |= set(re.findall(r"--[a-z][a-z-]*", text[a: text.find("\n}\n", a)]))
    for fl in sorted(flags):
        if fl not in script:
            problems.append(f"scripts/lib/ansible.sh: flag {fl} of parse_ansible_opts is missing from the completion")
    return problems


FUNCS = {"syntax": check_syntax, "shellcheck": check_shellcheck, "libs": check_libs, "registry": check_registry,
         "yaml-layout": check_yaml_layout, "stale-phrases": check_stale_phrases, "cli": check_cli,
         "completion": check_completion}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[2]), help="repository root (default: this repository)")
    ap.add_argument("--only", default="", help="comma-separated checks to run: " + ", ".join(CHECKS))
    ap.add_argument("--skip", default="", help="comma-separated checks to skip")
    args = ap.parse_args()
    root = Path(args.root).resolve()
    only = [c for c in args.only.split(",") if c]
    skip = {c for c in args.skip.split(",") if c}
    unknown = (set(only) | skip) - set(CHECKS)
    if unknown:
        print(f"unknown check(s): {', '.join(sorted(unknown))} (known: {', '.join(CHECKS)})", file=sys.stderr)
        return 2

    failed = 0
    for name in (only or CHECKS):
        if name in skip:
            print(f"[SKIP] {name}")
            continue
        problems = FUNCS[name](root)
        if problems is None:
            print(f"[SKIP] {name}: tool not installed")
        elif problems:
            failed += 1
            print(f"[FAIL] {name}: {len(problems)} problem(s)")
            for p in problems:
                print(f"       {p}")
        else:
            print(f"[ OK ] {name}")
    if failed:
        print(f"\n{failed} check(s) failed. Fix the lines above, or run one check alone with --only <name>.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
