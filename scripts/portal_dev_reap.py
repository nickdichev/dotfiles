"""Audit and safely stop unprotected Portal dev stacks inactive in local Herdr."""

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


class ReapError(RuntimeError):
    """An expected audit error that should be shown without a traceback."""


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


def listener_cwd(lsof: str, pid: int) -> str | None:
    result = run([lsof, "-nP", "-a", "-p", str(pid), "-d", "cwd", "-Fn"], timeout=5)
    if result.returncode != 0:
        return None
    for line in result.stdout.splitlines():
        if line.startswith("n") and len(line) > 1:
            return str(canonical(line[1:]))
    return None


def process_field(pid: int, field_name: str) -> str | None:
    for ps in (shutil.which("ps"), "/bin/ps", "/usr/bin/ps"):
        if not ps:
            continue
        try:
            result = run([ps, "-p", str(pid), "-o", f"{field_name}="], timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            continue
        value = " ".join(result.stdout.split())
        if result.returncode == 0 and value:
            return value
    return None


def listener_processes() -> list[ProcessRef]:
    lsof = require_tool("lsof")
    username = pwd.getpwuid(os.getuid()).pw_name
    result = run(
        [lsof, "-nP", "-a", "-u", username, "-iTCP", "-sTCP:LISTEN", "-Fpcn"],
        timeout=30,
    )
    if result.returncode not in (0, 1):
        raise ReapError(f"listener inventory failed: {result.stderr.strip()}")
    parsed = parse_lsof_listeners(result.stdout)
    processes: list[ProcessRef] = []
    for pid, entry in sorted(parsed.items()):
        started = process_field(pid, "lstart")
        command_line = process_field(pid, "command")
        identity = f"{started} {command_line}" if started and command_line else None
        raw_ppid = process_field(pid, "ppid")
        processes.append(
            ProcessRef(
                pid=pid,
                ppid=int(raw_ppid) if raw_ppid and raw_ppid.isdigit() else None,
                command=entry["command"],
                cwd=listener_cwd(lsof, pid),
                identity=identity,
                age=process_field(pid, "etime"),
                ports=tuple(sorted(entry["ports"])),
            )
        )
    return processes


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
            discovery.error = "unresolved local tasks; review suggested paths and supply --associate"
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


def process_descends_from(process: ProcessRef, ancestor_pids: set[int]) -> bool:
    current = process.ppid
    seen: set[int] = set()
    while current and current > 1 and current not in seen:
        if current in ancestor_pids:
            return True
        seen.add(current)
        raw_parent = process_field(current, "ppid")
        current = int(raw_parent) if raw_parent and raw_parent.isdigit() else None
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
    processes = listener_processes()
    discovery = discover_active_work(tuple(target.path for target in targets if target.kind != "trash"), associations)
    active_paths, active_error = discovery.paths, discovery.error
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
        target_active = any(path_is_within(target.path, path) for path in active_paths)
        explicitly_protected = any(
            path_is_within(target.path, path) for path in protected_paths
        )
        owned_processes = owned[target_key]
        extra_processes = extras[target_key]
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
        if explicitly_protected:
            reasons.append("explicit --protect selection")
        if target_active:
            reasons.append("current local Herdr task association")
        elif explicitly_abandoned:
            reasons.append("explicit --abandoned selection; rechecked before shutdown")
        elif stale:
            reasons.append("outside current projects under explicit --outside-active policy")
        else:
            reasons.append("no session ownership proof; absence of cwd does not prove abandonment")
        if active_error:
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
            if process_descends_from(process, manager_pids)
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

        has_runtime = bool(owned_processes or extra_processes)
        protected = target.kind == "primary" or explicitly_protected
        risky = bool(
            target.errors
            or active_error
            or uncontrolled_foreign
            or pc_mismatch
            or incomplete_identity
        )
        if target_active:
            classification = "active"
        elif protected:
            classification = "protected"
        elif active_error:
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
            and classification == "stale"
            and bool(manager_pids)
        )
        fingerprint = [
            [process.pid, process.identity, process.cwd]
            for process in sorted(all_owned.values(), key=lambda item: item.pid)
        ]
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
    print()
    print(f"{'CLASS':<25} {'RUNTIME':<8} {'PC':<7} {'AGE':<12} CHECKOUT")
    print(f"{'-----':<25} {'-------':<8} {'--':<7} {'---':<12} --------")
    for target in audit.targets:
        ages = [
            item.get("age")
            for item in (*target.listeners, *target.extra_owned_listeners)
            if item.get("age")
        ]
        age = ages[0] if ages else None
        print(
            f"{target.classification:<25} {target.runtime:<8} "
            f"{(':' + target.pc_port) if target.pc_port else '-':<7} "
            f"{format_age(age):<12} {target.path}"
        )
        for reason in target.reasons:
            print(f"  ! {reason}")
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
    print()
    print(f"Actionable stale runtimes: {actionable}")
    print(
        f"Running targets: {running}; protected: {protected}; unknown: {unknown}; "
        f"reported listener processes: {len(listener_pids)}"
    )
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
    lsof = require_tool("lsof")
    for fingerprint in report.fingerprint:
        if len(fingerprint) != 3:
            return False
        pid, expected_identity, expected_cwd = fingerprint
        if not isinstance(pid, int):
            return False
        started = process_field(pid, "lstart")
        command_line = process_field(pid, "command")
        identity = f"{started} {command_line}" if started and command_line else None
        if identity != expected_identity or listener_cwd(lsof, pid) != expected_cwd:
            return False
    return True


def apply_cleanup(root: Path, initial: Audit, only: tuple[Path, ...] = ()) -> int:
    if initial.active_error:
        raise ReapError(initial.active_error)
    selected = {str(canonical(path)) for path in only}
    candidates = [target for target in initial.targets if target.actionable and (not selected or target.path in selected)]
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
        if (initial.discovery.evidence != discovery.evidence or initial.discovery.node != discovery.node):
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
            if after.active_error:
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
    if final.active_error:
        return 1
    remaining = sum(1 for target in final.targets if target.actionable and (not selected or target.path in selected))
    if remaining:
        print(f"{remaining} actionable runtime(s) remain.", file=sys.stderr)
        return 1
    return 1 if failures else 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="portal-dev-reap",
        description="Audit Portal dev runtimes against Herdr and safely stop confirmed stale stacks.",
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
                        help="exact checkout reviewed as abandoned (repeatable); absence from Herdr is insufficient")
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
