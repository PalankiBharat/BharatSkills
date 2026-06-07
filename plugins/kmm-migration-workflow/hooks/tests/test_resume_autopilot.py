import importlib.util, os
from pathlib import Path

HOOK = Path(__file__).resolve().parents[1] / "resume_session.py"
spec = importlib.util.spec_from_file_location("resume_session", HOOK)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)


def test_worker_banner_present_and_phase_matches(monkeypatch):
    monkeypatch.setenv("KMM_AUTOPILOT_ROLE", "worker")
    monkeypatch.setenv("KMM_AUTOPILOT_PHASE", "D")
    banner = mod.autopilot_banner(active_phase_id="D")
    assert "AUTOPILOT WORKER MODE" in banner
    assert "run only the active phase" in banner.lower()
    assert "decision-request" in banner
    assert "phase-D.status" in banner


def test_worker_phase_mismatch_warns(monkeypatch):
    monkeypatch.setenv("KMM_AUTOPILOT_ROLE", "worker")
    monkeypatch.setenv("KMM_AUTOPILOT_PHASE", "C")
    banner = mod.autopilot_banner(active_phase_id="D")
    assert "MISMATCH" in banner
    assert "phase-C.status" in banner          # mismatch path keys off KMM_AUTOPILOT_PHASE (want), not active
    assert "FAILED" in banner
    assert "decision-request" not in banner    # proves early return — normal worker instructions NOT appended


def test_worker_none_active_uses_env_phase(monkeypatch):
    monkeypatch.setenv("KMM_AUTOPILOT_ROLE", "worker")
    monkeypatch.setenv("KMM_AUTOPILOT_PHASE", "D")
    banner = mod.autopilot_banner(active_phase_id=None)
    assert "phase-D.status" in banner
    assert "phase-?.status" not in banner


def test_unknown_role_empty(monkeypatch):
    monkeypatch.setenv("KMM_AUTOPILOT_ROLE", "typo")
    assert mod.autopilot_banner(active_phase_id="B") == ""


def test_orchestrator_banner(monkeypatch):
    monkeypatch.setenv("KMM_AUTOPILOT_ROLE", "orchestrator")
    banner = mod.autopilot_banner(active_phase_id="B")
    assert "AUTOPILOT ORCHESTRATOR MODE" in banner
    assert "spawn" in banner.lower()


def test_no_banner_without_role(monkeypatch):
    monkeypatch.delenv("KMM_AUTOPILOT_ROLE", raising=False)
    assert mod.autopilot_banner(active_phase_id="B") == ""
