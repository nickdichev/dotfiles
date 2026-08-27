"""Audit and safely stop Portal dev stacks that are not open in Herdr."""

from __future__ import annotations

import argparse
import json
import os
import pwd
import re
import shlex
import shutil
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
class Audit:
    schema_version: int
    repository: str
    active_source: str
    active_error: str | None
    active_paths: list[str]
    targets: list[TargetReport]
    unknown_process_compose: list[dict[str, Any]]


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


def herdr_active_paths() -> tuple[list[Path], str | None]:
    herdr = shutil.which("herdr")
    if herdr is None:
        return [], "herdr is not available"
    try:
        result = run([herdr, "pane", "list"], timeout=10)
    except subprocess.TimeoutExpired:
        return [], "herdr pane inventory timed out"
    if result.returncode != 0:
        return [], (
            result.stderr or result.stdout
        ).strip() or "herdr pane inventory failed"
    try:
        payload = json.loads(result.stdout)
        panes = payload["result"]["panes"]
    except (json.JSONDecodeError, KeyError, TypeError):
        return [], "herdr returned an unexpected pane inventory"

    paths: list[Path] = []
    for pane in panes:
        if not isinstance(pane, dict):
            continue
        for key in ("cwd", "foreground_cwd"):
            value = pane.get(key)
            if isinstance(value, str) and value.startswith("/"):
                paths.append(canonical(value))
    return list(dict.fromkeys(paths)), None


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


def build_audit(root: Path) -> tuple[Audit, dict[str, Target]]:
    targets = discover_targets(root)
    processes = listener_processes()
    active_paths, active_error = herdr_active_paths()
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

        has_runtime = bool(owned_processes or extra_processes)
        protected = target.kind == "primary"
        risky = bool(
            target.errors or active_error or uncontrolled_foreign or pc_mismatch
        )
        if target_active:
            classification = "active"
        elif risky and has_runtime:
            classification = "unknown"
        elif target.kind == "trash" and has_runtime:
            classification = "deleted-checkout-orphan"
        elif target.kind == "trash":
            classification = "deleted-checkout"
        else:
            classification = "inactive"
        runtime = "running" if has_runtime else "stopped"
        actionable = (
            has_runtime
            and not protected
            and not risky
            and target.env_values is not None
            and classification in ("inactive", "deleted-checkout-orphan")
        )
        all_owned = {
            process.pid: process
            for process in (*owned_processes, *extra_processes, *manager_controlled)
        }
        fingerprint = [
            [process.pid, process.identity, process.cwd, *process.ports]
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
        schema_version=1,
        repository=str(root),
        active_source="herdr",
        active_error=active_error,
        active_paths=[str(path) for path in active_paths],
        targets=reports,
        unknown_process_compose=unknown_process_compose,
    )
    return audit, target_by_path


def format_age(value: str | None) -> str:
    return value or "-"


def print_audit(audit: Audit) -> None:
    print(f"Portal repository: {audit.repository}")
    if audit.active_error:
        print(f"Herdr inventory: unavailable ({audit.active_error})")
    else:
        print(f"Herdr checkout paths: {len(audit.active_paths)}")
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
    print()
    print(f"Actionable stale runtimes: {actionable}")
    print("Report only; pass --apply to run Portal's ownership-checked cleanup.")


def cleanup_command(target: Target) -> list[str]:
    if target.env_values is None:
        raise ReapError(f"missing validated identity for {target.path}")
    values = target.env_values
    command = [
        require_tool("nix"),
        "run",
        f"{target.path}#portal-worktree-lifecycle",
        "--",
        "cleanup",
        "--worktree-path",
        str(target.path),
        "--worktree-name",
        values["WORKTREE_NAME"],
    ]
    for key, flag_name in PORT_FLAGS.items():
        command.extend([flag_name, values[key]])
    return command


def report_by_path(audit: Audit, path: str) -> TargetReport | None:
    return next((target for target in audit.targets if target.path == path), None)


def apply_cleanup(root: Path, initial: Audit) -> int:
    candidates = [target for target in initial.targets if target.actionable]
    if not candidates:
        print("No confirmed inactive or orphaned runtimes to stop.")
        return 0

    failures = 0
    for candidate in candidates:
        print(f"\nRevalidating {candidate.path}")
        fresh, fresh_targets = build_audit(root)
        current = report_by_path(fresh, candidate.path)
        target = fresh_targets.get(candidate.path)
        if current is None or target is None:
            print("  skipped: checkout inventory changed")
            failures += 1
            continue
        if current.fingerprint != candidate.fingerprint:
            print("  skipped: process identity changed; rerun the audit")
            failures += 1
            continue
        if not current.actionable:
            print(f"  skipped: now classified as {current.classification}")
            failures += 1
            continue

        command = cleanup_command(target)
        print(f"  running: {shlex.join(command)}")
        result = run(command, cwd=target.path, timeout=180, capture=False)
        if result.returncode != 0:
            print(
                f"  cleanup failed with exit code {result.returncode}", file=sys.stderr
            )
            failures += 1

    print("\nFinal audit")
    final, _targets = build_audit(root)
    print_audit(final)
    remaining = sum(1 for target in final.targets if target.actionable)
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
    parser.add_argument("--json", action="store_true", help="print the audit as JSON")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="run the repository's ownership-checked cleanup for confirmed stale runtimes",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        root = validate_repository(args.repo)
        audit, _targets = build_audit(root)
        if args.json:
            print(json.dumps(asdict(audit), indent=2, sort_keys=True))
        else:
            print_audit(audit)
        if args.apply:
            if args.json:
                print("--apply cannot be combined with --json", file=sys.stderr)
                return 2
            return apply_cleanup(root, audit)
        return 0
    except (OSError, subprocess.TimeoutExpired, ReapError) as error:
        print(f"portal-dev-reap: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
