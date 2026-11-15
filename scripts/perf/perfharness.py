#!/usr/bin/env python3
"""Interleaved (ABBA) measurement of two nshell binaries on a PTY.

Writes raw samples as JSON for perfstats.py. Every nshell process runs with
HOME and the XDG directories in a fresh temporary directory and
NSHELL_AI_COMMAND=/nonexistent, so real history, config and AI providers are
never touched.

Metrics (see README.md for definitions):
  startup.*   B1 startup times, one process per sample
  key.*       B2 per-key latency, long-lived processes, 200 measured keys each
  tab.*       Tab completion latency
  prompt.*    prompt display time after Enter on an empty line
  rss.*       resident set size of the interactive processes
"""

from __future__ import annotations

import argparse
import ctypes
import errno
import fcntl
import json
import os
import platform
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
import uuid
from pathlib import Path
from typing import Any, Callable

FRAME_END = b"\x1b[0 q"  # cursor-shape reset the line editor emits at the end of every redraw
CPR_QUERY = b"\x1b[6n"
CPR_RESPONSE = b"\x1b[1;1R"
PASTE_START = b"\x1b[200~"
PASTE_END = b"\x1b[201~"
CTRL_U = b"\x15"
BACKSPACE = b"\x7f"
ANSI_RE = re.compile(rb"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1b]*(?:\x07|\x1b\\)|[@-_])")
TERMINAL_SIZE = (24, 100)
PATH_VALUE = "/usr/bin:/bin"
BIG_DIR_ENTRIES = 20_000
HISTORY_ENTRIES = 10_000
HISTORY_PREFIX = b"# nshell-history-v3 "
PROMPT_TIMEOUT = 60.0
FRAME_TIMEOUT = 20.0
COMMAND_TIMEOUT = 60.0
UNIQUE_NAME = "unique-target.txt"

# B2 scenarios: (name, text pasted before typing, character typed).
# Typing alternates the character and Backspace, so the buffer keeps the
# prefilled length and every key triggers a redraw and an autosuggest lookup.
def _fill(prefix: str, length: int) -> str:
    body = prefix + "ab " * length
    return body[:length]


KEY_SCENARIOS: list[tuple[str, str, str]] = [
    ("key.bare_1", "", "x"),
    ("key.bare_200", _fill("echo ", 200), "x"),
    ("key.bare_1000", _fill("echo ", 1000), "x"),
    ("key.sexp_200", _fill("(echo ", 200), "x"),
    # History is empty, so autosuggest falls back to filesystem completion of
    # big/ (20,000 entries) on every key: "item-1" matches 10,000 names and
    # "item-12" 1,000.
    ("key.path_20k", "cat big/item-1", "2"),
]
TAB_VARIANTS: list[tuple[str, str]] = [
    ("tab.path_small", "cat small/uniq"),
    ("tab.path_20k", "cat big/uniq"),
]


class HarnessError(RuntimeError):
    pass


def uptime() -> str:
    return subprocess.run(["uptime"], check=True, capture_output=True, text=True).stdout.strip()


def visible(data: bytes) -> str:
    return ANSI_RE.sub(b"", data).decode("utf-8", "replace")


class Isolation:
    """A fresh HOME/XDG tree per process."""

    def __init__(self, root: Path, history: Path | None = None):
        self.home = Path(tempfile.mkdtemp(prefix="home-", dir=root))
        for name in ("config", "data", "state", "cache", "tmp"):
            (self.home / name).mkdir()
        if history is not None:
            target = self.home / "data" / "nshell" / "history"
            target.parent.mkdir(parents=True)
            shutil.copyfile(history, target)

    def env(self, marker: str | None = None) -> dict[str, str]:
        env = {
            "HOME": str(self.home),
            "XDG_CONFIG_HOME": str(self.home / "config"),
            "XDG_DATA_HOME": str(self.home / "data"),
            "XDG_STATE_HOME": str(self.home / "state"),
            "XDG_CACHE_HOME": str(self.home / "cache"),
            "TMPDIR": str(self.home / "tmp"),
            "PATH": PATH_VALUE,
            "TERM": "xterm-256color",
            "LANG": "C",
            "LC_ALL": "C",
            "NSHELL_GREETING": "",
            "NSHELL_AI_COMMAND": "/nonexistent",
        }
        if marker is not None:
            env["NSHELL_PROMPT"] = marker
        return env

    def remove(self) -> None:
        shutil.rmtree(self.home, ignore_errors=True)


class Session:
    """An nshell process on a PTY, answering cursor-position queries."""

    def __init__(self, argv: list[str], cwd: Path, env: dict[str, str]):
        self.data = bytearray()
        self.answered = 0
        self.rusage = None
        self.started_ns = time.perf_counter_ns()
        self.pid, self.master = pty.fork()
        if self.pid == 0:
            try:
                os.chdir(cwd)
                os.execve(argv[0], argv, env)
            except OSError as error:
                os.write(2, f"exec failed: {error}\n".encode())
            os._exit(127)
        fcntl.ioctl(self.master, termios.TIOCSWINSZ, struct.pack("HHHH", *TERMINAL_SIZE, 0, 0))

    def _read(self, timeout: float) -> bool:
        ready, _, _ = select.select([self.master], [], [], max(0.0, timeout))
        if not ready:
            return False
        try:
            chunk = os.read(self.master, 65536)
        except OSError as error:
            if error.errno == errno.EIO:
                raise HarnessError(f"nshell exited; tail={visible(bytes(self.data[-300:]))!r}") from error
            raise
        if not chunk:
            raise HarnessError("nshell closed the PTY")
        self.data.extend(chunk)
        queries = self.data.count(CPR_QUERY)
        while self.answered < queries:
            os.write(self.master, CPR_RESPONSE)
            self.answered += 1
        return True

    def wait_for(self, predicate: Callable[[int], bool], start: int, timeout: float) -> int:
        """Read until predicate(start) holds; returns perf_counter_ns at that moment."""
        deadline = time.monotonic() + timeout
        while not predicate(start):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise HarnessError(f"no frame within {timeout}s; tail={visible(bytes(self.data[-300:]))!r}")
            self._read(remaining)
        return time.perf_counter_ns()

    def frame_after(self, start: int) -> bool:
        return self.data.find(FRAME_END, start) >= 0

    def frame_showing(self, text: str) -> Callable[[int], bool]:
        """True once a complete frame after `start` shows `text` (ANSI sequences removed)."""
        def predicate(start: int) -> bool:
            segment_start = start
            while True:
                end = self.data.find(FRAME_END, segment_start)
                if end < 0:
                    return False
                if text in visible(bytes(self.data[segment_start:end])):
                    return True
                segment_start = end + len(FRAME_END)
        return predicate

    def frames_between(self, start: int, end: int) -> int:
        return bytes(self.data[start:end]).count(FRAME_END)

    def prompt_frame_after(self, marker: bytes) -> Callable[[int], bool]:
        def predicate(start: int) -> bool:
            index = self.data.find(marker, start)
            return index >= 0 and self.data.find(FRAME_END, index) >= 0
        return predicate

    def drain(self, quiet: float) -> None:
        """Consume output until none arrives for `quiet` seconds."""
        while self._read(quiet):
            pass

    def send(self, payload: bytes) -> tuple[int, int]:
        """Drain pending output, write payload; return (output offset, perf_counter_ns before the write)."""
        while self._read(0):
            pass
        start = len(self.data)
        sent_ns = time.perf_counter_ns()
        os.write(self.master, payload)
        return start, sent_ns

    def rss_kb(self) -> int | None:
        result = subprocess.run(["ps", "-o", "rss=", "-p", str(self.pid)], capture_output=True, text=True)
        text = result.stdout.strip()
        return int(text) if text.isdigit() else None

    def _signal(self, number: int) -> None:
        # pty.fork makes the child a session leader, so its pid is its process group.
        try:
            os.killpg(self.pid, number)
        except ProcessLookupError:
            try:
                os.kill(self.pid, number)
            except ProcessLookupError:
                pass

    def close(self) -> None:
        self._signal(signal.SIGTERM)
        # Close the master before waiting: an exiting process blocks while the
        # tty drains output that nobody reads.
        try:
            os.close(self.master)
        except OSError:
            pass
        deadline = time.monotonic() + 2.0
        while True:
            try:
                pid, _, rusage = os.wait4(self.pid, os.WNOHANG)
            except ChildProcessError:
                break
            if pid == self.pid:
                self.rusage = rusage
                break
            if time.monotonic() > deadline:
                self._signal(signal.SIGKILL)
                _, _, self.rusage = os.wait4(self.pid, 0)
                break
            time.sleep(0.01)

    def peak_rss_kb(self) -> int | None:
        if self.rusage is None:
            return None
        # ru_maxrss is bytes on macOS and kilobytes on Linux.
        return self.rusage.ru_maxrss // 1024 if sys.platform == "darwin" else self.rusage.ru_maxrss


# --- cold startup ---------------------------------------------------------

_libc = ctypes.CDLL(None, use_errno=True)
_libc.mmap.restype = ctypes.c_void_p
_libc.mmap.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong]
_libc.munmap.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
_libc.mincore.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_char_p]
F_NOCACHE = getattr(fcntl, "F_NOCACHE", 48)


def resident_fraction(path: Path) -> float:
    """Share of the file's pages in the page cache, via mmap + mincore."""
    size = path.stat().st_size
    fd = os.open(path, os.O_RDONLY)
    try:
        address = _libc.mmap(None, size, 1, 1, fd, 0)  # PROT_READ, MAP_SHARED
        if address in (None, ctypes.c_void_p(-1).value):
            raise HarnessError(f"mmap failed for {path}: errno {ctypes.get_errno()}")
        try:
            page = os.sysconf("SC_PAGE_SIZE")
            pages = (size + page - 1) // page
            vector = ctypes.create_string_buffer(pages)
            if _libc.mincore(address, size, vector) != 0:
                raise HarnessError(f"mincore failed: errno {ctypes.get_errno()}")
            return sum(1 for byte in vector.raw[:pages] if byte & 1) / pages
        finally:
            _libc.munmap(address, size)
    finally:
        os.close(fd)


def uncached_copy(source: Path, target: Path) -> None:
    """Copy with F_NOCACHE on both descriptors so the copy is not left in the page cache."""
    source_fd = os.open(source, os.O_RDONLY)
    target_fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
    try:
        fcntl.fcntl(source_fd, F_NOCACHE, 1)
        fcntl.fcntl(target_fd, F_NOCACHE, 1)
        while True:
            chunk = os.read(source_fd, 1 << 20)
            if not chunk:
                break
            os.write(target_fd, chunk)
        os.fsync(target_fd)
    finally:
        os.close(source_fd)
        os.close(target_fd)


class ColdLauncher:
    """Rewrites the wrapper chain of a Nix-built nshell to use a private core copy.

    bin/nshell execs bin/.nshell-wrapped (by store path), which execs sbcl with
    --core <nshell.core>. The launcher copies both scripts with the next hop
    replaced, so each sample can start from a freshly written, uncached core.
    """

    def __init__(self, binary: Path, root: Path):
        self.root = Path(tempfile.mkdtemp(prefix="cold-", dir=root))
        outer = binary.read_text(encoding="utf-8", errors="replace")
        hops = re.findall(r'exec -a "\$0" "([^"]+)"', outer)
        if not hops:
            raise HarnessError("cold startup: wrapper has no exec -a hop")
        inner_path = Path(hops[-1])
        inner = inner_path.read_text(encoding="utf-8", errors="replace")
        core = re.search(r"--core\s+(\S+)", inner)
        if core is None:
            raise HarnessError("cold startup: inner wrapper has no --core")
        self.core = Path(core.group(1).strip("'\""))
        self.core_copy = self.root / "nshell.core"
        inner_copy = self.root / "nshell-wrapped"
        inner_copy.write_text(inner.replace(core.group(1), str(self.core_copy)), encoding="utf-8")
        inner_copy.chmod(0o755)
        self.launcher = self.root / "nshell"
        self.launcher.write_text(outer.replace(str(inner_path), str(inner_copy)), encoding="utf-8")
        self.launcher.chmod(0o755)

    def prepare(self) -> float:
        if self.core_copy.exists():
            self.core_copy.unlink()
        uncached_copy(self.core, self.core_copy)
        return resident_fraction(self.core_copy)


# --- fixtures -------------------------------------------------------------

def make_fixtures(root: Path) -> dict[str, Path]:
    work = root / "work"
    big = work / "big"
    small = work / "small"
    big.mkdir(parents=True)
    small.mkdir()
    for index in range(BIG_DIR_ENTRIES):
        (big / f"item-{index:05d}").touch()
    (big / UNIQUE_NAME).touch()
    for index in range(9):
        (small / f"file-{index}").touch()
    (small / UNIQUE_NAME).touch()
    entries = sum(1 for _ in os.scandir(big))
    if entries != BIG_DIR_ENTRIES + 1:
        raise HarnessError(f"fixture big/ has {entries} entries, expected {BIG_DIR_ENTRIES + 1}")
    history = root / "history-10k"
    with history.open("xb") as stream:
        for index in range(HISTORY_ENTRIES):
            payload = (
                f'(:text "echo NSHELL_P07_RECORD_{index:05d}" :timestamp {1_700_000_000 + index} '
                ':cwd "/p07" :exit-code 0 :duration-ms 1 :origin :typed :host "p07")'
            ).encode("ascii")
            stream.write(HISTORY_PREFIX + str(len(payload)).encode("ascii") + b"\n" + payload + b"\n")
    return {"work": work, "history": history}


# --- measurement primitives ----------------------------------------------

def new_marker() -> str:
    return f"P07_{uuid.uuid4().hex[:12]}> "


def start_session(argv: list[str], fixtures: dict[str, Path], root: Path,
                  history: bool = False) -> tuple[Session, Isolation, bytes, int]:
    isolation = Isolation(root, fixtures["history"] if history else None)
    marker = new_marker()
    session = Session(argv, fixtures["work"], isolation.env(marker))
    marker_bytes = marker.encode()
    try:
        ready_ns = session.wait_for(session.prompt_frame_after(marker_bytes), 0, PROMPT_TIMEOUT)
    except BaseException:
        session.close()
        isolation.remove()
        raise
    return session, isolation, marker_bytes, ready_ns - session.started_ns


def history_guard(session: Session) -> str | None:
    """Check that the 10k history was loaded: a prefix must get a history suggestion."""
    typed = "echo NSHELL_P07_R"
    start, _ = session.send(PASTE_START + typed.encode() + PASTE_END)
    session.wait_for(session.frame_after, start, FRAME_TIMEOUT)
    session.drain(0.2)
    shown = visible(bytes(session.data[start:]))
    if "NSHELL_P07_RECORD_" not in shown:
        return "history suggestion missing after typing 'echo NSHELL_P07_R'"
    return None


def measure_interactive(binary: Path, fixtures: dict[str, Path], root: Path, history: bool,
                        guard: bool) -> dict[str, Any]:
    session, isolation, _, elapsed_ns = start_session([str(binary)], fixtures, root, history)
    try:
        result: dict[str, Any] = {"value": elapsed_ns / 1e6}
        if guard and history:
            failure = history_guard(session)
            if failure:
                result["guard_failure"] = failure
        return result
    finally:
        session.close()
        isolation.remove()


def measure_cold(launcher: ColdLauncher, fixtures: dict[str, Path], root: Path) -> dict[str, Any]:
    resident = launcher.prepare()
    result = measure_interactive(launcher.launcher, fixtures, root, False, False)
    result["core_resident_fraction"] = resident
    if resident > 0.01:
        result["guard_failure"] = f"core copy {resident:.1%} resident before launch"
    return result


def measure_command(argv: list[str], fixtures: dict[str, Path], root: Path) -> dict[str, Any]:
    isolation = Isolation(root)
    try:
        started = time.perf_counter_ns()
        completed = subprocess.run(argv, cwd=fixtures["work"], env=isolation.env(), stdin=subprocess.DEVNULL,
                                   capture_output=True, timeout=COMMAND_TIMEOUT)
        elapsed = (time.perf_counter_ns() - started) / 1e6
        if completed.returncode != 0:
            raise HarnessError(f"{argv[1:]} exited {completed.returncode}: {completed.stderr[-200:]!r}")
        return {"value": elapsed}
    finally:
        isolation.remove()


def json_support(binary: Path, fixtures: dict[str, Path], root: Path,
                 timeout: float = COMMAND_TIMEOUT) -> str | None:
    """None when `--json --command true` prints JSON; the reason when the binary rejects `--json`.

    Only nshell's usage-error path (exit 1 with the usage text on stderr)
    counts as "not supported". Any other outcome raises HarnessError, so a
    broken or slow binary is reported as unmeasured instead of excluded.
    """
    isolation = Isolation(root)
    try:
        completed = subprocess.run([str(binary), "--json", "--command", "true"], cwd=fixtures["work"],
                                   env=isolation.env(), stdin=subprocess.DEVNULL, capture_output=True,
                                   timeout=timeout)
    except subprocess.TimeoutExpired as error:
        raise HarnessError(f"--json probe: no exit within {timeout}s") from error
    finally:
        isolation.remove()
    stderr = completed.stderr.decode("utf-8", "replace")
    if completed.returncode == 1 and "Usage: nshell" in stderr:
        return "--json rejected as a usage error (exit 1 with usage text)"
    if completed.returncode != 0:
        raise HarnessError(f"--json probe exited {completed.returncode}: {stderr[-200:]!r}")
    lines = completed.stdout.decode("utf-8", "replace").strip().splitlines()
    try:
        json.loads(lines[-1])
    except (ValueError, IndexError) as error:
        raise HarnessError(f"--json probe printed no JSON on its last line: {lines[-1:]!r}") from error
    return None


def run_key_session(binary: Path, fixtures: dict[str, Path], root: Path, prefill: str, char: str,
                    warmup_keys: int, keys: int) -> dict[str, Any]:
    session, isolation, _, _ = start_session([str(binary)], fixtures, root)
    try:
        session.drain(0.1)
        rss_idle = session.rss_kb()
        if prefill:
            start, _ = session.send(PASTE_START + prefill.encode() + PASTE_END)
            session.wait_for(session.frame_showing(prefill[-20:].rstrip()), start, FRAME_TIMEOUT)
            # Autosuggest may redraw again after the paste; let it finish so a
            # late frame is not taken for the first key's redraw.
            session.drain(0.3)
        latencies = []
        guard_failure = None
        stale_frames = 0
        expected_insert = prefill[-20:] + char
        total = warmup_keys + keys
        if total % 2:
            raise HarnessError("warm-up plus measured keys must be even so the buffer returns to the prefill")
        for index in range(total):
            insert = index % 2 == 0
            start, t0 = session.send(char.encode() if insert else BACKSPACE)
            if insert:
                # The first frame that shows the typed character is this key's
                # redraw; earlier frames are late redraws of the previous state.
                t1 = session.wait_for(session.frame_showing(expected_insert), start, FRAME_TIMEOUT)
                stale_frames += session.frames_between(start, len(session.data)) - 1
            else:
                t1 = session.wait_for(session.frame_after, start, FRAME_TIMEOUT)
            if index >= warmup_keys:
                latencies.append((t1 - t0) / 1e6)
        session.drain(0.1)
        tail = prefill[-30:].rstrip()
        last_frame = bytes(session.data[session.data.rfind(b"\r\x1b[2K"):])
        if tail and guard_failure is None and tail not in visible(last_frame):
            guard_failure = "final frame does not show the prefilled buffer"
        rss_after = session.rss_kb()
        return {"latencies": latencies, "rss_idle_kb": rss_idle, "rss_after_kb": rss_after,
                "guard_failure": guard_failure, "stale_frames": stale_frames, "session": session}
    finally:
        session.close()
        isolation.remove()


def run_tab_session(binary: Path, fixtures: dict[str, Path], root: Path, warmup: int,
                    samples: int) -> dict[str, Any]:
    session, isolation, _, _ = start_session([str(binary)], fixtures, root)
    results: dict[str, list[float]] = {}
    try:
        session.drain(0.1)
        for name, prefix in TAB_VARIANTS:
            values = []
            for index in range(warmup + samples):
                start, _ = session.send(PASTE_START + prefix.encode() + PASTE_END)
                session.wait_for(session.frame_after, start, FRAME_TIMEOUT)
                session.drain(0.05)
                start, t0 = session.send(b"\t")

                def completed(offset: int) -> bool:
                    index_found = visible(bytes(session.data[offset:])).find(UNIQUE_NAME)
                    return index_found >= 0 and session.data.find(FRAME_END, offset) >= 0

                t1 = session.wait_for(completed, start, FRAME_TIMEOUT)
                if index >= warmup:
                    values.append((t1 - t0) / 1e6)
                session.drain(0.05)
                start, _ = session.send(CTRL_U)
                session.wait_for(session.frame_after, start, FRAME_TIMEOUT)
                session.drain(0.05)
            results[name] = values
        return {"variants": results}
    finally:
        session.close()
        isolation.remove()


def run_prompt_session(binary: Path, fixtures: dict[str, Path], root: Path, warmup: int,
                       samples: int) -> dict[str, Any]:
    session, isolation, marker, _ = start_session([str(binary)], fixtures, root)
    try:
        session.drain(0.1)
        values = []
        for index in range(warmup + samples):
            start, t0 = session.send(b"\r")
            t1 = session.wait_for(session.prompt_frame_after(marker), start, FRAME_TIMEOUT)
            if index >= warmup:
                values.append((t1 - t0) / 1e6)
            session.drain(0.1)
        return {"values": values}
    finally:
        session.close()
        isolation.remove()


# --- orchestration --------------------------------------------------------

class Metric:
    def __init__(self, name: str, kind: str, unit: str, planned: int):
        self.data: dict[str, Any] = {
            "name": name, "kind": kind, "unit": unit, "planned_groups_per_arm": planned,
            "blocks": [], "errors": [], "guard_failures": [], "support": {"A": True, "B": True},
            "extra": [],
        }
        # Set when the metric cannot be measured at all; its samples stay
        # empty, so perfstats judges it inconclusive from the recorded errors.
        self.skip = False

    def new_block(self) -> None:
        self.data["blocks"].append({"A": [], "B": []})

    def add(self, arm: str, values: list[float]) -> None:
        self.data["blocks"][-1][arm].append(values)


ABBA = ("A", "B", "B", "A")


def log(message: str) -> None:
    print(f"[perf {time.strftime('%H:%M:%S')}] {message}", file=sys.stderr, flush=True)


def run(args: argparse.Namespace) -> dict[str, Any]:
    binaries = {"A": Path(args.a).resolve(), "B": Path(args.b).resolve()}
    for arm, path in binaries.items():
        if not path.is_file() or not os.access(path, os.X_OK):
            raise SystemExit(f"arm {arm}: not an executable file: {path}")
    root = Path(tempfile.mkdtemp(prefix="nshell-perf-"))
    raw: dict[str, Any] = {
        "schema": "nshell-perf-raw/1",
        "arms": {arm: str(path) for arm, path in binaries.items()},
        "uptime": {"before": uptime()},
        "host": {"platform": platform.platform(), "machine": platform.machine(), "python": platform.python_version()},
        "config": {
            "startup_blocks": args.startup_blocks, "startup_warmup_blocks": 1,
            "key_blocks": args.key_blocks, "path_key_blocks": args.path_key_blocks,
            "keys": args.keys, "warmup_keys": args.warmup_keys,
            "tab_blocks": args.tab_blocks, "tab_samples": args.tab_samples, "tab_warmup": 2,
            "prompt_blocks": args.prompt_blocks, "prompt_samples": args.prompt_samples, "prompt_warmup": 3,
            "order": "ABBA within every block", "bootstrap": "hierarchical (block, process, value), 2000 iterations",
            "terminal": f"{TERMINAL_SIZE[1]}x{TERMINAL_SIZE[0]}", "path": PATH_VALUE,
        },
        "metrics": [],
        "notes": [],
    }
    metrics: list[Metric] = []
    try:
        fixtures = make_fixtures(root)
        log(f"fixtures ready in {root}")
        cold = {}
        cold_metric = Metric("startup.interactive_cold", "startup", "ms", 2 * args.startup_blocks)
        for arm, path in binaries.items():
            try:
                cold[arm] = ColdLauncher(path, root)
            except (HarnessError, OSError) as error:
                cold_metric.skip = True
                cold_metric.data["errors"].append(f"{arm}: {error}")
        json_metric = Metric("startup.json_command_true", "startup", "ms", 2 * args.startup_blocks)
        for arm, path in binaries.items():
            try:
                rejected = json_support(path, fixtures, root)
            except (HarnessError, OSError) as error:
                json_metric.skip = True
                json_metric.data["errors"].append(f"{arm}: {error}")
                continue
            if rejected is not None:
                json_metric.data["support"][arm] = False
                json_metric.data.setdefault("unsupported", {})[arm] = rejected

        startup: list[tuple[Metric, Callable[[str, bool], dict[str, Any]]]] = [
            (Metric("startup.interactive_warm", "startup", "ms", 2 * args.startup_blocks),
             lambda arm, guard: measure_interactive(binaries[arm], fixtures, root, False, guard)),
            (Metric("startup.interactive_history_10k", "startup", "ms", 2 * args.startup_blocks),
             lambda arm, guard: measure_interactive(binaries[arm], fixtures, root, True, guard)),
            (cold_metric, lambda arm, guard: measure_cold(cold[arm], fixtures, root)),
            (Metric("startup.c_true", "startup", "ms", 2 * args.startup_blocks),
             lambda arm, guard: measure_command([str(binaries[arm]), "-c", "true"], fixtures, root)),
            (Metric("startup.command_true", "startup", "ms", 2 * args.startup_blocks),
             lambda arm, guard: measure_command([str(binaries[arm]), "--command", "true"], fixtures, root)),
            (json_metric,
             lambda arm, guard: measure_command([str(binaries[arm]), "--json", "--command", "true"], fixtures, root)),
        ]
        metrics.extend(metric for metric, _ in startup)
        for block in range(1 + args.startup_blocks):
            warm = block == 0
            log(f"startup block {block}{' (warm-up, discarded)' if warm else ''}")
            for metric, action in startup:
                if metric.skip or not all(metric.data["support"].values()):
                    continue
                if not warm:
                    metric.new_block()
                for arm in ABBA:
                    try:
                        result = action(arm, warm)
                    except (HarnessError, OSError, subprocess.TimeoutExpired) as error:
                        metric.data["errors"].append(f"{arm} block {block}: {error}")
                        continue
                    if result.get("guard_failure"):
                        metric.data["guard_failures"].append(f"{arm}: {result['guard_failure']}")
                    if "core_resident_fraction" in result:
                        metric.data["extra"].append({"arm": arm, "block": block,
                                                     "core_resident_fraction": result["core_resident_fraction"]})
                    if not warm:
                        metric.add(arm, [result["value"]])

        rss_idle = Metric("rss.idle_kb", "rss", "KiB", 0)
        rss_metrics: dict[str, Metric] = {}
        metrics.append(rss_idle)
        for name, prefill, char in KEY_SCENARIOS:
            blocks = args.path_key_blocks if name == "key.path_20k" else args.key_blocks
            metric = Metric(name, "key", "ms", 2 * blocks)
            peak = Metric(f"rss.peak_kb.{name.split('.', 1)[1]}", "rss", "KiB", 2 * blocks)
            rss_metrics[name] = peak
            metrics.extend([metric, peak])
            for block in range(blocks):
                log(f"{name} block {block + 1}/{blocks}")
                metric.new_block()
                peak.new_block()
                if name == KEY_SCENARIOS[0][0]:
                    rss_idle.new_block()
                for arm in ABBA:
                    try:
                        result = run_key_session(binaries[arm], fixtures, root, prefill, char,
                                                 args.warmup_keys, args.keys)
                    except (HarnessError, OSError) as error:
                        metric.data["errors"].append(f"{arm} block {block}: {error}")
                        continue
                    if result["guard_failure"]:
                        metric.data["guard_failures"].append(f"{arm}: {result['guard_failure']}")
                    if result["stale_frames"]:
                        metric.data["extra"].append({"arm": arm, "block": block, "stale_frames_skipped": result["stale_frames"]})
                    metric.add(arm, result["latencies"])
                    peak_kb = result["session"].peak_rss_kb()
                    if peak_kb is not None:
                        peak.add(arm, [float(peak_kb)])
                    if result["rss_idle_kb"] is not None and name == KEY_SCENARIOS[0][0]:
                        rss_idle.add(arm, [float(result["rss_idle_kb"])])
        rss_idle.data["planned_groups_per_arm"] = 2 * args.key_blocks

        tab_metrics = {name: Metric(name, "tab", "ms", 2 * args.tab_blocks) for name, _ in TAB_VARIANTS}
        metrics.extend(tab_metrics.values())
        for block in range(args.tab_blocks):
            log(f"tab block {block + 1}/{args.tab_blocks}")
            for metric in tab_metrics.values():
                metric.new_block()
            for arm in ABBA:
                try:
                    result = run_tab_session(binaries[arm], fixtures, root, 2, args.tab_samples)
                except (HarnessError, OSError) as error:
                    for metric in tab_metrics.values():
                        metric.data["errors"].append(f"{arm} block {block}: {error}")
                    continue
                for name, values in result["variants"].items():
                    tab_metrics[name].add(arm, values)

        prompt = Metric("prompt.empty_enter", "prompt", "ms", 2 * args.prompt_blocks)
        metrics.append(prompt)
        for block in range(args.prompt_blocks):
            log(f"prompt block {block + 1}/{args.prompt_blocks}")
            prompt.new_block()
            for arm in ABBA:
                try:
                    result = run_prompt_session(binaries[arm], fixtures, root, 3, args.prompt_samples)
                except (HarnessError, OSError) as error:
                    prompt.data["errors"].append(f"{arm} block {block}: {error}")
                    continue
                prompt.add(arm, result["values"])
    except KeyboardInterrupt:
        raw["fatal_error"] = "interrupted"
    except (HarnessError, OSError) as error:
        raw["fatal_error"] = f"{type(error).__name__}: {error}"
    finally:
        shutil.rmtree(root, ignore_errors=True)
        raw["uptime"]["after"] = uptime()
        raw["metrics"] = [metric.data for metric in metrics]
    return raw


def main() -> int:
    parser = argparse.ArgumentParser(description="Interleaved ABBA measurement of two nshell binaries.")
    parser.add_argument("--a", required=True, help="baseline binary (arm A)")
    parser.add_argument("--b", required=True, help="candidate binary (arm B)")
    parser.add_argument("--out", required=True, help="raw JSON output path")
    parser.add_argument("--startup-blocks", type=int, default=12)
    parser.add_argument("--key-blocks", type=int, default=2)
    parser.add_argument("--path-key-blocks", type=int, default=2)
    parser.add_argument("--keys", type=int, default=200)
    parser.add_argument("--warmup-keys", type=int, default=20)
    parser.add_argument("--tab-blocks", type=int, default=2)
    parser.add_argument("--tab-samples", type=int, default=15)
    parser.add_argument("--prompt-blocks", type=int, default=2)
    parser.add_argument("--prompt-samples", type=int, default=30)
    args = parser.parse_args()
    for name in ("startup_blocks", "key_blocks", "path_key_blocks", "keys", "tab_blocks", "tab_samples",
                 "prompt_blocks", "prompt_samples"):
        if getattr(args, name) < 1:
            parser.error(f"--{name.replace('_', '-')} must be positive")
    if args.warmup_keys < 0 or (args.keys + args.warmup_keys) % 2:
        parser.error("--keys plus --warmup-keys must be even and warm-up nonnegative")
    started = time.monotonic()
    raw = run(args)
    raw["elapsed_seconds"] = round(time.monotonic() - started, 1)
    Path(args.out).write_text(json.dumps(raw, indent=1) + "\n", encoding="utf-8")
    log(f"raw results written to {args.out} ({raw['elapsed_seconds']} s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
