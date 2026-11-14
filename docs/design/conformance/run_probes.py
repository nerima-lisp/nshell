"""Run language probes against an nshell binary and record exit/stdout/stderr.

Usage: NSHELL_BIN=./result/bin/nshell python3 run_probes.py CASES.json OUT.json
CASES.json is a list of {"id", "src", "files"}; language-probes-v0.7.0.json holds the v0.7.0 results."""
import json, os, subprocess, sys, tempfile

CORE = os.environ.get("NSHELL_BIN", "nshell")
ROOT = os.environ.get("NSHELL_PROBE_DIR", "/tmp/nshprobe")


def run(src, files=None, timeout=20):
    os.makedirs(ROOT, exist_ok=True)
    work = tempfile.mkdtemp(dir=ROOT)
    home = os.path.join(work, "home")
    os.makedirs(home, exist_ok=True)
    for name, content in (files or {}).items():
        path = os.path.join(work, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(content)
    script = os.path.join(work, "case.nsh")
    with open(script, "w") as f:
        f.write(src)
    env = dict(os.environ, HOME=home, XDG_CONFIG_HOME=os.path.join(home, ".config"),
               XDG_DATA_HOME=os.path.join(home, ".data"), NO_COLOR="1", LANG="C.UTF-8")
    try:
        r = subprocess.run([CORE, script], cwd=work, env=env, capture_output=True, text=True,
                           timeout=timeout, stdin=subprocess.DEVNULL)
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return "TIMEOUT", "", ""


if __name__ == "__main__":
    data = json.load(open(sys.argv[1]))
    cases = data["cases"] if isinstance(data, dict) else data
    out = []
    for c in cases:
        code, so, se = run(c["src"], c.get("files"))
        out.append(dict(id=c["id"], src=c["src"], exit=code, stdout=so, stderr=se))
        print(f"### {c['id']}  exit={code}")
        print("SRC:", c["src"].rstrip())
        if so.strip():
            print("OUT:", so.rstrip()[:600])
        if se.strip():
            print("ERR:", se.rstrip()[:600])
    json.dump(out, open(sys.argv[2], "w"), ensure_ascii=False, indent=1)
