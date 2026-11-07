from __future__ import annotations

import copy
import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "herdr_orch.py"
SPEC = importlib.util.spec_from_file_location("herdr_orch", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
herdr_orch = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = herdr_orch
SPEC.loader.exec_module(herdr_orch)

Observation = herdr_orch.Observation
ReportInfo = herdr_orch.ReportInfo
PrInfo = herdr_orch.PrInfo
Classification = herdr_orch.Classification

CONFIG = {
    "paths": {"state_dir": "~/.local/state/herdr-orchestrator"},
    "tiers": {
        "opus": {"model": "opus", "effort": "high", "use_for": "hard work"},
        "sonnet": {"model": "sonnet", "effort": "medium", "use_for": "pattern work"},
    },
    "workers": {
        "implementer_tier": "sonnet",
        "reviewer_tier": "opus",
        "escalate_to_tier": "opus",
        "escalate_after_failures": 2,
    },
    "watcher": {
        "poll_seconds": 30,
        "idle_minutes": 10,
        "debounce_seconds": 60,
        "stall_minutes": 20,
        "pr_poll_seconds": 300,
        "fallback_check_minutes": 60,
        "max_nudges": 1,
        "report_grace_seconds": 120,
        "waiting_max_minutes": 120,
    },
    "olive": {"enable": True, "repos": ["o/r"], "marker": "<!-- olive-pr-specialist-review:v1 -->"},
    "classifier": {
        "backend": "off",
        "band_low": 0.3,
        "band_high": 0.9,
        "pane_lines": 60,
        "haiku_model": "haiku",
        "haiku_effort": "low",
        "opus_effort": "low",
        "jev_model": "typesafe/jev-1.14",
        "api_key_env": "OPENROUTER_API_KEY",
        "timeout_seconds": 60,
    },
    "orchestrator": {
        "rotate_at_percent": 35,
        "context_window_tokens": 1000000,
        "read_lines_max": 60,
        "report_lines_max": 40,
        "max_workers": 4,
    },
    "nudges": {"report": "write {report}", "routine": "continue", "blocked": "blocked {report}"},
}

LEDGER = {
    "_path": "/state/w1/run.json",
    "slug": "run",
    "orchestrator_pane": "w1:p1",
    "workers": [{"name": "run-a", "pane_id": "w1:p2", "status": "running", "prs": []}],
}

MIN = 60.0


def agent(status: str, session: str = "s-a") -> dict:
    return {"pane_id": "w1:p2", "agent_status": status, "agent_session": {"value": session}}


def orch(session: str = "s-orch") -> dict:
    return {"pane_id": "w1:p1", "agent_status": "idle", "agent_session": {"value": session}}


def obs(now: float, status: str | None = "working", report: ReportInfo | None = None, **kw) -> Observation:
    agents = {"w1:p1": orch()}
    if status is not None:
        agents["w1:p2"] = agent(status)
    return Observation(now=now, agents=agents, reports={"run-a": report}, **kw)


class Harness:
    """Runs the engine the way the watch loop does, persisting state as JSON."""

    def __init__(self, cfg: dict | None = None, ledger: dict | None = None):
        self.cfg = cfg or copy.deepcopy(CONFIG)
        self.ledger = ledger or copy.deepcopy(LEDGER)
        self.state: dict = {}

    def step(self, observation: Observation) -> list:
        engine = herdr_orch.Engine(self.cfg, self.ledger, self.state)
        actions = engine.step(observation)
        self.state = json.loads(json.dumps(self.state))  # Survive a restart.
        return actions

    def texts(self, actions: list) -> list[str]:
        return [f"{a.kind}:{a.text}" for a in actions]


class ConfigTests(unittest.TestCase):
    def test_accepts_defaults(self) -> None:
        herdr_orch.validate_config(copy.deepcopy(CONFIG))

    def test_rejects_bad_values(self) -> None:
        cases = {
            "unknown model": lambda c: c["tiers"]["opus"].update(model="gpt-5"),
            "unknown effort": lambda c: c["tiers"]["opus"].update(effort="huge"),
            "missing tier": lambda c: c["workers"].update(implementer_tier="nope"),
            "band inverted": lambda c: c["classifier"].update(band_low=0.9, band_high=0.3),
            "band equal": lambda c: c["classifier"].update(band_low=0.5, band_high=0.5),
            "bad backend": lambda c: c["classifier"].update(backend="gpt"),
            "short fallback": lambda c: c["watcher"].update(fallback_check_minutes=10),
        }
        for name, mutate in cases.items():
            with self.subTest(name):
                cfg = copy.deepcopy(CONFIG)
                mutate(cfg)
                with self.assertRaises(herdr_orch.ConfigError):
                    herdr_orch.validate_config(cfg)

    def test_full_model_ids_are_allowed(self) -> None:
        cfg = copy.deepcopy(CONFIG)
        cfg["tiers"]["opus"]["model"] = "claude-opus-5-5[1m]"
        herdr_orch.validate_config(cfg)

    @unittest.skipUnless(os.environ.get("HERDR_ORCH_RENDERED_CONFIG"), "set by the flake check")
    def test_rendered_config_is_valid(self) -> None:
        cfg = herdr_orch.load_config(Path(os.environ["HERDR_ORCH_RENDERED_CONFIG"]))
        self.assertEqual(cfg["classifier"]["backend"], "off")
        self.assertTrue(cfg["olive"]["enable"])
        self.assertIn("Portal-Wholesale/cms", cfg["olive"]["repos"])


class ReportTests(unittest.TestCase):
    def test_parses_status_and_prs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "run-a.report.md"
            path.write_text(
                "status: done\nsummary: ported\npr: https://github.com/o/r/pull/12\n"
                "tests:\n- mix test: pass\n"
            )
            info = herdr_orch.read_report(path)
            self.assertEqual(info.status, "DONE")
            self.assertEqual(info.prs, ["https://github.com/o/r/pull/12"])
            self.assertIsNone(herdr_orch.read_report(Path(tmp) / "missing.md"))

    def test_unknown_status(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "r.md"
            path.write_text("summary: no status line\n")
            self.assertEqual(herdr_orch.read_report(path).status, "UNKNOWN")


def report(sig: str = "r1", mtime: float = 0.0, prs: list[str] | None = None, status: str = "DONE") -> ReportInfo:
    return ReportInfo(sig=sig, mtime=mtime, status=status, prs=prs or [])


class EngineTests(unittest.TestCase):
    def test_first_observation_is_silent(self) -> None:
        h = Harness()
        self.assertEqual(h.step(obs(0)), [])

    def test_unannounced_report_notifies_once_after_grace_and_survives_restart(self) -> None:
        h = Harness()
        h.step(obs(0))
        self.assertEqual(h.step(obs(30, report=report(mtime=20))), [])  # Inside the grace period.
        actions = h.step(obs(150, report=report(mtime=20)))
        self.assertEqual(
            h.texts(actions),
            ["notify:[watch] run-a REPORT status=DONE report=/state/w1/run/run-a.report.md (worker did not notify)"],
        )
        self.assertEqual(h.step(obs(180, report=report(mtime=20))), [])
        restarted = Harness(h.cfg, h.ledger)
        restarted.state = h.state
        self.assertEqual(restarted.step(obs(210, report=report(mtime=20))), [])

    def test_report_the_worker_announced_stays_quiet(self) -> None:
        h = Harness()
        h.step(obs(0))
        mentions = {"run-a": 22.0}
        self.assertEqual(h.step(obs(30, report=report(mtime=20), mentions=mentions)), [])
        self.assertEqual(h.step(obs(500, report=report(mtime=20), mentions=mentions)), [])

    def test_older_mention_does_not_cover_a_new_report(self) -> None:
        h = Harness()
        h.step(obs(0))
        actions = h.step(obs(400, report=report(mtime=200), mentions={"run-a": 50.0}))
        self.assertEqual(len(actions), 1)

    def test_changed_report_notifies_again(self) -> None:
        h = Harness()
        h.step(obs(0, report=report("r1")))
        h.step(obs(130, report=report("r1")))
        self.assertEqual(len(h.step(obs(400, report=report("r2", mtime=250)))), 1)

    def test_status_flicker_inside_debounce_is_ignored(self) -> None:
        h = Harness()
        h.step(obs(0, "working"))
        h.step(obs(10, "blocked"))
        h.step(obs(40, "working"))
        self.assertEqual(h.state["workers"]["run-a"]["status"], "working")
        self.assertEqual(h.step(obs(200, "working")), [])

    def test_blocked_notifies_once_per_episode(self) -> None:
        h = Harness()
        h.step(obs(0, "working"))
        h.step(obs(10, "blocked"))
        first = h.step(obs(80, "blocked"))
        self.assertEqual(h.texts(first), ["notify:[watch] run-a BLOCKED (waiting on a prompt)"])
        self.assertEqual(h.step(obs(110, "blocked")), [])
        h.step(obs(120, "working"))
        h.step(obs(190, "working"))
        h.step(obs(200, "blocked"))
        self.assertEqual(len(h.step(obs(270, "blocked"))), 1)

    def test_idle_without_report_nudges_then_escalates(self) -> None:
        h = Harness()
        h.step(obs(0, "working"))
        h.step(obs(100, "idle"))
        h.step(obs(170, "idle"))  # Confirmed idle since t=100.
        self.assertEqual(h.step(obs(100 + 9 * MIN, "idle")), [])
        nudge = h.step(obs(100 + 10 * MIN, "idle"))
        self.assertEqual(h.texts(nudge), ["nudge:write /state/w1/run/run-a.report.md"])
        self.assertEqual(h.step(obs(100 + 15 * MIN, "idle")), [])
        escalate = h.step(obs(100 + 21 * MIN, "idle"))
        self.assertEqual(len(escalate), 1)
        self.assertIn("IDLE_NO_REPORT", escalate[0].text)
        self.assertEqual(h.step(obs(100 + 40 * MIN, "idle")), [])

    def test_idle_with_fresh_report_is_quiet(self) -> None:
        h = Harness()
        h.step(obs(0, "working"))
        announced = {"run-a": 95.0}
        h.step(obs(100, "idle", report=report(mtime=90), mentions=announced))
        h.step(obs(170, "idle", report=report(mtime=90), mentions=announced))
        self.assertEqual(h.step(obs(100 + 30 * MIN, "idle", report=report(mtime=90), mentions=announced)), [])

    def test_stale_report_from_earlier_round_does_not_count(self) -> None:
        h = Harness()
        h.step(obs(0, "idle", report=report(mtime=0)))
        h.step(obs(100, "working", report=report(mtime=0)))
        h.step(obs(170, "working", report=report(mtime=0)))
        h.step(obs(200, "idle", report=report(mtime=0)))
        h.step(obs(270, "idle", report=report(mtime=0)))
        actions = h.step(obs(200 + 11 * MIN, "idle", report=report(mtime=0)))
        self.assertEqual([a.kind for a in actions], ["nudge"])

    def test_gone_notifies_once_after_debounce(self) -> None:
        h = Harness()
        h.step(obs(0, "working"))
        self.assertEqual(h.step(obs(30, None)), [])
        gone = h.step(obs(95, None))
        self.assertEqual(len(gone), 1)
        self.assertIn("GONE", gone[0].text)
        self.assertEqual(h.step(obs(200, None)), [])

    def test_stall_on_unchanged_output(self) -> None:
        h = Harness()
        h.step(obs(0, "working", pane_sigs={"run-a": "x"}))
        h.step(obs(10 * MIN, "working", pane_sigs={"run-a": "x"}))
        stalled = h.step(obs(21 * MIN, "working", pane_sigs={"run-a": "x"}))
        self.assertEqual(len(stalled), 1)
        self.assertIn("STALLED", stalled[0].text)
        self.assertEqual(h.step(obs(30 * MIN, "working", pane_sigs={"run-a": "x"})), [])

    def test_changing_output_is_not_a_stall(self) -> None:
        h = Harness()
        for i in range(10):
            self.assertEqual(h.step(obs(i * 5 * MIN, "working", pane_sigs={"run-a": str(i)})), [])

    def test_ignores_workers_not_running(self) -> None:
        ledger = copy.deepcopy(LEDGER)
        ledger["workers"][0]["status"] = "done"
        h = Harness(ledger=ledger)
        h.step(obs(0, None))
        self.assertEqual(h.step(obs(500, None)), [])

    def test_pr_transitions(self) -> None:
        url = "https://github.com/o/r/pull/1"
        h = Harness()
        r = report(prs=[url])
        h.step(obs(0, report=r))

        def pr(checks: str, merge: str = "MERGEABLE", state: str = "OPEN") -> list:
            return h.step(obs(100, report=r, prs={url: PrInfo(state, checks, merge)}))

        self.assertEqual(pr("pending"), [])
        self.assertIn("checks=fail", pr("fail")[0].text)
        self.assertEqual(pr("fail"), [])
        self.assertEqual(pr("pending"), [])
        self.assertIn("checks=pass", pr("pass")[0].text)
        self.assertIn("merge=CONFLICTING", pr("pass", "CONFLICTING")[0].text)
        self.assertIn("state=MERGED", pr("pass", "MERGEABLE", "MERGED")[0].text)

    def test_rotate_once_per_orchestrator_session(self) -> None:
        h = Harness()
        self.assertEqual(h.step(obs(0, orchestrator_ctx_pct=20.0)), [])
        rotate = h.step(obs(30, orchestrator_ctx_pct=36.0))
        self.assertIn("ROTATE ctx=36%", rotate[0].text)
        self.assertEqual(h.step(obs(60, orchestrator_ctx_pct=40.0)), [])

    def test_records_sessions(self) -> None:
        h = Harness()
        h.step(obs(0))
        self.assertEqual(h.state["sessions"], {"run-a": ["s-a"], "orchestrator": ["s-orch"]})

    def test_forget_allows_redelivery(self) -> None:
        h = Harness()
        h.step(obs(0))
        actions = h.step(obs(150, report=report(mtime=20)))
        self.assertEqual(h.step(obs(165, report=report(mtime=20))), [])
        herdr_orch.Engine(h.cfg, h.ledger, h.state).forget(actions[0].key)
        self.assertEqual(h.texts(h.step(obs(180, report=report(mtime=20)))), h.texts(actions))
        self.assertEqual(h.step(obs(210, report=report(mtime=20))), [])

    def test_forgotten_pr_event_is_redelivered(self) -> None:
        url = "https://github.com/o/r/pull/1"
        h = Harness()
        r = report(prs=[url])
        h.step(obs(0, report=r))
        fail = {url: PrInfo("OPEN", "fail", "MERGEABLE")}
        actions = h.step(obs(100, report=r, prs=fail))
        herdr_orch.Engine(h.cfg, h.ledger, h.state).forget(actions[0].key)
        self.assertEqual(len(h.step(obs(400, report=r, prs=fail))), 1)


class ClassifierRoutingTests(unittest.TestCase):
    def setUp(self) -> None:
        cfg = copy.deepcopy(CONFIG)
        cfg["classifier"]["backend"] = "haiku"
        cfg["watcher"]["max_nudges"] = 2
        self.h = Harness(cfg)
        self.h.step(obs(0, "working"))
        self.h.step(obs(10, "blocked"))
        actions = self.h.step(obs(80, "blocked"))
        self.assertEqual([a.kind for a in actions], ["classify"])
        self.action = actions[0]

    def classified(self, label: str, confidence: float) -> list:
        engine = herdr_orch.Engine(self.h.cfg, self.h.ledger, self.h.state)
        result = Classification(label, confidence, "haiku", "claude-haiku", 1.0)
        return engine.on_classified(self.action, result, 90)

    def test_confident_routine_question_is_nudged(self) -> None:
        self.assertEqual(self.h.texts(self.classified("routine_question", 0.95)), ["nudge:continue"])

    def test_unsure_band_escalates(self) -> None:
        actions = self.classified("routine_question", 0.6)
        self.assertEqual([a.kind for a in actions], ["notify"])
        self.assertIn("unsure label=routine_question conf=0.60", actions[0].text)

    def test_below_band_trusts_cheap_label(self) -> None:
        self.assertEqual([a.kind for a in self.classified("stuck", 0.2)], ["nudge"])

    def test_real_question_always_escalates(self) -> None:
        actions = self.classified("real_question", 0.99)
        self.assertEqual([a.kind for a in actions], ["notify"])

    def test_classifier_failure_escalates(self) -> None:
        engine = herdr_orch.Engine(self.h.cfg, self.h.ledger, self.h.state)
        actions = engine.on_classified(self.action, None, 90)
        self.assertIn("classifier failed", actions[0].text)

    def test_nudges_run_out(self) -> None:
        self.classified("stuck", 0.95)
        self.action.key += ":again"
        self.classified("stuck", 0.95)
        self.action.key += ":third"
        self.assertEqual([a.kind for a in self.classified("stuck", 0.95)], ["notify"])


class HelperTests(unittest.TestCase):
    def test_rollup_checks(self) -> None:
        def run(status: str, conclusion: str) -> dict:
            return {"__typename": "CheckRun", "status": status, "conclusion": conclusion}

        def ctx(state: str) -> dict:
            return {"__typename": "StatusContext", "state": state}

        self.assertEqual(herdr_orch.rollup_checks([]), "none")
        self.assertEqual(herdr_orch.rollup_checks([run("COMPLETED", "SUCCESS"), ctx("SUCCESS")]), "pass")
        self.assertEqual(herdr_orch.rollup_checks([run("IN_PROGRESS", ""), run("COMPLETED", "SUCCESS")]), "pending")
        self.assertEqual(herdr_orch.rollup_checks([run("IN_PROGRESS", ""), run("COMPLETED", "FAILURE")]), "fail")
        self.assertEqual(herdr_orch.rollup_checks([ctx("PENDING")]), "pending")
        self.assertEqual(herdr_orch.rollup_checks([run("COMPLETED", "SKIPPED")]), "pass")

    def test_pane_signature_ignores_timers(self) -> None:
        a = "Running tests\n✻ Thinking… (3m 12s · ↓ 4.1k tokens)\n"
        b = "Running tests\n✶ Thinking… (3m 48s · ↓ 4.9k tokens)\n"
        self.assertEqual(herdr_orch.pane_signature(a), herdr_orch.pane_signature(b))
        self.assertNotEqual(herdr_orch.pane_signature(a), herdr_orch.pane_signature("Tests passed\n"))

    def test_redact(self) -> None:
        text = "mail bob@example.com key sk-ant-abcdefghijklmnopqrstu token=abcdefgh12345678 at 10.0.0.12"
        out = herdr_orch.redact(text)
        for secret in ("bob@example.com", "sk-ant-abcdefghijklmnopqrstu", "abcdefgh12345678", "10.0.0.12"):
            self.assertNotIn(secret, out)

    def test_orchestrator_view(self) -> None:
        records = [
            {"type": "user", "timestamp": "2026-11-06T10:00:00Z", "message": {"content": "[run-a] DONE: ported"}},
            {"type": "user", "timestamp": "2026-11-06T10:05:00Z", "message": {"content": "[watch] run-b STALLED"}},
            {"type": "assistant", "message": {"id": "m", "model": "claude-opus-5-5", "usage": {
                "input_tokens": 1, "cache_creation_input_tokens": 9, "cache_read_input_tokens": 90, "output_tokens": 4}}},
        ]
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "proj"
            project.mkdir()
            (project / "sess.jsonl").write_text("\n".join(json.dumps(r) for r in records) + "\n")
            saved = herdr_orch.CLAUDE_PROJECTS
            herdr_orch.CLAUDE_PROJECTS = Path(tmp)
            try:
                ctx, mentions = herdr_orch.orchestrator_view("sess", 1000, ["run-a", "run-b"])
            finally:
                herdr_orch.CLAUDE_PROJECTS = saved
        self.assertEqual(ctx, 10.0)
        self.assertEqual(set(mentions), {"run-a"})

    def test_transcript_usage_counts_each_message_once(self) -> None:
        usage = {"input_tokens": 3, "cache_creation_input_tokens": 10, "cache_read_input_tokens": 100, "output_tokens": 5}
        records = [
            {"type": "assistant", "message": {"id": "m1", "model": "claude-sonnet-5-5", "usage": usage}},
            {"type": "assistant", "message": {"id": "m1", "model": "claude-sonnet-5-5", "usage": usage}},
            {"type": "assistant", "message": {"id": "m2", "model": "claude-opus-5-5", "usage": usage}},
            {"type": "assistant", "message": {"id": "m3", "model": "<synthetic>", "usage": usage}},
            {"type": "user", "message": {"content": "hi"}},
        ]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "s.jsonl"
            path.write_text("\n".join(json.dumps(r) for r in records) + "\nnot json\n")
            totals = herdr_orch.transcript_usage([path])
        self.assertEqual(totals["claude-sonnet-5-5"], {"input": 3, "cache_write": 10, "cache_read": 100, "output": 5, "turns": 1})
        self.assertEqual(set(totals), {"claude-sonnet-5-5", "claude-opus-5-5"})

    def test_cascade(self) -> None:
        rows = [{"id": str(i), "label": "working"} for i in range(4)]
        cheap = {
            "0": {"label": "working", "confidence": 0.95, "cost_usd": 0.001},
            "1": {"label": "stuck", "confidence": 0.5, "cost_usd": 0.001},
            "2": {"label": "stuck", "confidence": 0.1, "cost_usd": 0.001},
            "3": {"label": "working", "confidence": 0.8, "cost_usd": 0.001},
        }
        opus = {str(i): {"label": "working", "confidence": 0.9, "cost_usd": 0.01} for i in range(4)}
        result = herdr_orch.cascade(rows, cheap, opus, 0.3, 0.9)
        self.assertEqual(result["escalated"], 0.5)
        self.assertEqual(result["accuracy"], 0.75)
        self.assertAlmostEqual(result["cost_per_1k"], 1000 * (0.004 + 0.02) / 4)


if __name__ == "__main__":
    unittest.main()


OLIVE_BODY = """<!-- olive-pr-specialist-review:v1 -->

## Olive PR review

**Open · {done}/4 specialist reports available**

Reviewed revision: [`{rev}`](https://github.com/o/r/commit/{rev}) · base at review [`0b9612ee545c`](https://github.com/o/r/commit/0b96)

### Database

> Summary paragraph.
>
> ### M1 (Medium): not a section heading, it is quoted

**Blocking**

> - Bound the keyword arguments (&gt;20 keywords).

<details>
<summary>Architecture</summary>

> - Not blocking: a bullet inside the details block.

</details>

### React

**Blocking**

> - F1: is_saved is hard-coded
>   to false for signed-in viewers.
> - F2: sequential await inside Promise.all.

### Tests

> No blocking test findings at this head.
"""

HEAD = "e1ff79dd9cbe0e52364e61845b9dc889c6c0a85f"
URL = "https://github.com/o/r/pull/1"


def olive(done: int = 4, rev: str = HEAD[:12]):
    return herdr_orch.parse_olive(OLIVE_BODY.format(done=done, rev=rev), "https://github.com/o/r/pull/1#c1")


class OliveTests(unittest.TestCase):
    def test_parses_revision_progress_and_blocking_items(self) -> None:
        info = olive()
        self.assertEqual((info.revision, info.done, info.total), (HEAD[:12], 4, 4))
        self.assertTrue(info.complete and info.covers(HEAD))
        specialists = [s for s, _ in info.blocking]
        self.assertEqual(specialists, ["Database", "React", "React"])
        self.assertIn("F1: is_saved is hard-coded to false for signed-in viewers.", [t for _, t in info.blocking])
        self.assertNotIn("Tests", specialists)
        self.assertEqual(info.blocking[0][1], "Bound the keyword arguments (>20 keywords).")

    def test_gate(self) -> None:
        cfg = copy.deepcopy(CONFIG)
        self.assertEqual(herdr_orch.olive_gate(cfg, URL, HEAD, None)["gate"], "WAITING_REVIEW")
        self.assertEqual(herdr_orch.olive_gate(cfg, URL, HEAD, olive(done=1))["gate"], "WAITING_REVIEW")
        stale = herdr_orch.olive_gate(cfg, URL, HEAD, olive(rev="71d3aa7737a8"))
        self.assertEqual((stale["gate"], stale["blocking"]), ("WAITING_REVIEW", []))
        done = herdr_orch.olive_gate(cfg, URL, HEAD, olive())
        self.assertEqual(done["gate"], "TRIAGE")
        self.assertEqual(len(done["blocking"]), 3)
        other = herdr_orch.olive_gate(cfg, "https://github.com/x/y/pull/2", HEAD, None)
        self.assertEqual(other["gate"], "NOT_CONFIGURED")

    def test_event_once_when_complete_on_current_head(self) -> None:
        h = Harness()
        r = report(prs=[URL])
        h.step(obs(0, report=r))
        pending = {URL: PrInfo("OPEN", "pending", "MERGEABLE", HEAD)}
        self.assertEqual(h.step(obs(100, report=r, prs=pending, olive={URL: olive(done=2)})), [])
        self.assertEqual(h.step(obs(400, report=r, prs=pending, olive={URL: olive(rev="71d3aa7737a8")})), [])
        actions = h.step(obs(700, report=r, prs=pending, olive={URL: olive()}))
        self.assertEqual(len(actions), 1)
        self.assertIn(f"OLIVE {URL} head={HEAD[:12]} reports=4/4 blocking=", actions[0].text)
        self.assertEqual((actions[0].pr, actions[0].head), (URL, HEAD))
        self.assertEqual(h.step(obs(1000, report=r, prs=pending, olive={URL: olive()})), [])


class HeadTests(unittest.TestCase):
    def test_pr_events_carry_the_head(self) -> None:
        h = Harness()
        r = report(prs=[URL])
        h.step(obs(0, report=r))
        actions = h.step(obs(100, report=r, prs={URL: PrInfo("OPEN", "fail", "MERGEABLE", HEAD)}))
        self.assertIn(f"head={HEAD[:12]} state=OPEN checks=fail", actions[0].text)

    def test_new_head_with_same_result_notifies_again(self) -> None:
        h = Harness()
        r = report(prs=[URL])
        h.step(obs(0, report=r))
        self.assertEqual(len(h.step(obs(100, report=r, prs={URL: PrInfo("OPEN", "pass", "MERGEABLE", "a" * 40)}))), 1)
        self.assertEqual(len(h.step(obs(400, report=r, prs={URL: PrInfo("OPEN", "pass", "MERGEABLE", "b" * 40)}))), 1)

    def test_drop_stale(self) -> None:
        old = herdr_orch.Action("notify", "run-a", "PR old", pr=URL, head="a" * 40)
        plain = herdr_orch.Action("notify", "run-a", "REPORT")
        self.assertEqual(herdr_orch.drop_stale([old, plain], lambda _: "b" * 40), [plain])
        self.assertEqual(herdr_orch.drop_stale([old], lambda _: "a" * 40), [old])

        def broken(_: str) -> str:
            raise OSError("gh down")

        self.assertEqual(herdr_orch.drop_stale([old], broken), [old])


class WaitingTests(unittest.TestCase):
    def test_waiting_report_is_neither_announced_nor_nudged(self) -> None:
        h = Harness()
        h.step(obs(0))
        waiting = report(mtime=20, status="WAITING_CI")
        self.assertEqual(h.step(obs(30, "idle", report=waiting)), [])
        for t in (200, 1000, 3000, 6000):
            self.assertEqual(h.step(obs(t, "idle", report=waiting)), [], t)

    def test_long_wait_escalates_once(self) -> None:
        h = Harness()
        h.step(obs(0))
        waiting = report(mtime=20, status="WAITING_REVIEW")
        h.step(obs(30, "idle", report=waiting))
        actions = h.step(obs(20 + 121 * MIN, "idle", report=waiting))
        self.assertEqual(len(actions), 1)
        self.assertIn("WAITING_REVIEW for 121m (over 120m)", actions[0].text)
        self.assertEqual(h.step(obs(20 + 130 * MIN, "idle", report=waiting)), [])

    def test_resumed_work_is_watched_again(self) -> None:
        h = Harness()
        h.step(obs(0, "idle"))
        waiting = report(mtime=20, status="WAITING_CI")
        h.step(obs(30, "idle", report=waiting))
        h.step(obs(100, "working", report=waiting))
        h.step(obs(200, "working", report=waiting))  # Debounced: working since 100.
        h.step(obs(300, "idle", report=waiting))
        h.step(obs(400, "idle", report=waiting))  # Idle since 300.
        actions = h.step(obs(300 + 11 * MIN, "idle", report=waiting))
        self.assertEqual([a.kind for a in actions], ["nudge"])

    def test_report_statuses(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "r.md"
            path.write_text("status: WAITING_CI\nsummary: pushed, CI pending\n")
            self.assertEqual(herdr_orch.read_report(path).status, "WAITING_CI")
