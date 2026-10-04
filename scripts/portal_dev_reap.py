"""Audit Portal dev stacks and safely stop the ones that are provably finished.

A stack is stoppable when Herdr policy says so ("stale") or when its pull
request is merged or closed, its tree is clean with every commit in the PR, and
no agent is working in it ("pr-merged"/"pr-closed"). Only "stale" is deletion authority for
disk maintenance; the PR classes only ever stop a runtime.
"""

from __future__ import annotations

import argparse
import json
import os
import pwd
import re
import shlex
import shutil
import socket
import stat
import subprocess
import sys
import time
import urllib.request
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

PORT_FLAGS = {
    "WORKTREE_PORT": "--worktree-port",
    "PC_PORT_NUM": "--pc-port-num",
    "PORTAL_PORT": "--portal-port",
    "ADMIN_PORT": "--admin-port",
    "POSTGRES_PORT": "--postgres-port",
    "REDIS_PORT": "--redis-port",
    "MAILPIT_UI_PORT": "--mailpit-ui-port",
    "MAILPIT_SMTP_PORT": "--mailpit-smtp-port",
    "GARAGE_S3_PORT": "--garage-s3-port",
    "GARAGE_RPC_PORT": "--garage-rpc-port",
    "GARAGE_ADMIN_PORT": "--garage-admin-port",
    "IMGPROXY_PORT": "--imgproxy-port",
    "WORKER_DASHBOARD_PORT": "--worker-dashboard-port",
}

PRIMARY_PORTS = {
    "WORKTREE_PORT": "3000",
    "PC_PORT_NUM": "8081",
    "PORTAL_PORT": "4000",
    "ADMIN_PORT": "4001",
    "MAILPIT_UI_PORT": "8025",
    "MAILPIT_SMTP_PORT": "1025",
    "GARAGE_S3_PORT": "3900",
    "GARAGE_RPC_PORT": "3901",
    "GARAGE_ADMIN_PORT": "3903",
    "IMGPROXY_PORT": "8600",
    "WORKER_DASHBOARD_PORT": "8671",
    "POSTGRES_PORT": "5432",
    "REDIS_PORT": "6379",
}

ENV_MAX_BYTES = 16 * 1024
ENV_NAME_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
PORT_RE = re.compile(r"[0-9]+")
STORE_PATH_RE = re.compile(r"/nix/store/[0-9a-z]{32}-[^/\s]+")

UNRESOLVED_ERROR = "unresolved local tasks; review suggested paths and supply --associate"
AGENT_COMMANDS = {"claude", "codex"}
# Finished-PR classes stop runtimes only; "stale" alone is deletion authority.
EVIDENCE_CLASSES = {"MERGED": "pr-merged", "CLOSED": "pr-closed"}
STOPPABLE_CLASSES = {"stale", *EVIDENCE_CLASSES.values()}
RESTART_WARNING = 20


class ReapError(RuntimeError):
    """An expected audit error that should be shown without a traceback."""


@dataclass(frozen=True)
class ProcessInfo:
    pid: int
    ppid: int
    started: str
    age: str
    rss_kb: int
    command: str


@dataclass(frozen=True)
class ProcessRef:
    pid: int
    ppid: int | None
    command: str
    cwd: str | None
    identity: str | None
    age: str | None
    ports: tuple[int, ...]


@dataclass
class Target:
    kind: str
    path: Path
    name: str
    ports: dict[str, str]
    env_values: dict[str, str] | None = None
    errors: list[str] = field(default_factory=list)

    @property
    def pc_port(self) -> str | None:
        return self.ports.get("PC_PORT_NUM")


@dataclass
class TargetReport:
    kind: str
    path: str
    name: str
    pc_port: str | None
    classification: str
    runtime: str
    actionable: bool
    protected: bool
    reasons: list[str]
    listeners: list[dict[str, Any]]
    foreign_listeners: list[dict[str, Any]]
    manager_controlled_listeners: list[dict[str, Any]]
    extra_owned_listeners: list[dict[str, Any]]
    fingerprint: list[list[Any]]
    # True when stoppability rests on PR evidence or a reviewed --abandoned
    # selection instead of a complete Herdr inventory.
    herdr_independent: bool = False
    age: str | None = None
    process_count: int = 0
    rss_mb: int = 0
    evidence: dict[str, Any] = field(default_factory=dict)
    health: list[str] = field(default_factory=list)


@dataclass
class Discovery:
    paths: list[Path] = field(default_factory=list)
    error: str | None = None
    evidence: list[dict[str, Any]] = field(default_factory=list)
    unresolved: list[dict[str, Any]] = field(default_factory=list)
    node: str = field(default_factory=socket.gethostname)


@dataclass
class Audit:
    schema_version: int
    repository: str
    active_source: str
    active_error: str | None
    active_paths: list[str]
    protected_paths: list[str]
    targets: list[TargetReport]
    unknown_process_compose: list[dict[str, Any]]
    abandoned_paths: list[str] = field(default_factory=list)
    outside_active: bool = False
    associations: list[str] = field(default_factory=list)
    discovery: Discovery = field(default_factory=Discovery)
    system: dict[str, Any] = field(default_factory=dict)


def run(
    args: list[str],
    *,
    cwd: Path | None = None,
    timeout: float = 15,
    capture: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=cwd,
        check=False,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        timeout=timeout,
    )


def canonical(path: Path | str) -> Path:
    return Path(os.path.realpath(os.path.abspath(os.fspath(path))))


def path_is_within(parent: Path, child: Path) -> bool:
    try:
        canonical(child).relative_to(canonical(parent))
        return True
    except ValueError:
        return False


def require_tool(name: str) -> str:
    path = shutil.which(name)
    if path is None:
        raise ReapError(f"required command is not available: {name}")
    return path


def validate_repository(path: Path) -> Path:
    root = canonical(path)
    marker = root / ".config" / "wt.toml"
    lifecycle = root / "nix" / "worktree-lifecycle"
    if not marker.is_file() or not lifecycle.is_dir():
        raise ReapError(f"not a Portal CMS checkout: {root}")
    result = run([require_tool("git"), "-C", str(root), "rev-parse", "--show-toplevel"])
    if result.returncode != 0:
        raise ReapError(
            f"could not inspect Portal Git worktrees: {result.stderr.strip()}"
        )
    return canonical(result.stdout.strip())


def parse_git_worktrees(root: Path) -> list[Path]:
    result = run(
        [require_tool("git"), "-C", str(root), "worktree", "list", "--porcelain"]
    )
    if result.returncode != 0:
        raise ReapError(f"git worktree inventory failed: {result.stderr.strip()}")
    paths = [
        canonical(line.removeprefix("worktree "))
        for line in result.stdout.splitlines()
        if line.startswith("worktree ")
    ]
    return list(dict.fromkeys(paths))


def git_common_dir(root: Path) -> Path:
    result = run(
        [require_tool("git"), "-C", str(root), "rev-parse", "--git-common-dir"]
    )
    if result.returncode != 0:
        raise ReapError(
            f"could not locate Git common directory: {result.stderr.strip()}"
        )
    value = Path(result.stdout.strip())
    if not value.is_absolute():
        value = root / value
    return canonical(value)


def parse_env_file(path: Path) -> dict[str, str]:
    try:
        info = path.lstat()
    except FileNotFoundError as error:
        raise ReapError("missing .env.worktree") from error
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise ReapError(".env.worktree is not a regular file")
    if info.st_uid != os.getuid():
        raise ReapError(".env.worktree is not owned by the current user")
    if stat.S_IMODE(info.st_mode) != 0o600:
        raise ReapError(".env.worktree permissions are not 0600")
    if info.st_size > ENV_MAX_BYTES:
        raise ReapError(".env.worktree is unexpectedly large")

    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            words = shlex.split(line, comments=True, posix=True)
        except ValueError as error:
            raise ReapError(".env.worktree contains invalid shell syntax") from error
        if len(words) != 2 or words[0] != "export" or "=" not in words[1]:
            raise ReapError(".env.worktree contains an unexpected entry")
        key, value = words[1].split("=", 1)
        if key in values:
            raise ReapError(f".env.worktree repeats {key}")
        values[key] = value

    missing = [
        key
        for key in ("WORKTREE_NAME", "PUBLIC_ENV__WORKTREE_NAME", *PORT_FLAGS)
        if key not in values
    ]
    if missing:
        raise ReapError(f".env.worktree is missing {', '.join(missing)}")
    if values["WORKTREE_NAME"] != values["PUBLIC_ENV__WORKTREE_NAME"]:
        raise ReapError(".env.worktree has mismatched worktree names")
    if not ENV_NAME_RE.fullmatch(values["WORKTREE_NAME"]):
        raise ReapError(".env.worktree has an invalid worktree name")

    ports: list[int] = []
    for key in PORT_FLAGS:
        value = values[key]
        if not PORT_RE.fullmatch(value) or not 1 <= int(value) <= 65535:
            raise ReapError(f".env.worktree has an invalid {key}")
        ports.append(int(value))
    if len(ports) != len(set(ports)):
        raise ReapError(".env.worktree has duplicate allocated ports")
    return values


def target_from_path(kind: str, path: Path) -> Target:
    try:
        values = parse_env_file(path / ".env.worktree")
    except (OSError, UnicodeError, ReapError) as error:
        return Target(
            kind=kind,
            path=canonical(path),
            name=path.name,
            ports={},
            errors=[str(error)],
        )
    return Target(
        kind=kind,
        path=canonical(path),
        name=values["WORKTREE_NAME"],
        ports={key: values[key] for key in PORT_FLAGS},
        env_values=values,
    )


def discover_targets(root: Path) -> list[Target]:
    worktrees = parse_git_worktrees(root)
    targets = [
        Target(kind="primary", path=root, name="primary", ports=dict(PRIMARY_PORTS))
    ]
    for path in worktrees:
        if path != root:
            targets.append(target_from_path("worktree", path))

    registered = {target.path for target in targets}
    trash = git_common_dir(root) / "wt" / "trash"
    if trash.is_dir():
        for env_file in sorted(trash.glob("*/.env.worktree")):
            path = canonical(env_file.parent)
            if path not in registered:
                targets.append(target_from_path("trash", path))
    return targets


def parse_lsof_listeners(output: str) -> dict[int, dict[str, Any]]:
    processes: dict[int, dict[str, Any]] = {}
    current: dict[str, Any] | None = None
    for line in output.splitlines():
        if not line:
            continue
        field_name, value = line[0], line[1:]
        if field_name == "p":
            try:
                pid = int(value)
            except ValueError:
                current = None
                continue
            current = processes.setdefault(
                pid, {"pid": pid, "command": "", "ports": set()}
            )
        elif current is not None and field_name == "c":
            current["command"] = value
        elif current is not None and field_name == "n":
            match = re.search(r":([0-9]+)$", value)
            if match:
                current["ports"].add(int(match.group(1)))
    return processes


def parse_process_snapshot(output: str) -> dict[int, ProcessInfo]:
    table: dict[int, ProcessInfo] = {}
    for line in output.splitlines():
        # pid ppid lstart(5 words) etime rss command
        parts = line.split(None, 9)
        if len(parts) < 10 or not parts[0].isdigit() or not parts[1].isdigit():
            continue
        table[int(parts[0])] = ProcessInfo(
            pid=int(parts[0]),
            ppid=int(parts[1]),
            started=" ".join(parts[2:7]),
            age=parts[7],
            rss_kb=int(parts[8]) if parts[8].isdigit() else 0,
            command=" ".join(parts[9].split()),
        )
    return table


def process_snapshot() -> dict[int, ProcessInfo]:
    """One ps call for the whole machine; per-process calls time out under load."""
    ps = shutil.which("ps") or "/bin/ps"
    columns = ("pid=", "ppid=", "lstart=", "etime=", "rss=", "command=")
    command = [ps, "-A", "-ww"]
    for column in columns:
        command.extend(["-o", column])
    try:
        result = run(command, timeout=60)
    except subprocess.TimeoutExpired as error:
        raise ReapError("process inventory timed out") from error
    if result.returncode != 0:
        raise ReapError(f"process inventory failed: {result.stderr.strip()}")
    return parse_process_snapshot(result.stdout)


def process_cwds(lsof: str, pids: set[int]) -> dict[int, str]:
    """Batched cwd lookup; a slow lsof leaves cwds unknown instead of aborting."""
    if not pids:
        return {}
    try:
        result = run(
            [lsof, "-nP", "-a", "-p", ",".join(map(str, sorted(pids))), "-d", "cwd", "-Fpn"],
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        return {}
    cwds: dict[int, str] = {}
    pid: int | None = None
    # lsof exits 1 when any listed pid has gone; the rest is still reported.
    for line in result.stdout.splitlines():
        if line.startswith("p"):
            pid = int(line[1:]) if line[1:].isdigit() else None
        elif line.startswith("n") and len(line) > 1 and pid is not None:
            cwds.setdefault(pid, str(canonical(line[1:])))
    return cwds


def identity_of(info: ProcessInfo | None) -> str | None:
    return f"{info.started} {info.command}" if info and info.command else None


def listener_processes(snapshot: dict[int, ProcessInfo]) -> list[ProcessRef]:
    lsof = require_tool("lsof")
    username = pwd.getpwuid(os.getuid()).pw_name
    try:
        result = run(
            [lsof, "-nP", "-a", "-u", username, "-iTCP", "-sTCP:LISTEN", "-Fpcn"],
            timeout=60,
        )
    except subprocess.TimeoutExpired as error:
        raise ReapError("listener inventory timed out") from error
    if result.returncode not in (0, 1):
        raise ReapError(f"listener inventory failed: {result.stderr.strip()}")
    parsed = parse_lsof_listeners(result.stdout)
    cwds = process_cwds(lsof, set(parsed))
    if parsed and not cwds:
        # Without cwds every stack would look stopped; refuse to report that.
        raise ReapError("could not read listener working directories; retry")
    processes: list[ProcessRef] = []
    for pid, entry in sorted(parsed.items()):
        info = snapshot.get(pid)
        processes.append(
            ProcessRef(
                pid=pid,
                ppid=info.ppid if info else None,
                command=entry["command"],
                cwd=cwds.get(pid),
                identity=identity_of(info),
                age=info.age if info else None,
                ports=tuple(sorted(entry["ports"])),
            )
        )
    return processes


def agent_checkouts(snapshot: dict[int, ProcessInfo]) -> list[Path]:
    """Working directories of live Claude/Codex processes, visible without Herdr."""
    pids = {
        info.pid
        for info in snapshot.values()
        if Path(info.command.split(" ", 1)[0]).name in AGENT_COMMANDS
    }
    lsof = shutil.which("lsof")
    if not pids or lsof is None:
        return []
    return [Path(cwd) for cwd in dict.fromkeys(process_cwds(lsof, pids).values())]


def checkout_evidence(path: Path) -> dict[str, Any]:
    """Git and pull-request facts for a checkout; a missing fact never implies staleness."""
    evidence: dict[str, Any] = {}
    git = shutil.which("git")
    if git is None or not path.is_dir():
        return evidence
    try:
        status = run([git, "-C", str(path), "status", "--porcelain=v2", "--branch"], timeout=30)
        if status.returncode != 0:
            return evidence
        dirty = 0
        for line in status.stdout.splitlines():
            if line.startswith("# branch.oid "):
                evidence["head"] = line.split(" ", 2)[2]
            elif line.startswith("# branch.head "):
                evidence["branch"] = line.split(" ", 2)[2]
            elif line and not line.startswith("#"):
                dirty += 1
        evidence["dirty"] = dirty
        committed = run([git, "-C", str(path), "log", "-1", "--format=%ct"], timeout=30)
        if committed.returncode == 0 and committed.stdout.strip().isdigit():
            evidence["last_commit_days"] = int((time.time() - int(committed.stdout.strip())) // 86400)
        branch, gh = evidence.get("branch"), shutil.which("gh")
        if gh is None or not branch or branch == "(detached)":
            return evidence
        listed = run(
            [gh, "pr", "list", "--head", branch, "--state", "all", "--limit", "20",
             "--json", "number,state,headRefOid"],
            cwd=path, timeout=30,
        )
        if listed.returncode != 0:
            return evidence
        pulls = [item for item in json.loads(listed.stdout) if isinstance(item, dict)]
        # An open PR outranks an older merged or closed one for the same branch.
        pull = next((item for item in pulls if item.get("state") == "OPEN"), pulls[0] if pulls else None)
        if pull:
            evidence["pr_number"] = pull.get("number")
            evidence["pr_state"] = pull.get("state")
            pr_head, head = pull.get("headRefOid"), evidence.get("head")
            # A checkout merely behind the PR (remote merge-from-main) has no local-only commits.
            evidence["pr_contains_head"] = bool(pr_head and head) and (
                pr_head == head
                or run([git, "-C", str(path), "merge-base", "--is-ancestor", head, pr_head],
                       timeout=30).returncode == 0
            )
    except (OSError, ValueError, subprocess.TimeoutExpired):
        pass
    return evidence


def evidence_class(evidence: dict[str, Any]) -> str | None:
    """A finished PR, nothing uncommitted, and no local commits beyond the PR head."""
    if evidence.get("dirty") != 0 or evidence.get("pr_contains_head") is not True:
        return None
    return EVIDENCE_CLASSES.get(evidence.get("pr_state") or "")


def describe_evidence(evidence: dict[str, Any]) -> str | None:
    if not evidence:
        return None
    parts = []
    if evidence.get("pr_number"):
        parts.append(f"PR #{evidence['pr_number']} {evidence.get('pr_state')}")
        if evidence.get("pr_contains_head") is False:
            parts.append("local commits are not in the PR")
    else:
        parts.append("no PR found")
    dirty = evidence.get("dirty")
    if dirty is not None:
        parts.append("clean tree" if dirty == 0 else f"{dirty} uncommitted path(s)")
    if evidence.get("last_commit_days") is not None:
        parts.append(f"last commit {evidence['last_commit_days']}d ago")
    return "; ".join(parts)


def stack_health(pc_port: str) -> list[str]:
    """Crash loops and dead services, read from the stack's Process Compose manager."""
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(f"http://localhost:{pc_port}/processes", timeout=5) as response:
            services = json.load(response)["data"]
    except (OSError, ValueError, KeyError, TypeError):
        return ["manager API unreachable; service health unknown"]
    findings: list[str] = []
    for service in services if isinstance(services, list) else []:
        if not isinstance(service, dict):
            continue
        name, restarts, code = service.get("name"), service.get("restarts"), service.get("exit_code")
        if isinstance(restarts, int) and restarts >= RESTART_WARNING:
            findings.append(f"{name} restarted {restarts} times (current run: {service.get('system_time') or '-'})")
        if service.get("status") in ("Completed", "Error") and isinstance(code, int) and code != 0:
            findings.append(f"{name} exited with code {code} and is not running")
    return findings


def missing_store_paths(snapshot: dict[int, ProcessInfo], pids: set[int]) -> list[str]:
    """Store paths a running stack still references after garbage collection."""
    paths = {
        match
        for pid in pids
        if pid in snapshot
        for match in STORE_PATH_RE.findall(snapshot[pid].command)
    }
    return sorted(path for path in paths if not os.path.exists(path))


def descendants(snapshot: dict[int, ProcessInfo], roots: set[int]) -> set[int]:
    children: dict[int, list[int]] = {}
    for info in snapshot.values():
        children.setdefault(info.ppid, []).append(info.pid)
    found: set[int] = set()
    pending = list(roots)
    while pending:
        pid = pending.pop()
        if pid not in found:
            found.add(pid)
            pending.extend(children.get(pid, []))
    return found


def system_pressure() -> dict[str, Any]:
    pressure: dict[str, Any] = {"cpus": os.cpu_count()}
    try:
        pressure["load"] = [round(value, 2) for value in os.getloadavg()]
    except OSError:
        pass
    sysctl = shutil.which("sysctl") or "/usr/sbin/sysctl"
    try:
        result = run([sysctl, "-n", "vm.swapusage"], timeout=5)
        match = re.search(r"used = ([0-9.]+)M", result.stdout)
        if result.returncode == 0 and match:
            pressure["swap_used_mb"] = int(float(match.group(1)))
    except (OSError, subprocess.TimeoutExpired):
        pass
    return pressure


def discover_active_work(
    checkout_roots: tuple[Path, ...], associations: tuple[str, ...] = ()
) -> Discovery:
    """Local sessions only. Task associations are reviewed input, never old launch records.

    Recent terminal paths are suggestions, not deletion authority. An agent in
    the primary checkout may be working in any sibling, so require a mapping.
    """
    discovery = Discovery()
    try:
        herdr = require_tool("herdr")
        roots = tuple(canonical(path) for path in checkout_roots)
        mappings: dict[str, list[Path]] = {}
        for value in associations:
            key, separator, raw_path = value.partition("=")
            path = canonical(raw_path)
            if not separator or "/" not in key or not raw_path.startswith("/") or path not in roots:
                raise ReapError("--associate requires SESSION/PANE=/exact/registered/checkout")
            mappings.setdefault(key, []).append(path)

        def query(*args: str) -> Any:
            response = run([herdr, *args], timeout=10)
            if response.returncode:
                raise ReapError(f"local Herdr query failed: {' '.join(args)}")
            return json.loads(response.stdout)

        sessions = query("session", "list", "--json")["sessions"]
        if not isinstance(sessions, list):
            raise ReapError("invalid local Herdr session inventory")
        seen: set[str] = set()
        running = 0
        for session in sessions:
            if not isinstance(session, dict):
                raise ReapError("invalid local Herdr session")
            if session.get("running") is not True:
                continue
            name, endpoint = session.get("name"), session.get("socket_path")
            if not isinstance(name, str) or not isinstance(endpoint, str) or not endpoint.startswith("/"):
                raise ReapError("local session has no name/socket identity")
            running += 1
            # No --machine/--remote: named sessions address this node's server.
            snapshot = query("--session", name, "api", "snapshot")["result"]["snapshot"]
            agents, workspaces = snapshot["agents"], snapshot["workspaces"]
            if not isinstance(agents, list) or not isinstance(workspaces, list):
                raise ReapError("invalid local Herdr snapshot")
            labels = {item["workspace_id"]: item.get("label") for item in workspaces}
            for agent in agents:
                pane = agent["pane_id"]
                key = f"{name}/{pane}"
                terminal = agent.get("terminal_id")
                if not isinstance(terminal, str) or agent["workspace_id"] not in labels:
                    raise ReapError("agent has no terminal/workspace identity")
                seen.add(key)
                entry = {
                    "session": name, "socket": endpoint, "pane": pane,
                    "terminal_id": terminal, "agent_session": agent.get("agent_session"),
                    "workspace": labels[agent["workspace_id"]],
                    "workspace_id": agent["workspace_id"],
                }
                paths = mappings.get(key, [])
                source = "reviewed task association"
                if not paths:
                    source = "agent worktree directory"
                    for field_name in ("foreground_cwd", "cwd"):
                        cwd = agent.get(field_name)
                        if not isinstance(cwd, str) or not cwd.startswith("/"):
                            continue
                        # Primary cwd cannot identify a task's sibling checkout.
                        matches = [root for root in roots[1:] if path_is_within(root, cwd)]
                        if matches:
                            paths = [max(matches, key=lambda path: len(str(path)))]
                            break
                if paths:
                    discovery.paths.extend(paths)
                    discovery.evidence.append({**entry, "paths": [str(path) for path in paths], "source": source})
                    continue
                response = run([herdr, "--session", name, "agent", "read", pane,
                                "--source", "recent-unwrapped", "--lines", "160", "--format", "text"], timeout=10)
                if response.returncode:
                    raise ReapError(f"could not inspect unresolved task {key}")
                suggestions = []
                for root in roots[1:]:
                    spellings = (str(root), str(root).replace(str(Path.home()), "~", 1))
                    if any(re.search(re.escape(value) + r"(?=$|[/\s`'\"):,])", response.stdout) for value in spellings):
                        suggestions.append(str(root))
                discovery.unresolved.append({**entry, "suggested_paths": suggestions,
                                             "resolve_with": f"--associate {key}=/exact/checkout"})
        if not running:
            raise ReapError("no running local Herdr sessions; cannot establish current projects")
        if set(mappings) - seen:
            raise ReapError("association no longer matches a local agent: " + ", ".join(sorted(set(mappings) - seen)))
        if discovery.unresolved:
            discovery.error = UNRESOLVED_ERROR
        discovery.paths = list(dict.fromkeys(discovery.paths))
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired, ReapError) as error:
        discovery.error = f"local Herdr discovery failed: {error}"
    return discovery


def process_dict(process: ProcessRef) -> dict[str, Any]:
    return {
        "pid": process.pid,
        "ppid": process.ppid,
        "command": process.command,
        "cwd": process.cwd,
        "age": process.age,
        "ports": list(process.ports),
    }


def owning_target(targets: list[Target], cwd: str | None) -> Target | None:
    if cwd is None:
        return None
    candidates = [
        target for target in targets if path_is_within(target.path, Path(cwd))
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda target: len(str(target.path)))


def is_process_compose(process: ProcessRef) -> bool:
    command = process.command.lower()
    return command == "process-compose" or command.startswith("process-compose")


def process_descends_from(
    process: ProcessRef, ancestor_pids: set[int], parents: dict[int, int]
) -> bool:
    current = process.ppid
    seen: set[int] = set()
    while current and current > 1 and current not in seen:
        if current in ancestor_pids:
            return True
        seen.add(current)
        current = parents.get(current)
    return False


def build_audit(
    root: Path, protected_paths: tuple[Path, ...] = (), abandoned_paths: tuple[Path, ...] = (),
    outside_active: bool = False, associations: tuple[str, ...] = (),
) -> tuple[Audit, dict[str, Target]]:
    targets = discover_targets(root)
    abandoned_paths = tuple(canonical(path) for path in abandoned_paths)
    if any(path not in {target.path for target in targets if target.kind == "worktree"}
           for path in abandoned_paths):
        raise ReapError("--abandoned must name an exact registered linked checkout")
    protected_paths = tuple(
        dict.fromkeys(canonical(path) for path in protected_paths)
    )
    unmatched_protections = [
        path
        for path in protected_paths
        if not any(path_is_within(target.path, path) for target in targets)
    ]
    if unmatched_protections:
        raise ReapError(
            "protected path is not inside a discovered Portal checkout: "
            f"{unmatched_protections[0]}"
        )
    snapshot = process_snapshot()
    parents = {pid: info.ppid for pid, info in snapshot.items()}
    processes = listener_processes(snapshot)
    discovery = discover_active_work(tuple(target.path for target in targets if target.kind != "trash"), associations)
    active_paths, active_error = discovery.paths, discovery.error
    agent_paths = agent_checkouts(snapshot)
    # Unresolved panes are a per-checkout caveat; a failed inventory is not.
    only_unresolved = bool(discovery.unresolved) and active_error == UNRESOLVED_ERROR
    mentioned_paths = {
        str(canonical(path))
        for entry in discovery.unresolved
        for path in entry.get("suggested_paths", [])
    }
    target_by_path = {str(target.path): target for target in targets}
    owned: dict[str, list[ProcessRef]] = {str(target.path): [] for target in targets}
    extras: dict[str, list[ProcessRef]] = {str(target.path): [] for target in targets}

    unknown_process_compose: list[dict[str, Any]] = []
    for process in processes:
        owner = owning_target(targets, process.cwd)
        if owner is None:
            if is_process_compose(process):
                unknown_process_compose.append(process_dict(process))
            continue
        expected_ports = {int(value) for value in owner.ports.values()}
        if set(process.ports) & expected_ports:
            owned[str(owner.path)].append(process)
        if set(process.ports) - expected_ports:
            extras[str(owner.path)].append(process)

    reports: list[TargetReport] = []
    for target in targets:
        target_key = str(target.path)
        herdr_active = any(path_is_within(target.path, path) for path in active_paths)
        agent_live = any(path_is_within(target.path, path) for path in agent_paths)
        target_active = herdr_active or agent_live
        explicitly_protected = any(
            path_is_within(target.path, path) for path in protected_paths
        )
        owned_processes = owned[target_key]
        extra_processes = extras[target_key]
        has_runtime = bool(owned_processes or extra_processes)
        mentioned = target_key in mentioned_paths
        evidence: dict[str, Any] = {}
        if target.kind == "worktree" and has_runtime and not target_active:
            evidence = checkout_evidence(target.path)
        finished = None if mentioned or explicitly_protected else evidence_class(evidence)
        foreign: list[ProcessRef] = []
        target_ports = {int(value) for value in target.ports.values()}
        for process in processes:
            if not (set(process.ports) & target_ports):
                continue
            owner = owning_target(targets, process.cwd)
            if owner is None or owner.path != target.path:
                foreign.append(process)

        reasons = list(target.errors)
        explicitly_abandoned = target.path in abandoned_paths
        stale = explicitly_abandoned or (outside_active and not active_error and target.kind == "worktree")
        # A reviewed --abandoned selection survives unresolved panes, not a failed inventory.
        abandoned_ok = explicitly_abandoned and not mentioned and (not active_error or only_unresolved)
        herdr_independent = bool(finished) or (abandoned_ok and bool(active_error))
        if explicitly_protected:
            reasons.append("explicit --protect selection")
        if herdr_active:
            reasons.append("current local Herdr task association")
        elif agent_live:
            reasons.append("a live agent process is working in this checkout")
        elif mentioned:
            reasons.append("mentioned by an unresolved Herdr task; supply --associate or review it")
        elif finished:
            reasons.append("pull request finished, tree clean with every commit in the PR, and no live agent")
        elif explicitly_abandoned:
            reasons.append("explicit --abandoned selection; rechecked before shutdown")
        elif stale:
            reasons.append("outside current projects under explicit --outside-active policy")
        else:
            reasons.append("no session ownership proof; absence of cwd does not prove abandonment")
        if active_error and not herdr_independent:
            reasons.append(f"active workspace source unavailable: {active_error}")
        checkout_processes = {
            process.pid: process for process in (*owned_processes, *extra_processes)
        }.values()
        pc_processes = [
            process for process in checkout_processes if is_process_compose(process)
        ]
        manager_pids = {
            process.pid
            for process in pc_processes
            if target.pc_port and int(target.pc_port) in process.ports
        }
        manager_controlled = [
            process
            for process in foreign
            if process_descends_from(process, manager_pids, parents)
        ]
        uncontrolled_foreign = [
            process for process in foreign if process not in manager_controlled
        ]
        if uncontrolled_foreign:
            reasons.append("allocated port has a foreign or unproven listener")
        if manager_controlled:
            reasons.append(
                "allocated listener is controlled by the checkout's process-compose manager"
            )
        pc_mismatch = bool(
            pc_processes
            and target.pc_port
            and any(
                int(target.pc_port) not in process.ports for process in pc_processes
            )
        )
        if pc_mismatch:
            reasons.append("process-compose listener does not match PC_PORT_NUM")
        if extra_processes:
            reasons.append("checkout owns listeners outside its allocated port set")

        all_owned = {
            process.pid: process
            for process in (*owned_processes, *extra_processes, *manager_controlled)
        }
        incomplete_identity = any(
            process.identity is None or process.cwd is None
            for process in all_owned.values()
        )
        if incomplete_identity:
            reasons.append("owned listener identity inventory is incomplete")

        protected = target.kind == "primary" or explicitly_protected
        risky = bool(
            target.errors
            or (active_error and not herdr_independent)
            or uncontrolled_foreign
            or pc_mismatch
            or incomplete_identity
        )
        if target_active:
            classification = "active"
        elif protected:
            classification = "protected"
        elif finished:
            classification = finished
        elif abandoned_ok:
            classification = "stale"
        elif active_error or mentioned:
            classification = "unknown"
        elif stale:
            classification = "stale"
        elif risky and has_runtime:
            classification = "unknown"
        elif has_runtime and not explicitly_abandoned:
            classification = "unknown"
        elif target.kind == "trash" and has_runtime:
            classification = "deleted-checkout-orphan"
        elif target.kind == "trash":
            classification = "deleted-checkout"
        else:
            classification = "unowned"
        runtime = "running" if has_runtime else "stopped"
        actionable = (
            has_runtime
            and not protected
            and not risky
            and target.env_values is not None
            and classification in STOPPABLE_CLASSES
            and bool(manager_pids)
        )
        fingerprint = [
            [process.pid, process.identity, process.cwd]
            for process in sorted(all_owned.values(), key=lambda item: item.pid)
        ]
        stack_pids = descendants(snapshot, manager_pids) | set(all_owned)
        health: list[str] = []
        if manager_pids and target.pc_port:
            health = stack_health(target.pc_port)
            missing = missing_store_paths(snapshot, stack_pids)
            if missing:
                health.append(
                    f"{len(missing)} Nix store path(s) used by running services were "
                    "garbage-collected; restart the stack"
                )
        reports.append(
            TargetReport(
                kind=target.kind,
                path=target_key,
                name=target.name,
                pc_port=target.pc_port,
                classification=classification,
                runtime=runtime,
                actionable=actionable,
                protected=protected,
                reasons=reasons,
                listeners=[process_dict(process) for process in owned_processes],
                foreign_listeners=[
                    process_dict(process) for process in uncontrolled_foreign
                ],
                manager_controlled_listeners=[
                    process_dict(process) for process in manager_controlled
                ],
                extra_owned_listeners=[
                    process_dict(process) for process in extra_processes
                ],
                fingerprint=fingerprint,
                herdr_independent=herdr_independent and actionable,
                age=next(
                    (process.age for process in pc_processes if process.pid in manager_pids),
                    None,
                ),
                process_count=len(stack_pids),
                rss_mb=sum(snapshot[pid].rss_kb for pid in stack_pids if pid in snapshot) // 1024,
                evidence=evidence,
                health=health,
            )
        )

    audit = Audit(
        schema_version=3,
        repository=str(root),
        active_source="herdr-local-machine-all-running-sessions",
        active_error=active_error,
        active_paths=[str(path) for path in active_paths],
        protected_paths=[str(path) for path in protected_paths],
        targets=reports,
        unknown_process_compose=unknown_process_compose,
        abandoned_paths=[str(path) for path in abandoned_paths],
        outside_active=outside_active, associations=list(associations), discovery=discovery,
        system=system_pressure(),
    )
    return audit, target_by_path


def format_age(value: str | None) -> str:
    return value or "-"


def print_audit(audit: Audit, *, show_apply_hint: bool = True) -> None:
    print(f"Portal repository: {audit.repository}")
    if audit.active_error:
        print(f"Herdr inventory: unavailable ({audit.active_error})")
    else:
        print(
            f"Herdr checkout paths: {len(audit.active_paths)} "
            "(this machine, all running local sessions)"
        )
    print(f"Local node: {audit.discovery.node}")
    for entry in audit.discovery.evidence:
        print(f"Keep: {entry['workspace']} ({entry['session']}/{entry['pane']}): {', '.join(entry['paths'])}; {entry['source']}")
    for entry in audit.discovery.unresolved:
        print(f"Unresolved: {entry['workspace']}: {entry['resolve_with']}; suggestions: {entry['suggested_paths']}")
    print(f"Explicitly protected paths: {len(audit.protected_paths)}")
    if audit.system.get("load"):
        swap = audit.system.get("swap_used_mb")
        print(
            f"System: load {audit.system['load'][0]} on {audit.system.get('cpus')} CPUs"
            + (f"; swap used {swap} MB" if swap is not None else "")
        )
    print()
    print(f"{'CLASS':<25} {'RUNTIME':<8} {'PC':<7} {'AGE':<12} {'PROCS':>5} {'RSS MB':>7}  CHECKOUT")
    print(f"{'-----':<25} {'-------':<8} {'--':<7} {'---':<12} {'-----':>5} {'------':>7}  --------")
    for target in audit.targets:
        ages = [
            item.get("age")
            for item in (*target.listeners, *target.extra_owned_listeners)
            if item.get("age")
        ]
        # The manager's age is the stack's age; services restart underneath it.
        age = target.age or (ages[0] if ages else None)
        running = target.runtime == "running"
        print(
            f"{target.classification:<25} {target.runtime:<8} "
            f"{(':' + target.pc_port) if target.pc_port else '-':<7} "
            f"{format_age(age):<12} {target.process_count if running else '-':>5} "
            f"{target.rss_mb if running else '-':>7}  {target.path}"
        )
        for reason in target.reasons:
            print(f"  ! {reason}")
        described = describe_evidence(target.evidence)
        if described:
            print(f"  · {described}")
        for finding in target.health:
            print(f"  ✗ {finding}")
    if audit.unknown_process_compose:
        print()
        print("Unknown Process Compose listeners (never reaped):")
        for process in audit.unknown_process_compose:
            print(
                f"- pid={process['pid']} ports={','.join(map(str, process['ports'])) or '-'} "
                f"cwd={process['cwd'] or '-'}"
            )
    actionable = sum(1 for target in audit.targets if target.actionable)
    protected = sum(1 for target in audit.targets if target.protected)
    unknown = sum(
        1 for target in audit.targets if target.classification == "unknown"
    )
    running = sum(1 for target in audit.targets if target.runtime == "running")
    listener_pids = {
        item["pid"]
        for target in audit.targets
        for item in (
            *target.listeners,
            *target.foreign_listeners,
            *target.manager_controlled_listeners,
            *target.extra_owned_listeners,
        )
    }
    unhealthy = [target for target in audit.targets if target.health]
    print()
    print(f"Actionable stale runtimes: {actionable}")
    print(
        f"Running targets: {running}; protected: {protected}; unknown: {unknown}; "
        f"reported listener processes: {len(listener_pids)}"
    )
    if unhealthy:
        print(f"Unhealthy stacks: {len(unhealthy)} (see ✗ lines)")
        for target in unhealthy:
            if not target.actionable:
                print(f"- not stopped automatically: {target.path} (`just dev down` there, then `just dev` to restart)")
    print(
        "Coverage is limited to TCP-listening Portal stacks; "
        "standalone builds are not inventoried."
    )
    if show_apply_hint:
        print("Report only; pass --apply to run Portal's ownership-checked cleanup.")


def cleanup_command(target: Target) -> list[str]:
    if target.pc_port is None:
        raise ReapError(f"missing manager port for {target.path}")
    # Use the installed maintained lifecycle, never evaluate a historical flake.
    # Explicit live-manager compatibility does not rewrite old identities.
    return [require_tool("portal-worktree-lifecycle"), "stop-runtime",
            "--worktree-path", str(target.path), "--legacy-pc-port", target.pc_port]


def report_by_path(audit: Audit, path: str) -> TargetReport | None:
    return next((target for target in audit.targets if target.path == path), None)


def fingerprint_is_current(report: TargetReport) -> bool:
    """Recheck stable process ownership fields without comparing listener ports."""
    if any(len(item) != 3 or not isinstance(item[0], int) for item in report.fingerprint):
        return False
    snapshot = process_snapshot()
    cwds = process_cwds(require_tool("lsof"), {item[0] for item in report.fingerprint})
    return all(
        identity_of(snapshot.get(pid)) == expected_identity and cwds.get(pid) == expected_cwd
        for pid, expected_identity, expected_cwd in report.fingerprint
    )


def apply_cleanup(root: Path, initial: Audit, only: tuple[Path, ...] = ()) -> int:
    # An incomplete Herdr inventory still permits stops that do not rest on it.
    if initial.active_error and not any(
        target.actionable and target.herdr_independent for target in initial.targets
    ):
        raise ReapError(initial.active_error)
    selected = {str(canonical(path)) for path in only}
    candidates = [target for target in initial.targets if target.actionable and (not selected or target.path in selected)]
    strict = any(not candidate.herdr_independent for candidate in candidates)
    if selected - {target.path for target in candidates}:
        raise ReapError("selected runtime is not safely stoppable; refresh discovery")
    if not candidates:
        print("No confirmed inactive or orphaned runtimes to stop.")
        return 0

    failures = 0
    results: list[tuple[str, str]] = []
    protected_paths = tuple(Path(path) for path in initial.protected_paths)
    print("\nRevalidating candidate inventory")
    for candidate in candidates:
        fresh, fresh_targets = build_audit(
            root, protected_paths, tuple(Path(p) for p in initial.abandoned_paths),
            initial.outside_active, tuple(initial.associations),
        )
        print(f"\nChecking {candidate.path}")
        current = report_by_path(fresh, candidate.path)
        target = fresh_targets.get(candidate.path)
        if current is None or target is None:
            print("  skipped: checkout inventory changed")
            results.append((candidate.path, "skipped: checkout inventory changed"))
            failures += 1
            continue
        if current.fingerprint != candidate.fingerprint:
            print("  skipped: process ownership identity changed; rerun the audit")
            results.append((candidate.path, "skipped: process ownership changed"))
            failures += 1
            continue
        if not current.actionable:
            print(f"  skipped: now classified as {current.classification}")
            results.append(
                (candidate.path, f"skipped: now {current.classification}")
            )
            failures += 1
            continue

        discovery = discover_active_work(tuple(item.path for item in fresh_targets.values() if item.kind != "trash"),
                                         tuple(initial.associations))
        active_paths, active_error = discovery.paths, discovery.error
        if current.herdr_independent:
            # The fresh audit above already re-proved the non-Herdr evidence.
            active_error = None
        elif (initial.discovery.evidence != discovery.evidence or initial.discovery.node != discovery.node):
            active_error = "task identities/associations changed; review a fresh inventory"
        if active_error:
            print(f"  skipped: active workspace source unavailable: {active_error}")
            results.append((candidate.path, "skipped: Herdr unavailable"))
            failures += 1
            continue
        if any(path_is_within(target.path, path) for path in active_paths):
            print("  skipped: checkout became active in Herdr")
            results.append((candidate.path, "skipped: became active"))
            failures += 1
            continue
        if not fingerprint_is_current(current):
            print("  skipped: process ownership identity changed before cleanup")
            results.append(
                (candidate.path, "skipped: process ownership changed before cleanup")
            )
            failures += 1
            continue

        try:
            command = cleanup_command(target)
            print(f"  running: {shlex.join(command)}")
            result = run(command, cwd=target.path, timeout=180, capture=False)
        except subprocess.TimeoutExpired:
            print(
                "  cleanup timed out; not retrying because descendant processes "
                "may still be exiting",
                file=sys.stderr,
            )
            results.append((candidate.path, "failed: cleanup timed out"))
            failures += 1
            continue
        except (OSError, ReapError) as error:
            print(f"  cleanup could not run: {error}", file=sys.stderr)
            results.append((candidate.path, f"failed: {error}"))
            failures += 1
            continue
        if result.returncode != 0:
            print(
                f"  cleanup failed with exit code {result.returncode}", file=sys.stderr
            )
            results.append(
                (candidate.path, f"failed: exit code {result.returncode}")
            )
            failures += 1
        else:
            after, _ = build_audit(
                root, protected_paths, tuple(Path(p) for p in initial.abandoned_paths),
                initial.outside_active, tuple(initial.associations),
            )
            stopped = report_by_path(after, candidate.path)
            if after.active_error and not current.herdr_independent:
                failures += 1
                results.append((candidate.path, "failed: final project discovery unavailable"))
            elif stopped is None or stopped.runtime != "stopped":
                failures += 1
                results.append((candidate.path, "failed: runtime remains after shutdown"))
            else:
                results.append((candidate.path, "runtime stopped; checkout and data preserved"))

    print("\nApply results")
    for path, status in results:
        print(f"- {path}: {status}")
    print("\nFinal audit")
    final, _targets = build_audit(
        root, protected_paths, tuple(Path(p) for p in initial.abandoned_paths),
        initial.outside_active, tuple(initial.associations),
    )
    print_audit(final, show_apply_hint=False)
    if final.active_error and strict:
        return 1
    remaining = sum(1 for target in final.targets if target.actionable and (not selected or target.path in selected))
    if remaining:
        print(f"{remaining} actionable runtime(s) remain.", file=sys.stderr)
        return 1
    return 1 if failures else 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="portal-dev-reap",
        description="Audit Portal dev runtimes against Herdr, pull requests, and service health, "
                    "and safely stop confirmed stale stacks.",
    )
    parser.add_argument(
        "--repo",
        type=Path,
        default=Path(
            os.environ.get(
                "PORTAL_CMS_ROOT", Path.home() / "Workspace" / "portal" / "cms"
            )
        ),
        help="primary Portal CMS checkout (default: %(default)s)",
    )
    parser.add_argument("--outside-active", action="store_true",
                        help="explicitly classify linked checkouts outside discovered current projects as stale")
    parser.add_argument("--associate", action="append", default=[], metavar="SESSION/PANE=PATH",
                        help="reviewed current task-to-checkout association (repeatable, including multiple paths per task)")
    parser.add_argument("--only", action="append", default=[], type=Path,
                        help="stop only this exact actionable checkout with --apply (repeatable)")
    parser.add_argument("--abandoned", action="append", default=[], type=Path,
                        help="exact checkout reviewed as abandoned (repeatable); works despite unresolved "
                             "Herdr tasks unless one mentions it")
    parser.add_argument("--json", action="store_true", help="print the audit as JSON")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="run the repository's ownership-checked cleanup for confirmed stale runtimes",
    )
    parser.add_argument(
        "--protect",
        action="append",
        default=[],
        metavar="PATH",
        type=Path,
        help="protect a checkout path not represented in Herdr (repeatable)",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        root = validate_repository(args.repo)
        audit, _targets = build_audit(root, tuple(args.protect), tuple(args.abandoned), args.outside_active, tuple(args.associate))
        if args.json:
            print(json.dumps(asdict(audit), indent=2, sort_keys=True, default=str))
        else:
            print_audit(audit)
        if args.apply:
            if args.json:
                print("--apply cannot be combined with --json", file=sys.stderr)
                return 2
            return apply_cleanup(root, audit, tuple(args.only))
        return 2 if audit.active_error else 0
    except (OSError, subprocess.TimeoutExpired, ReapError) as error:
        print(f"portal-dev-reap: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
