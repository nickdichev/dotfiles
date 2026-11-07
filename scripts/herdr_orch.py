"""Watcher, classifier, token report and benchmark for herdr-orchestrator.

The orchestrator skill starts `herdr-orch watch` in its own Herdr pane. The
watcher polls Herdr, the worker report files and GitHub without any model
calls, and prompts the orchestrator with one line per real transition. An
optional cheap classifier (Haiku through `claude -p`, or TypeSafe's Jev
decision model through OpenRouter) settles fuzzy cases it is confident about.

All tunables come from ~/.config/herdr-orchestrator/config.toml, which Home
Manager renders from `profiles.ai.orchestrator`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import tomllib
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

HOME = Path.home()
CONFIG_PATH = Path(
    os.environ.get(
        "HERDR_ORCH_CONFIG",
        Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
        / "herdr-orchestrator"
        / "config.toml",
    )
)
CLAUDE_PROJECTS = HOME / ".claude" / "projects"

AGENT_STATUSES = ("idle", "working", "blocked", "done", "unknown")
REPORT_STATUSES = ("DONE", "BLOCKED", "QUESTION")
BACKENDS = ("off", "haiku", "jev")
EFFORTS = ("low", "medium", "high", "xhigh", "max")
MODEL_ALIASES = ("opus", "sonnet", "haiku", "fable")
MODEL_ID = re.compile(r"^claude-[a-z0-9.-]+(\[1m\])?$")

# Labels the tier-2 classifier chooses between. The descriptions are the
# whole definition: both backends and the benchmark use them verbatim.
LABELS = {
    "working": "The agent is actively making progress: running commands, editing files, or waiting on a build or test it started. Nothing is needed.",
    "finished": "The agent has completed its task and is idle at the prompt; its last message reports the work as done.",
    "stuck": "The agent cannot proceed: a failure it cannot fix, missing access or tooling, a crash, or it says it is blocked and waits for help.",
    "looping": "The agent repeats the same action, error or retry cycle without making progress.",
    "routine_question": "The agent asks something that the task brief or ordinary engineering judgement settles, such as whether to proceed, run tests or pick an obvious option. Telling it to use its judgement and continue is safe.",
    "real_question": "The agent needs a decision only the orchestrator or a human can make: scope, architecture, risk, a destructive or outward-facing action, or conflicting requirements.",
}

CLASSIFIER_SYSTEM = (
    "You classify the state of a coding agent from the last lines of its "
    "terminal. Choose exactly one label:\n"
    + "\n".join(f"- {name}: {desc}" for name, desc in LABELS.items())
    + "\nReport your confidence as the probability, from 0 to 1, that the "
    "label is correct. Answer with JSON only."
)

CLASSIFIER_SCHEMA = {
    "type": "object",
    "properties": {
        "label": {"type": "string", "enum": list(LABELS)},
        "confidence": {"type": "number"},
    },
    "required": ["label", "confidence"],
    "additionalProperties": False,
}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def parse_time(value: str | None) -> float:
    if not value:
        return 0.0
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0.0


def read_json(path: Path, default: Any = None) -> Any:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)


def log(message: str) -> None:
    print(f"{datetime.now().strftime('%H:%M:%S')} {message}", flush=True)


# --- Config ----------------------------------------------------------------


class ConfigError(ValueError):
    pass


def validate_config(cfg: dict[str, Any]) -> dict[str, Any]:
    """Check the rendered config. Nix checks the same rules at build time."""
    tiers = cfg.get("tiers") or {}
    if not tiers:
        raise ConfigError("no tiers declared")
    for name, tier in tiers.items():
        model = tier.get("model", "")
        if model not in MODEL_ALIASES and not MODEL_ID.match(model):
            raise ConfigError(f"tier {name}: unknown model {model!r}")
        if tier.get("effort") not in EFFORTS:
            raise ConfigError(f"tier {name}: unknown effort {tier.get('effort')!r}")
    workers = cfg["workers"]
    for key in ("implementer_tier", "reviewer_tier", "escalate_to_tier"):
        if workers[key] not in tiers:
            raise ConfigError(f"workers.{key}: no tier named {workers[key]!r}")
    classifier = cfg["classifier"]
    if classifier["backend"] not in BACKENDS:
        raise ConfigError(f"classifier.backend: {classifier['backend']!r}")
    if not 0 <= classifier["band_low"] < classifier["band_high"] <= 1:
        raise ConfigError("classifier band needs 0 <= band_low < band_high <= 1")
    watcher = cfg["watcher"]
    for key in ("poll_seconds", "idle_minutes", "stall_minutes", "pr_poll_seconds"):
        if watcher[key] <= 0:
            raise ConfigError(f"watcher.{key} must be positive")
    if watcher["fallback_check_minutes"] < 60:
        raise ConfigError("watcher.fallback_check_minutes must be at least 60")
    if not 0 < cfg["orchestrator"]["rotate_at_percent"] < 100:
        raise ConfigError("orchestrator.rotate_at_percent must be between 0 and 100")
    return cfg


def load_config(path: Path = CONFIG_PATH) -> dict[str, Any]:
    try:
        with path.open("rb") as handle:
            cfg = tomllib.load(handle)
    except FileNotFoundError:
        raise SystemExit(
            f"{path} not found; enable profiles.ai.orchestrator and switch"
        )
    return validate_config(cfg)


def state_root(cfg: dict[str, Any]) -> Path:
    return Path(os.path.expanduser(cfg["paths"]["state_dir"]))


def run_dir_for(ledger_path: Path) -> Path:
    """Reports and watcher state live next to the ledger: <ws>/<slug>/."""
    return ledger_path.with_suffix("")


# --- External commands -----------------------------------------------------


def run(cmd: list[str], *, input_text: str | None = None, timeout: float = 30) -> str:
    result = subprocess.run(
        cmd,
        input=input_text,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=True,
    )
    return result.stdout


def herdr_agents() -> dict[str, dict[str, Any]]:
    """Live agents keyed by pane ID."""
    data = json.loads(run(["herdr", "agent", "list"]))
    return {a["pane_id"]: a for a in data["result"]["agents"]}


def herdr_read(target: str, lines: int) -> str:
    return run(
        ["herdr", "agent", "read", target, "--source", "recent-unwrapped", "--lines", str(lines)]
    )


def herdr_prompt(target: str, text: str) -> None:
    run(["herdr", "agent", "prompt", target, text])


@dataclass
class PrInfo:
    state: str  # OPEN | MERGED | CLOSED
    checks: str  # pending | pass | fail | none
    merge: str  # MERGEABLE | CONFLICTING | UNKNOWN

    def key(self) -> str:
        return f"{self.state}/{self.checks}/{self.merge}"

    def notable(self) -> bool:
        return (
            self.state != "OPEN"
            or self.checks in ("pass", "fail")
            or self.merge == "CONFLICTING"
        )


def rollup_checks(rollup: list[dict[str, Any]]) -> str:
    """Collapse `statusCheckRollup` into pending, pass, fail or none."""
    if not rollup:
        return "none"
    failed = {"FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE"}
    pending = False
    for check in rollup:
        # CheckRun has status/conclusion; StatusContext has state.
        outcome = (check.get("conclusion") or check.get("state") or "").upper()
        if outcome in failed:
            return "fail"
        if check.get("__typename") == "CheckRun" and check.get("status") != "COMPLETED":
            pending = True
        elif outcome in ("PENDING", "EXPECTED", "QUEUED", "IN_PROGRESS", ""):
            pending = True
    return "pending" if pending else "pass"


def gh_pr_info(url: str) -> PrInfo:
    data = json.loads(
        run(["gh", "pr", "view", url, "--json", "state,mergeable,statusCheckRollup"], timeout=60)
    )
    return PrInfo(
        state=data.get("state", "OPEN"),
        checks=rollup_checks(data.get("statusCheckRollup") or []),
        merge=data.get("mergeable") or "UNKNOWN",
    )


# --- Report files ----------------------------------------------------------


@dataclass
class ReportInfo:
    sig: str
    mtime: float
    status: str
    prs: list[str]


PR_URL = re.compile(r"https://github\.com/[\w.-]+/[\w.-]+/pull/\d+")


def read_report(path: Path) -> ReportInfo | None:
    try:
        stat = path.stat()
        text = path.read_text(errors="replace")
    except OSError:
        return None
    status = "UNKNOWN"
    for line in text.splitlines():
        match = re.match(r"\s*status:\s*([A-Za-z]+)", line)
        if match:
            status = match.group(1).upper()
            break
    return ReportInfo(
        sig=hashlib.sha256(text.encode()).hexdigest()[:16],
        mtime=stat.st_mtime,
        status=status if status in REPORT_STATUSES else "UNKNOWN",
        prs=sorted(set(PR_URL.findall(text))),
    )


# --- Pane normalisation ----------------------------------------------------

SPINNER = re.compile(r"[⠀-⣿✦-✿·*✢✳✶✻✽◐◑◒◓]")


def pane_signature(text: str) -> str:
    """Hash of a pane tail that ignores timers, token counters and spinners.

    Claude Code redraws an elapsed-time spinner every second while it works,
    so the raw text never repeats. Dropping digits and spinner glyphs leaves
    only what the agent actually printed.
    """
    lines = [SPINNER.sub("", re.sub(r"\d+", "#", line)).strip() for line in text.splitlines()]
    return hashlib.sha256("\n".join(line for line in lines if line).encode()).hexdigest()[:16]


# --- Classifier ------------------------------------------------------------


@dataclass
class Classification:
    label: str
    confidence: float
    backend: str
    model: str
    latency_s: float
    cost_usd: float | None = None
    probabilities: dict[str, float] | None = None


class ClaudeBackend:
    """Haiku (or Opus, for the benchmark) through `claude -p`."""

    def __init__(self, name: str, model: str, effort: str | None, timeout: float):
        self.name, self.model, self.effort, self.timeout = name, model, effort, timeout

    def classify(self, pane: str) -> Classification:
        cmd = [
            "claude", "-p",
            "--model", self.model,
            "--no-session-persistence",
            "--output-format", "json",
            "--json-schema", json.dumps(CLASSIFIER_SCHEMA),
            "--tools", "",
            "--system-prompt", CLASSIFIER_SYSTEM,
        ]
        if self.effort:
            cmd += ["--effort", self.effort]
        started = time.monotonic()
        out = json.loads(run(cmd, input_text=f"Terminal:\n{pane}", timeout=self.timeout))
        latency = time.monotonic() - started
        if out.get("is_error"):
            raise RuntimeError(out.get("result") or "claude -p failed")
        answer = out.get("structured_output") or json.loads(out["result"])
        model = next(iter(out.get("modelUsage") or {}), self.model)
        return Classification(
            label=answer["label"],
            confidence=max(0.0, min(1.0, float(answer["confidence"]))),
            backend=self.name,
            model=model,
            latency_s=latency,
            cost_usd=out.get("total_cost_usd"),
        )


class JevBackend:
    """TypeSafe's Jev decision model on OpenRouter's decisions endpoint.

    Jev isn't a chat model: it takes a state and named questions, and answers
    each `choice` question with a label, per-label probabilities and its own
    confidence score.
    """

    URL = "https://openrouter.ai/api/alpha/decisions"

    def __init__(self, model: str, api_key_env: str, timeout: float):
        self.model, self.api_key_env, self.timeout = model, api_key_env, timeout

    def classify(self, pane: str) -> Classification:
        key = os.environ.get(self.api_key_env)
        if not key:
            raise RuntimeError(f"${self.api_key_env} is not set")
        body = {
            "model": self.model,
            "state": {"terminal_tail": pane},
            "questions": {"agent_state": {"type": "choice", "criteria": LABELS}},
        }
        request = urllib.request.Request(
            self.URL,
            data=json.dumps(body).encode(),
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        )
        started = time.monotonic()
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                out = json.loads(response.read())
        except urllib.error.HTTPError as exc:
            # Never echo the request: it carries the key in its headers.
            raise RuntimeError(f"Jev HTTP {exc.code}: {exc.read()[:300]!r}") from None
        latency = time.monotonic() - started
        answer = out["answers"]["agent_state"]
        return Classification(
            label=answer["choice"],
            confidence=float(answer["confidence"]),
            backend="jev",
            model=out.get("model", self.model),
            latency_s=latency,
            cost_usd=(out.get("usage") or {}).get("cost"),
            probabilities=answer.get("probabilities"),
        )


def make_backend(cfg: dict[str, Any], name: str):
    c = cfg["classifier"]
    if name == "haiku":
        return ClaudeBackend("haiku", c["haiku_model"], c.get("haiku_effort"), c["timeout_seconds"])
    if name == "opus":
        tier = cfg["tiers"][cfg["workers"]["reviewer_tier"]]
        return ClaudeBackend("opus", tier["model"], c.get("opus_effort"), c["timeout_seconds"] * 3)
    if name == "jev":
        return JevBackend(c["jev_model"], c["api_key_env"], c["timeout_seconds"])
    raise ConfigError(f"unknown classifier backend {name!r}")


def route(c: Classification, band_low: float, band_high: float) -> str:
    """`escalate` inside the unsure band, otherwise `trust` the cheap label."""
    return "escalate" if band_low <= c.confidence < band_high else "trust"


# --- Engine ----------------------------------------------------------------


@dataclass
class Action:
    kind: str  # notify | nudge | classify
    worker: str
    text: str = ""
    reason: str = ""
    key: str = ""


@dataclass
class Observation:
    now: float
    agents: dict[str, dict[str, Any]]  # pane_id -> herdr agent record
    reports: dict[str, ReportInfo | None]  # worker -> report
    pane_sigs: dict[str, str] = field(default_factory=dict)  # working workers only
    prs: dict[str, PrInfo] = field(default_factory=dict)  # PRs polled this cycle
    orchestrator_ctx_pct: float | None = None
    # Worker -> time of the orchestrator's latest turn quoting `[<worker>]`.
    mentions: dict[str, float] = field(default_factory=dict)


class Engine:
    """Turns observations into one-line events. Pure apart from `state`.

    `state` is a JSON-able dict persisted between polls (and restarts), so an
    event that was already sent is never replayed. Each event has a dedupe
    key that names the episode it belongs to, e.g. the time a worker went
    idle; the same key is never emitted twice.
    """

    def __init__(self, cfg: dict[str, Any], ledger: dict[str, Any], state: dict[str, Any]):
        self.cfg, self.ledger, self.state = cfg, ledger, state
        state.setdefault("workers", {})
        state.setdefault("prs", {})
        state.setdefault("emitted", {})
        state.setdefault("sessions", {})

    # Helpers

    @property
    def classifier_on(self) -> bool:
        return self.cfg["classifier"]["backend"] != "off"

    def report_path(self, worker: str) -> str:
        return str(run_dir_for(Path(self.ledger["_path"])) / f"{worker}.report.md")

    def emit(self, actions: list[Action], action: Action, now: float) -> None:
        if action.key in self.state["emitted"]:
            return
        self.state["emitted"][action.key] = now
        actions.append(action)

    def forget(self, key: str) -> None:
        """Undo `emit` after a failed delivery so the next poll retries it."""
        self.state["emitted"].pop(key, None)

    def notify(self, actions: list[Action], now: float, worker: str, text: str, key: str) -> None:
        self.emit(actions, Action("notify", worker, f"[watch] {worker} {text}", key=key), now)

    def nudge(self, actions: list[Action], now: float, worker: str, which: str, key: str) -> bool:
        ws = self.state["workers"][worker]
        if ws["nudges"] >= self.cfg["watcher"]["max_nudges"]:
            return False
        text = self.cfg["nudges"][which].replace("{report}", self.report_path(worker))
        before = len(actions)
        self.emit(actions, Action("nudge", worker, text, reason=which, key=key), now)
        if len(actions) > before:
            ws["nudges"] += 1
            ws["last_nudge"] = now
        return True

    # Main step

    def step(self, obs: Observation) -> list[Action]:
        actions: list[Action] = []
        w_cfg = self.cfg["watcher"]
        debounce = w_cfg["debounce_seconds"]
        live = [w for w in self.ledger.get("workers", []) if w.get("status") == "running"]

        for worker in live:
            name = worker["name"]
            ws = self.state["workers"].setdefault(
                name,
                {"status": None, "since": obs.now, "pending": None, "pending_since": obs.now,
                 "working_since": 0.0, "report_sig": None, "nudges": 0, "last_nudge": 0.0,
                 "pane_sig": None, "pane_since": obs.now},
            )
            agent = obs.agents.get(worker.get("pane_id", ""))
            raw = agent.get("agent_status", "unknown") if agent else "gone"
            if agent and (agent.get("agent_session") or {}).get("value"):
                seen = self.state["sessions"].setdefault(name, [])
                if agent["agent_session"]["value"] not in seen:
                    seen.append(agent["agent_session"]["value"])

            # Debounce: a status counts only once it has held for `debounce`.
            if ws["status"] is None:
                ws.update(status=raw, since=obs.now, pending=None)
                if raw == "working":
                    ws["working_since"] = obs.now
            elif raw != ws["status"]:
                if ws["pending"] != raw:
                    ws.update(pending=raw, pending_since=obs.now)
                if obs.now - ws["pending_since"] >= debounce:
                    ws.update(status=raw, since=ws["pending_since"], pending=None)
                    if raw == "working":
                        ws["working_since"] = ws["since"]
                        ws.update(pane_sig=None, pane_since=obs.now)
            else:
                ws["pending"] = None

            report = obs.reports.get(name)
            if report:
                if report.sig != ws["report_sig"]:
                    ws.update(report_sig=report.sig, nudges=0)
                # Workers notify the orchestrator themselves after writing the
                # report. Speak up only if that message hasn't arrived within
                # the grace period, so one finish costs one orchestrator turn.
                key = f"{name}:report:{report.sig}"
                notified = obs.mentions.get(name, 0.0) >= report.mtime - 5
                if notified:
                    self.state["emitted"].setdefault(key, obs.now)
                elif obs.now - report.mtime >= w_cfg["report_grace_seconds"]:
                    # Deduped by key, so a failed delivery is retried next poll.
                    self.notify(actions, obs.now, name,
                                f"REPORT status={report.status} report={self.report_path(name)} (worker did not notify)",
                                key=key)
            reported = bool(report and report.mtime >= ws["working_since"])
            status, since = ws["status"], ws["since"]
            episode = f"{name}:{status}:{int(since)}"

            if status == "gone":
                self.notify(actions, obs.now, name, "GONE (agent no longer in its pane)", key=episode)
            elif status == "unknown":
                self.notify(actions, obs.now, name, "UNKNOWN state", key=episode)
            elif status == "blocked" and not reported:
                if self.classifier_on:
                    self.emit(actions, Action("classify", name, reason="blocked", key=episode), obs.now)
                else:
                    self.notify(actions, obs.now, name, "BLOCKED (waiting on a prompt)", key=episode)
            elif status in ("idle", "done") and not reported:
                idle_for = obs.now - max(since, ws["last_nudge"])
                if idle_for >= w_cfg["idle_minutes"] * 60:
                    key = f"{episode}:{ws['nudges']}"
                    if self.classifier_on:
                        self.emit(actions, Action("classify", name, reason="idle", key=key), obs.now)
                    elif not self.nudge(actions, obs.now, name, "report", key):
                        self.notify(actions, obs.now, name,
                                    f"IDLE_NO_REPORT for {int(idle_for // 60)}m", key=f"{episode}:escalate")
            elif status == "working" and name in obs.pane_sigs:
                sig = obs.pane_sigs[name]
                if sig != ws["pane_sig"]:
                    ws.update(pane_sig=sig, pane_since=obs.now)
                elif obs.now - ws["pane_since"] >= w_cfg["stall_minutes"] * 60:
                    key = f"{name}:stall:{sig}:{int(ws['pane_since'])}"
                    if self.classifier_on:
                        self.emit(actions, Action("classify", name, reason="stall", key=key), obs.now)
                    else:
                        minutes = int((obs.now - ws["pane_since"]) // 60)
                        self.notify(actions, obs.now, name, f"STALLED (no new output for {minutes}m)", key=key)

        self._step_prs(actions, obs)
        self._step_orchestrator(actions, obs)
        return actions

    def tracked_prs(self, reports: dict[str, ReportInfo | None]) -> dict[str, str]:
        """PR URL -> worker, from the ledger and the workers' reports."""
        prs: dict[str, str] = {}
        for worker in self.ledger.get("workers", []):
            if worker.get("status") in ("closed", "failed"):
                continue
            urls = list(worker.get("prs") or [])
            report = reports.get(worker["name"])
            urls += report.prs if report else []
            for url in urls:
                prs.setdefault(url, worker["name"])
        return prs

    def _step_prs(self, actions: list[Action], obs: Observation) -> None:
        for url, info in obs.prs.items():
            entry = self.state["prs"].setdefault(url, {"key": None, "checked_at": 0.0, "changes": 0})
            entry["checked_at"] = obs.now
            entry["state"] = info.state
            # Count changes so a PR that goes green again after a new push
            # notifies again rather than matching the earlier event.
            if info.key() != entry["key"]:
                entry["key"] = info.key()
                entry["changes"] = entry.get("changes", 0) + 1
            if info.notable():
                worker = self.tracked_prs(obs.reports).get(url, "pr")
                self.notify(actions, obs.now, worker,
                            f"PR {url} state={info.state} checks={info.checks} merge={info.merge}",
                            key=f"pr:{url}:{entry['changes']}")

    def _step_orchestrator(self, actions: list[Action], obs: Observation) -> None:
        pane = self.ledger.get("orchestrator_pane", "")
        agent = obs.agents.get(pane)
        session = (agent or {}).get("agent_session", {}).get("value")
        if session:
            seen = self.state["sessions"].setdefault("orchestrator", [])
            if session not in seen:
                seen.append(session)
        limit = self.cfg["orchestrator"]["rotate_at_percent"]
        if obs.orchestrator_ctx_pct is not None and obs.orchestrator_ctx_pct >= limit:
            self.emit(actions, Action(
                "notify", "orchestrator",
                f"[watch] orchestrator ROTATE ctx={obs.orchestrator_ctx_pct:.0f}% (limit {limit}%)",
                key=f"rotate:{session}",
            ), obs.now)

    def on_classified(self, action: Action, result: Classification | None, now: float) -> list[Action]:
        """Act on a tier-2 answer: trust it when confident, else escalate."""
        actions: list[Action] = []
        name, reason, key = action.worker, action.reason.upper(), action.key
        if result is None:
            self.notify(actions, now, name, f"{reason} (classifier failed)", key=f"{key}:escalate")
            return actions
        c = self.cfg["classifier"]
        tag = f"label={result.label} conf={result.confidence:.2f}"
        if route(result, c["band_low"], c["band_high"]) == "escalate":
            self.notify(actions, now, name, f"{reason} unsure {tag}", key=f"{key}:escalate")
            return actions
        ws = self.state["workers"][name]
        if result.label == "working" and action.reason != "idle":
            ws["pane_since"] = now  # Look again after another stall period.
        elif result.label in ("finished", "working"):
            if not self.nudge(actions, now, name, "report", f"{key}:nudge"):
                self.notify(actions, now, name, f"{reason} {tag}, no report after nudges", key=f"{key}:escalate")
        elif result.label == "routine_question":
            if not self.nudge(actions, now, name, "routine", f"{key}:nudge"):
                self.notify(actions, now, name, f"{reason} {tag}, nudges used up", key=f"{key}:escalate")
        elif result.label in ("stuck", "looping"):
            if not self.nudge(actions, now, name, "blocked", f"{key}:nudge"):
                self.notify(actions, now, name, f"{reason} {tag}, nudges used up", key=f"{key}:escalate")
        else:
            self.notify(actions, now, name, f"{reason} {tag}", key=f"{key}:escalate")
        return actions


# --- Token accounting ------------------------------------------------------


def session_files(session_id: str) -> list[Path]:
    """A session's transcript plus any subagent transcripts stored under it."""
    files = list(CLAUDE_PROJECTS.glob(f"*/{session_id}.jsonl"))
    for main in list(files):
        files += sorted(main.with_suffix("").glob("**/*.jsonl"))
    return files


def transcript_usage(paths: list[Path]) -> dict[str, dict[str, int]]:
    """Token totals by model. Streaming writes one record per content block,
    so each assistant message is counted once by its ID."""
    seen: set[str] = set()
    totals: dict[str, dict[str, int]] = {}
    for path in paths:
        try:
            lines = path.read_text(errors="replace").splitlines()
        except OSError:
            continue
        for line in lines:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            msg = rec.get("message") or {}
            usage, model = msg.get("usage"), msg.get("model")
            if rec.get("type") != "assistant" or not usage or not model or model == "<synthetic>":
                continue
            mid = msg.get("id") or rec.get("uuid")
            if mid in seen:
                continue
            seen.add(mid)
            t = totals.setdefault(model, {"input": 0, "cache_write": 0, "cache_read": 0, "output": 0, "turns": 0})
            t["input"] += usage.get("input_tokens") or 0
            t["cache_write"] += usage.get("cache_creation_input_tokens") or 0
            t["cache_read"] += usage.get("cache_read_input_tokens") or 0
            t["output"] += usage.get("output_tokens") or 0
            t["turns"] += 1
    return totals


def orchestrator_view(session_id: str, window: int, workers: list[str]) -> tuple[float | None, dict[str, float]]:
    """From the tail of the orchestrator's transcript: its context use (as the
    statusline computes it) and when each worker's `[<worker>]` message
    last arrived."""
    files = list(CLAUDE_PROJECTS.glob(f"*/{session_id}.jsonl"))
    if not files:
        return None, {}
    try:
        with files[0].open("rb") as handle:
            handle.seek(max(0, handle.seek(0, os.SEEK_END) - 512 * 1024))
            lines = handle.read().decode(errors="replace").splitlines()
    except OSError:
        return None, {}
    ctx: float | None = None
    mentions: dict[str, float] = {}
    for line in reversed(lines):
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        msg = rec.get("message") or {}
        if ctx is None and rec.get("type") == "assistant" and msg.get("usage"):
            usage = msg["usage"]
            used = sum(usage.get(k) or 0 for k in (
                "input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
            ctx = 100.0 * used / window
        if rec.get("type") == "user":
            text = json.dumps(msg.get("content", ""))
            for name in workers:
                if name not in mentions and f"[{name}]" in text:
                    mentions[name] = parse_time(rec.get("timestamp"))
    return ctx, mentions


def merge_usage(into: dict[str, dict[str, int]], more: dict[str, dict[str, int]]) -> None:
    for model, counts in more.items():
        t = into.setdefault(model, dict.fromkeys(counts, 0))
        for k, v in counts.items():
            t[k] = t.get(k, 0) + v


def legacy_sessions(ledger: dict[str, Any]) -> dict[str, list[str]]:
    """Find sessions for ledgers written before session IDs were recorded.

    Workers' first prompt is their brief, which names the worker in its
    report-back line; the orchestrator's sessions mention `orch-<slug>`
    without being a worker brief.
    """
    slug, started = ledger["slug"], parse_time(ledger.get("started_at"))
    names = [w["name"] for w in ledger.get("workers", [])]
    found: dict[str, list[str]] = {}
    for path in CLAUDE_PROJECTS.glob("*/*.jsonl"):
        try:
            if path.stat().st_mtime < started:
                continue
            text = path.read_text(errors="replace")
        except OSError:
            continue
        if f"orch-{slug}" not in text:
            continue
        first_user = ""
        for line in text.splitlines():
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("type") == "user" and not rec.get("isMeta"):
                first_user = json.dumps(rec.get("message", {}).get("content", ""))
                break
        role = next((n for n in names if f"[{n}]" in first_user), "orchestrator")
        found.setdefault(role, []).append(path.stem)
    return found


def run_sessions(ledger_path: Path) -> dict[str, list[str]]:
    ledger = read_json(ledger_path, {})
    sessions: dict[str, list[str]] = {}

    def add(role: str, ids: list[str]) -> None:
        for sid in ids:
            if sid and sid not in sessions.setdefault(role, []):
                sessions[role].append(sid)

    add("orchestrator", ledger.get("orchestrator_sessions") or [])
    for worker in ledger.get("workers", []):
        add(worker["name"], worker.get("session_ids") or [])
    state = read_json(run_dir_for(ledger_path) / "watch-state.json", {})
    for role, ids in (state.get("sessions") or {}).items():
        add(role, ids)
    if not sessions:
        for role, ids in legacy_sessions(ledger).items():
            add(role, ids)
    return sessions


def classifier_spend(ledger_path: Path) -> tuple[int, float]:
    calls, cost = 0, 0.0
    log_path = run_dir_for(ledger_path) / "classifier.jsonl"
    try:
        for line in log_path.read_text().splitlines():
            rec = json.loads(line)
            calls += 1
            cost += rec.get("cost_usd") or 0.0
    except (OSError, ValueError):
        pass
    return calls, cost


def fmt_tokens(n: int) -> str:
    return f"{n / 1e6:.2f}M" if n >= 1e6 else f"{n / 1e3:.1f}k"


def cmd_report(args: argparse.Namespace) -> int:
    cfg = load_config()
    if args.session:
        # Sessions without a ledger, e.g. orchestrators from before this
        # tool, to compare against.
        runs = [(None, {"slug": "sessions"}, {sid: [sid] for sid in args.session})]
    elif args.run:
        ledgers = resolve_ledgers(cfg, args.run)
        if not ledgers:
            print(f"no ledger matches {args.run!r}", file=sys.stderr)
            return 1
        runs = [(path, read_json(path, {}), run_sessions(path)) for path in ledgers]
    else:
        print("give a run slug, a ledger path or --session", file=sys.stderr)
        return 2
    out = []
    for ledger_path, ledger, sessions in runs:
        by_role = {role: transcript_usage([f for s in ids for f in session_files(s)])
                   for role, ids in sessions.items()}
        by_model: dict[str, dict[str, int]] = {}
        for usage in by_role.values():
            merge_usage(by_model, usage)
        calls, cost = classifier_spend(ledger_path) if ledger_path else (0, 0.0)
        out.append({"ledger": str(ledger_path), "slug": ledger.get("slug"), "by_role": by_role,
                    "by_model": by_model, "classifier_calls": calls, "classifier_cost_usd": cost})
    if args.json:
        print(json.dumps(out, indent=2))
        return 0
    cols = ("input", "cache_write", "cache_read", "output", "turns")
    for run_report in out:
        print(f"## {run_report['slug']}  ({run_report['ledger']})")
        if not run_report["by_model"]:
            print("No Claude transcripts found. Ledgers written before session IDs were recorded are\n"
                  "matched by `orch-<slug>` in ~/.claude/projects; Codex runs aren't covered.\n")
            continue
        for title, table in (("By model", run_report["by_model"]), ("By agent", None)):
            print(f"\n{title}:")
            print(f"  {'':34} " + " ".join(f"{c:>11}" for c in cols))
            rows = table.items() if table is not None else [
                (f"{role} {model}", t)
                for role, usage in run_report["by_role"].items() for model, t in usage.items()]
            for label, t in rows:
                cells = [fmt_tokens(t[c]) if c != "turns" else str(t[c]) for c in cols]
                print(f"  {label[:34]:34} " + " ".join(f"{c:>11}" for c in cells))
        if run_report["classifier_calls"]:
            print(f"\nClassifier: {run_report['classifier_calls']} calls, ${run_report['classifier_cost_usd']:.4f}")
        print()
    return 0


def resolve_ledgers(cfg: dict[str, Any], run_arg: str) -> list[Path]:
    path = Path(os.path.expanduser(run_arg))
    if path.suffix == ".json" and path.exists():
        return [path]
    return sorted(state_root(cfg).glob(f"*/{run_arg}.json"))


def cmd_record_usage(args: argparse.Namespace) -> int:
    """Write a finished worker's model, timing and token totals to the ledger."""
    ledger_path = Path(os.path.expanduser(args.ledger))
    ledger = read_json(ledger_path)
    if ledger is None:
        print(f"cannot read {ledger_path}", file=sys.stderr)
        return 1
    ledger["_path"] = str(ledger_path)
    worker = next((w for w in ledger.get("workers", []) if w["name"] == args.worker), None)
    if worker is None:
        print(f"no worker {args.worker!r} in {ledger_path}", file=sys.stderr)
        return 1
    sessions = run_sessions(ledger_path).get(args.worker, [])
    usage = transcript_usage([f for s in sessions for f in session_files(s)])
    worker["session_ids"] = sessions
    worker["finished_at"] = utc_now()
    worker["usage"] = usage or None
    worker["usage_source"] = "transcript" if usage else "unavailable: no transcript found"
    ledger.pop("_path", None)
    write_json(ledger_path, ledger)
    print(json.dumps({"worker": args.worker, "usage": usage, "sessions": sessions}))
    return 0


# --- Watch loop ------------------------------------------------------------


def load_ledger(path: Path) -> dict[str, Any] | None:
    ledger = read_json(path)
    if ledger is not None:
        ledger["_path"] = str(path)
    return ledger


def cmd_watch(args: argparse.Namespace) -> int:
    cfg = load_config()
    ledger_path = Path(os.path.expanduser(args.ledger)).resolve()
    run_dir = run_dir_for(ledger_path)
    state_path = run_dir / "watch-state.json"
    state = read_json(state_path, {}) or {}
    state.setdefault("created_at", utc_now())
    w_cfg, c_cfg = cfg["watcher"], cfg["classifier"]
    backend = make_backend(cfg, c_cfg["backend"]) if c_cfg["backend"] != "off" else None
    log(f"watching {ledger_path} (classifier: {c_cfg['backend']})")
    orchestrator_missing_since: float | None = None

    while True:
        ledger = load_ledger(ledger_path)
        if ledger is None:
            log("ledger unreadable; retrying")
            time.sleep(w_cfg["poll_seconds"])
            continue
        if ledger.get("closed_at"):
            log("run closed; exiting")
            return 0
        engine = Engine(cfg, ledger, state)
        now = time.time()
        try:
            agents = herdr_agents()
        except (subprocess.SubprocessError, OSError, ValueError) as exc:
            log(f"herdr agent list failed: {exc}")
            time.sleep(w_cfg["poll_seconds"])
            continue

        orch_pane = ledger.get("orchestrator_pane", "")
        orch = agents.get(orch_pane)
        if orch is None:
            orchestrator_missing_since = orchestrator_missing_since or now
            if now - orchestrator_missing_since > w_cfg["debounce_seconds"] * 5:
                log("orchestrator gone; exiting")
                write_json(state_path, state)
                return 2
        else:
            orchestrator_missing_since = None

        live = [w for w in ledger.get("workers", []) if w.get("status") == "running"]
        reports = {w["name"]: read_report(run_dir / f"{w['name']}.report.md") for w in ledger.get("workers", [])}
        pane_sigs = {}
        for w in live:
            if (agents.get(w.get("pane_id", "")) or {}).get("agent_status") == "working":
                try:
                    pane_sigs[w["name"]] = pane_signature(herdr_read(w["pane_id"], 40))
                except (subprocess.SubprocessError, OSError):
                    pass
        prs = {}
        for url in engine.tracked_prs(reports):
            entry = state["prs"].get(url, {})
            if entry.get("state") in ("MERGED", "CLOSED"):
                continue
            if now - entry.get("checked_at", 0.0) >= w_cfg["pr_poll_seconds"]:
                try:
                    prs[url] = gh_pr_info(url)
                except (subprocess.SubprocessError, OSError, ValueError) as exc:
                    log(f"gh pr view {url} failed: {exc}")
        ctx, mentions = None, {}
        orch_session = ((orch or {}).get("agent_session") or {}).get("value")
        if orch_session:
            ctx, mentions = orchestrator_view(
                orch_session, cfg["orchestrator"]["context_window_tokens"],
                [w["name"] for w in ledger.get("workers", [])])
        if orch and ledger.get("rotate_requested") and not args.dry_run:
            restart_orchestrator(ledger_path, orch, state)
            time.sleep(w_cfg["poll_seconds"])
            continue

        actions = engine.step(Observation(now, agents, reports, pane_sigs, prs, ctx, mentions))
        for action in [a for a in actions if a.kind == "classify"]:
            actions.remove(action)
            actions += engine.on_classified(action, classify_worker(cfg, backend, ledger, action), time.time())

        deliver(engine, ledger, actions, dry_run=args.dry_run)
        state["heartbeat_at"] = utc_now()
        write_json(state_path, state)
        if args.once:
            return 0
        time.sleep(w_cfg["poll_seconds"])


def restart_orchestrator(ledger_path: Path, orch: dict[str, Any], state: dict[str, Any]) -> None:
    """Clear the orchestrator once it is idle and have it rebuild from the ledger.

    The orchestrator writes its handoff and sets `rotate_requested`; it can't
    clear its own context mid-turn, so the watcher does it between turns.
    """
    if orch.get("agent_status") not in ("idle", "done"):
        return
    pane = orch["pane_id"]
    log("rotating orchestrator")
    try:
        herdr_prompt(pane, "/clear")
        deadline = time.time() + 60
        while time.time() < deadline:
            time.sleep(3)
            status = json.loads(run(["herdr", "agent", "get", pane]))["result"]["agent"]["agent_status"]
            if status in ("idle", "done"):
                break
        herdr_prompt(pane, f"/herdr-orchestrator --resume {ledger_path}")
    except (subprocess.SubprocessError, OSError, ValueError, KeyError) as exc:
        log(f"rotation failed: {exc}")
        return
    ledger = read_json(ledger_path, {})
    ledger["rotate_requested"] = False
    ledger["rotations"] = ledger.get("rotations", 0) + 1
    write_json(ledger_path, ledger)
    state["rotated_at"] = utc_now()


def classify_worker(cfg, backend, ledger, action: Action) -> Classification | None:
    worker = next(w for w in ledger["workers"] if w["name"] == action.worker)
    try:
        pane = herdr_read(worker["pane_id"], cfg["classifier"]["pane_lines"])
        result = backend.classify(redact(pane))
    except Exception as exc:  # Any failure escalates; never crash the loop.
        log(f"classify {action.worker} failed: {exc}")
        return None
    log_path = run_dir_for(Path(ledger["_path"])) / "classifier.jsonl"
    with log_path.open("a") as handle:
        handle.write(json.dumps({
            "at": utc_now(), "worker": action.worker, "reason": action.reason,
            "label": result.label, "confidence": result.confidence, "backend": result.backend,
            "model": result.model, "latency_s": round(result.latency_s, 3), "cost_usd": result.cost_usd,
        }) + "\n")
    log(f"classified {action.worker} ({action.reason}): {result.label} {result.confidence:.2f}")
    return result


def deliver(engine: Engine, ledger: dict[str, Any], actions: list[Action], *, dry_run: bool) -> None:
    """Send nudges to workers, and all notifications as one orchestrator prompt."""
    names = {w["name"]: w.get("pane_id") for w in ledger.get("workers", [])}
    for action in [a for a in actions if a.kind == "nudge"]:
        log(f"nudge {action.worker}: {action.reason}")
        if dry_run:
            continue
        try:
            herdr_prompt(names.get(action.worker) or action.worker, action.text)
        except (subprocess.SubprocessError, OSError) as exc:
            log(f"nudge failed: {exc}")
            engine.forget(action.key)
    notes = [a for a in actions if a.kind == "notify"]
    if not notes:
        return
    text = " | ".join(a.text for a in notes)
    log(f"notify: {text}")
    if dry_run:
        return
    target = ledger.get("orchestrator_agent") or ledger.get("orchestrator_pane")
    try:
        herdr_prompt(target, text)
    except (subprocess.SubprocessError, OSError) as exc:
        log(f"notify failed: {exc}")
        for action in notes:
            engine.forget(action.key)


def cmd_classify(args: argparse.Namespace) -> int:
    cfg = load_config()
    backend = make_backend(cfg, args.backend or cfg["classifier"]["backend"])
    text = Path(args.file).read_text() if args.file else herdr_read(args.target, cfg["classifier"]["pane_lines"])
    result = backend.classify(redact(text))
    print(json.dumps(result.__dict__))
    return 0


def cmd_config(args: argparse.Namespace) -> int:
    print(CONFIG_PATH.read_text(), end="")
    return 0


# --- Benchmark -------------------------------------------------------------

REDACTIONS = [
    (re.compile(r"[\w.+-]+@[\w-]+(\.[\w-]+)+"), "<email>"),
    (re.compile(r"\b(sk|pk|rk)-[A-Za-z0-9_-]{16,}"), "<key>"),
    (re.compile(r"\b(ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]{20,}"), "<key>"),
    (re.compile(r"\bxox[abpors]-[A-Za-z0-9-]{10,}"), "<key>"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "<key>"),
    (re.compile(r"(?i)(bearer|token|secret|password|api[_-]?key)([\"']?\s*[:=]\s*[\"']?|\s+)[^\s\"']{8,}"), r"\1\2<redacted>"),
    (re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+"), "<jwt>"),
    (re.compile(r"\b[A-Fa-f0-9]{40,}\b"), "<hex>"),
    (re.compile(r"\b[A-Za-z0-9+/]{48,}={0,2}"), "<blob>"),
    (re.compile(r"\b\d{1,3}(\.\d{1,3}){3}\b"), "<ip>"),
    (re.compile(r"\+?\b\d{3}[ .-]\d{3}[ .-]\d{4}\b"), "<phone>"),
    (re.compile(r"(https?://[^\s?]+)\?[^\s]+"), r"\1?<query>"),
    (re.compile(re.escape(str(HOME))), "~"),
]


def redact(text: str) -> str:
    for pattern, replacement in REDACTIONS:
        text = pattern.sub(replacement, text)
    return text


def bench_dir(cfg: dict[str, Any], arg: str | None) -> Path:
    return Path(os.path.expanduser(arg)) if arg else state_root(cfg) / "bench"


def cmd_bench_extract(args: argparse.Namespace) -> int:
    """Collect pane snapshots that orchestrators read with `herdr agent read`."""
    cfg = load_config()
    out_dir = bench_dir(cfg, args.dir)
    seen: set[str] = set()
    rows = []
    for path in sorted(CLAUDE_PROJECTS.rglob("*.jsonl")):
        try:
            text = path.read_text(errors="replace")
        except OSError:
            continue
        if "herdr agent read" not in text:
            continue
        calls: dict[str, str] = {}
        for line in text.splitlines():
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            content = (rec.get("message") or {}).get("content")
            if not isinstance(content, list):
                continue
            for part in content:
                if part.get("type") == "tool_use":
                    command = str((part.get("input") or {}).get("command", ""))
                    # One read per command: the watcher classifies a single
                    # pane, and chained reads print several panes together.
                    if command.count("herdr agent read") == 1 and "for " not in command:
                        calls[part["id"]] = command
                elif part.get("type") == "tool_result" and part.get("tool_use_id") in calls:
                    body = part.get("content")
                    if isinstance(body, list):
                        body = "\n".join(x.get("text", "") for x in body if isinstance(x, dict))
                    lines = [ln for ln in (body or "").splitlines() if ln.strip()]
                    if len(lines) < args.min_lines:
                        continue
                    snap = redact("\n".join(lines[-args.lines:]))
                    digest = pane_signature(snap)
                    if digest in seen:
                        continue
                    seen.add(digest)
                    rows.append({"id": digest, "source": f"{path.parent.name}/{path.name}",
                                 "ts": rec.get("timestamp"), "text": snap})
    out_dir.mkdir(parents=True, exist_ok=True)
    with (out_dir / "candidates.jsonl").open("w") as handle:
        for row in rows:
            handle.write(json.dumps(row) + "\n")
    print(f"wrote {len(rows)} snapshots to {out_dir / 'candidates.jsonl'}")
    return 0


def transcript_events(path: Path) -> list[tuple[str, str, bool]]:
    """(kind, text, is_error) for a session, in order: say, tool, result, user."""
    events = []
    for line in path.read_text(errors="replace").splitlines():
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if rec.get("isSidechain") or rec.get("isMeta"):
            continue
        content = (rec.get("message") or {}).get("content")
        if isinstance(content, str) and rec.get("type") == "user":
            if not content.startswith("<"):
                events.append(("user", content, False))
            continue
        for part in content if isinstance(content, list) else []:
            kind = part.get("type")
            if kind == "text" and rec.get("type") == "assistant":
                events.append(("say", part.get("text", ""), False))
            elif kind == "text" and rec.get("type") == "user" and not part.get("text", "").startswith("<"):
                events.append(("user", part.get("text", ""), False))
            elif kind == "tool_use":
                inp = part.get("input") or {}
                arg = inp.get("command") or inp.get("file_path") or inp.get("pattern") or inp.get("description") or ""
                events.append(("tool", f"{part.get('name')}({str(arg).splitlines()[0][:100] if arg else ''})", False))
            elif kind == "tool_result":
                body = part.get("content")
                if isinstance(body, list):
                    body = "\n".join(x.get("text", "") for x in body if isinstance(x, dict))
                events.append(("result", body or "", bool(part.get("is_error"))))
    return events


def render_pane(events: list[tuple[str, str, bool]], lines: int, idle: bool) -> str:
    """Approximate the Claude Code TUI for a stretch of transcript."""
    out: list[str] = []
    for kind, text, _ in events:
        body = text.strip().splitlines() or [""]
        if kind == "say":
            out += [f"⏺ {body[0]}"] + [f"  {ln}" for ln in body[1:]]
        elif kind == "tool":
            out.append(f"⏺ {text}")
        elif kind == "result":
            out += [f"  ⎿  {body[0][:160]}"] + [f"     {ln[:160]}" for ln in body[1:4]]
            if len(body) > 4:
                out.append(f"     … +{len(body) - 4} lines (ctrl+o to expand)")
        elif kind == "user":
            out += ["", f"> {body[0][:160]}"] + [f"  {ln[:160]}" for ln in body[1:3]]
    out += ["", "─" * 60, "❯ ", "─" * 60] if idle else ["", "✻ Working… (esc to interrupt)"]
    return "\n".join(out[-lines:])


def cmd_bench_mine(args: argparse.Namespace) -> int:
    """Render pane-like snapshots at likely loops and questions in transcripts.

    Orchestrators rarely read a pane at those moments, so the extracted set
    lacks them. The next user reply after a question goes to hints.jsonl to
    help with labelling; classifiers never see it.
    """
    cfg = load_config()
    out_dir = bench_dir(cfg, args.dir)
    rows, hints, seen = [], [], set()
    paths = sorted(CLAUDE_PROJECTS.glob("*/*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    loops = questions = 0
    for path in paths:
        try:
            events = transcript_events(path)
        except OSError:
            continue
        for i, (kind, text, is_error) in enumerate(events):
            point = None
            # Three failing results in a row with the same first line.
            if kind == "result" and is_error and loops < args.max_each:
                prior = [e for e in events[max(0, i - 6):i + 1] if e[0] == "result"]
                firsts = {(e[1].strip().splitlines() or [""])[0][:60] for e in prior[-3:]}
                if len(prior) >= 3 and all(e[2] for e in prior[-3:]) and len(firsts) == 1:
                    point, idle, kind_tag = i + 1, False, "loop"
            # An assistant turn that ends in a question, then a user reply.
            elif (kind == "say" and text.rstrip().endswith("?") and i + 1 < len(events)
                  and events[i + 1][0] == "user" and questions < args.max_each):
                point, idle, kind_tag = i + 1, True, "question"
            if point is None:
                continue
            snap = redact(render_pane(events[max(0, point - 40):point], args.lines, idle))
            digest = pane_signature(snap)
            if digest in seen:
                continue
            seen.add(digest)
            if kind_tag == "loop":
                loops += 1
            else:
                questions += 1
                hints.append({"id": digest, "next_user_reply": redact(events[point][1][:400])})
            rows.append({"id": digest, "source": f"rendered:{kind_tag}:{path.parent.name}/{path.name}",
                         "ts": None, "text": snap})
        if loops >= args.max_each and questions >= args.max_each:
            break
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, data in (("mined.jsonl", rows), ("hints.jsonl", hints)):
        with (out_dir / name).open("w") as handle:
            for row in data:
                handle.write(json.dumps(row) + "\n")
    print(f"wrote {loops} loop and {questions} question snapshots to {out_dir / 'mined.jsonl'}")
    return 0


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    try:
        return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    except OSError:
        return []


def labelled_set(out_dir: Path) -> list[dict[str, Any]]:
    """Candidates joined with labels.jsonl; excluded rows are dropped."""
    texts, sources = {}, {}
    for name in ("candidates.jsonl", "mined.jsonl"):
        for r in read_jsonl(out_dir / name):
            texts[r["id"]], sources[r["id"]] = r["text"], r["source"]
    rows = []
    for label in read_jsonl(out_dir / "labels.jsonl"):
        if label.get("exclude") or label["id"] not in texts:
            continue
        if label["label"] not in LABELS:
            raise SystemExit(f"bad label {label['label']!r} for {label['id']}")
        kind = "rendered" if sources[label["id"]].startswith("rendered:") else "pane"
        rows.append({**label, "text": texts[label["id"]], "kind": kind})
    return rows


def cmd_bench_run(args: argparse.Namespace) -> int:
    cfg = load_config()
    out_dir = bench_dir(cfg, args.dir)
    rows = labelled_set(out_dir)
    backend = make_backend(cfg, args.backend)
    results_path = out_dir / f"results-{args.backend}.jsonl"
    done = {r["id"] for r in read_jsonl(results_path) if not r.get("error")}
    todo = [r for r in rows if r["id"] not in done][: args.limit or None]
    print(f"{args.backend}: {len(todo)} to run, {len(done)} cached")

    def one(row: dict[str, Any]) -> dict[str, Any]:
        try:
            c = backend.classify(row["text"])
            return {"id": row["id"], **c.__dict__}
        except Exception as exc:
            return {"id": row["id"], "error": str(exc)[:300]}

    with ThreadPoolExecutor(max_workers=args.concurrency) as pool, results_path.open("a") as handle:
        for result in pool.map(one, todo):
            handle.write(json.dumps(result) + "\n")
            handle.flush()
            print(f"  {result['id']}: {result.get('label', 'ERROR')} {result.get('confidence', '')}")
    return 0


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return float("nan")
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round(pct / 100 * (len(ordered) - 1))))
    return ordered[index]


BUCKETS = ((0.0, 0.5), (0.5, 0.7), (0.7, 0.9), (0.9, 1.01))


def auroc(right: list[float], wrong: list[float]) -> float | None:
    """Chance that a correct answer has higher confidence than a wrong one.

    0.5 means confidence says nothing about correctness, and escalating by
    confidence can't work; 1.0 means every wrong answer is less confident
    than every right one.
    """
    if not right or not wrong:
        return None
    wins = sum((r > w) + 0.5 * (r == w) for r in right for w in wrong)
    return wins / (len(right) * len(wrong))


def backend_stats(rows: list[dict[str, Any]], results: dict[str, dict[str, Any]], high: float = 0.9) -> dict[str, Any]:
    scored = [(r, results[r["id"]]) for r in rows if r["id"] in results]
    right = [res["confidence"] for r, res in scored if res["label"] == r["label"]]
    wrong = [res["confidence"] for r, res in scored if res["label"] != r["label"]]
    buckets = []
    for lo, hi in BUCKETS:
        inside = [(r, res) for r, res in scored if lo <= res["confidence"] < hi]
        hits = sum(res["label"] == r["label"] for r, res in inside)
        buckets.append({"range": f"{lo:.1f}–{min(hi, 1.0):.1f}", "n": len(inside),
                        "accuracy": hits / len(inside) if inside else None})
    by_kind = {}
    for kind in ("pane", "rendered"):
        subset = [(r, res) for r, res in scored if r.get("kind") == kind]
        if subset:
            by_kind[kind] = sum(res["label"] == r["label"] for r, res in subset) / len(subset)
    costs = [res.get("cost_usd") or 0.0 for _, res in scored]
    latencies = [res["latency_s"] for _, res in scored]
    return {
        "n": len(scored),
        "accuracy": len(right) / len(scored) if scored else None,
        "accuracy_by_kind": by_kind,
        "buckets": buckets,
        "mean_conf_right": sum(right) / len(right) if right else None,
        "mean_conf_wrong": sum(wrong) / len(wrong) if wrong else None,
        "auroc": auroc(right, wrong),
        "confident_errors": sum(c >= high for c in wrong),
        "errors": len(wrong),
        "p50_s": percentile(latencies, 50),
        "p95_s": percentile(latencies, 95),
        "cost_per_1k": 1000 * sum(costs) / len(costs) if costs else None,
    }


def cascade(rows, cheap, opus, low: float, high: float) -> dict[str, float] | None:
    """Cheap backend decides; its unsure band [low, high) goes to Opus."""
    scored = [r for r in rows if r["id"] in cheap and r["id"] in opus]
    if not scored:
        return None
    hits = escalated = 0
    cost = 0.0
    for r in scored:
        c = cheap[r["id"]]
        cost += c.get("cost_usd") or 0.0
        if low <= c["confidence"] < high:
            escalated += 1
            cost += opus[r["id"]].get("cost_usd") or 0.0
            hits += opus[r["id"]]["label"] == r["label"]
        else:
            hits += c["label"] == r["label"]
    n = len(scored)
    return {"low": low, "high": high, "accuracy": hits / n, "escalated": escalated / n,
            "cost_per_1k": 1000 * cost / n}


LOWS = (0.0, 0.1, 0.2, 0.3, 0.4, 0.5)
HIGHS = (0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 1.01)


def pick_band(sweep: list[dict[str, float]], target: float) -> dict[str, float]:
    """Cheapest band within `target` accuracy, else the most accurate."""
    good = [c for c in sweep if c["accuracy"] >= target]
    if good:
        return min(good, key=lambda c: (c["cost_per_1k"], -c["accuracy"]))
    return max(sweep, key=lambda c: (c["accuracy"], -c["cost_per_1k"]))


def frontier(sweep: list[dict[str, float]]) -> list[dict[str, float]]:
    """Bands no other band beats on both accuracy and cost."""
    best = []
    for c in sorted(sweep, key=lambda c: (c["cost_per_1k"], -c["accuracy"])):
        if not best or c["accuracy"] > best[-1]["accuracy"]:
            best.append(c)
    return best


def fmt(value: Any, spec: str = ".0%") -> str:
    if value is None or value != value:
        return "–"
    return format(value, spec)


def markdown_report(report: dict[str, Any]) -> str:
    out = [f"Labelled set: {report['n']} snapshots ("
           + ", ".join(f"{k} {v}" for k, v in sorted(report["labels"].items()))
           + f"); {report['unsure_labels']} labels flagged unsure.", ""]
    out += ["| Backend | Accuracy | Real panes | Rendered | AUROC (conf→correct) | Mean conf right / wrong | Errors at conf ≥ 0.9 | p50 | p95 | Cost / 1k calls |",
            "|---|---|---|---|---|---|---|---|---|---|"]
    for name, st in report["backends"].items():
        kinds = st["accuracy_by_kind"]
        out.append(
            f"| {name} | {fmt(st['accuracy'])} | {fmt(kinds.get('pane'))} | {fmt(kinds.get('rendered'))} "
            f"| {fmt(st['auroc'], '.2f')} | {fmt(st['mean_conf_right'], '.2f')} / {fmt(st['mean_conf_wrong'], '.2f')} "
            f"| {st['confident_errors']} of {st['errors']} | {fmt(st['p50_s'], '.1f')}s | {fmt(st['p95_s'], '.1f')}s "
            f"| ${fmt(st['cost_per_1k'], '.2f')} |")
    out += ["", "Calibration (accuracy within confidence buckets, n in brackets):", "",
            "| Backend | " + " | ".join(b["range"] for b in next(iter(report["backends"].values()))["buckets"]) + " |",
            "|---|" + "---|" * len(BUCKETS)]
    for name, st in report["backends"].items():
        out.append(f"| {name} | " + " | ".join(f"{fmt(b['accuracy'])} ({b['n']})" for b in st["buckets"]) + " |")
    for cheap, sweep in report["cascades"].items():
        out += ["", f"Cascade: {cheap} decides, band [low, high) goes to Opus (cost frontier):", "",
                "| low | high | Accuracy | Escalated | Cost / 1k |", "|---|---|---|---|---|"]
        for c in frontier(sweep):
            out.append(f"| {c['low']:.1f} | {min(c['high'], 1.0):.2f} | {fmt(c['accuracy'])} | {fmt(c['escalated'])} | ${c['cost_per_1k']:.2f} |")
        pick = report["picks"][cheap]
        out.append(f"\nCheapest band within 2 points of Opus-on-everything: [{pick['low']:.1f}, {min(pick['high'], 1.0):.2f}) "
                   f"→ {fmt(pick['accuracy'])} accuracy, {fmt(pick['escalated'])} escalated, ${pick['cost_per_1k']:.2f} / 1k.")
    return "\n".join(out)


def cmd_bench_analyze(args: argparse.Namespace) -> int:
    cfg = load_config()
    out_dir = bench_dir(cfg, args.dir)
    rows = labelled_set(out_dir)
    if args.sure_only:
        rows = [r for r in rows if not r.get("unsure")]
    results = {}
    for name in ("haiku", "jev", "opus"):
        latest: dict[str, dict[str, Any]] = {}
        for res in read_jsonl(out_dir / f"results-{name}.jsonl"):
            if not res.get("error"):
                latest[res["id"]] = res
        if latest:
            results[name] = latest
    stats = {name: backend_stats(rows, res) for name, res in results.items()}
    sweeps, picks = {}, {}
    if "opus" in results:
        target = stats["opus"]["accuracy"] - 0.02
        for cheap in ("haiku", "jev"):
            if cheap in results:
                sweeps[cheap] = [cascade(rows, results[cheap], results["opus"], low, high)
                                 for low in LOWS for high in HIGHS if low < high]
                picks[cheap] = pick_band(sweeps[cheap], target)
    counts: dict[str, int] = {}
    for r in rows:
        counts[r["label"]] = counts.get(r["label"], 0) + 1
    report = {"n": len(rows), "labels": counts, "unsure_labels": sum(bool(r.get("unsure")) for r in rows),
              "backends": stats, "cascades": sweeps, "picks": picks}
    print(markdown_report(report) if args.markdown else json.dumps(report, indent=2, default=float))
    return 0


# --- CLI -------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="herdr-orch", description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("watch", help="Watch a run's workers and prompt the orchestrator on transitions")
    p.add_argument("--ledger", required=True)
    p.add_argument("--once", action="store_true", help="Poll once and exit")
    p.add_argument("--dry-run", action="store_true", help="Log events instead of sending them")
    p.set_defaults(func=cmd_watch)

    p = sub.add_parser("classify", help="Classify a pane (or file) with the tier-2 classifier")
    p.add_argument("target", nargs="?", help="Herdr agent or pane")
    p.add_argument("--file")
    p.add_argument("--backend", choices=("haiku", "jev", "opus"))
    p.set_defaults(func=cmd_classify)

    p = sub.add_parser("record-usage", help="Record a finished worker's model and tokens in the ledger")
    p.add_argument("--ledger", required=True)
    p.add_argument("--worker", required=True)
    p.set_defaults(func=cmd_record_usage)

    p = sub.add_parser("report", help="Print tokens by model and agent for a run")
    p.add_argument("run", nargs="?", help="Run slug or ledger path")
    p.add_argument("--session", action="append", help="Report on a Claude session ID instead (repeatable)")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_report)

    p = sub.add_parser("config", help="Print the rendered config")
    p.set_defaults(func=cmd_config)

    bench = sub.add_parser("bench", help="Tier-2 classifier benchmark").add_subparsers(dest="bench", required=True)
    p = bench.add_parser("extract", help="Extract redacted pane snapshots from Claude transcripts")
    p.add_argument("--dir")
    p.add_argument("--lines", type=int, default=60)
    p.add_argument("--min-lines", type=int, default=8)
    p.set_defaults(func=cmd_bench_extract)
    p = bench.add_parser("mine", help="Render snapshots at likely loops and questions in transcripts")
    p.add_argument("--dir")
    p.add_argument("--lines", type=int, default=60)
    p.add_argument("--max-each", type=int, default=40)
    p.set_defaults(func=cmd_bench_mine)
    p = bench.add_parser("run", help="Classify the labelled set with one backend (resumable)")
    p.add_argument("backend", choices=("haiku", "jev", "opus"))
    p.add_argument("--dir")
    p.add_argument("--limit", type=int, default=0)
    p.add_argument("--concurrency", type=int, default=4)
    p.set_defaults(func=cmd_bench_run)
    p = bench.add_parser("analyze", help="Accuracy, calibration, latency, cost and cascade sweep")
    p.add_argument("--dir")
    p.add_argument("--markdown", action="store_true", help="Print the tables for a PR description")
    p.add_argument("--sure-only", action="store_true", help="Leave out labels flagged unsure")
    p.set_defaults(func=cmd_bench_analyze)

    args = parser.parse_args(argv)
    if args.command == "classify" and not (args.target or args.file):
        parser.error("classify needs a target or --file")
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
