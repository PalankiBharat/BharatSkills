import importlib.util, os
from pathlib import Path

HOOK = Path(__file__).resolve().parents[1] / "resume_session.py"
spec = importlib.util.spec_from_file_location("resume_session", HOOK)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)

FOLDER = "/repo/.kmm/migrations/kmm/funds-x"


def test_worker_banner_present_and_phase_matches(monkeypatch):
    monkeypatch.delenv("KMM_ORCH_DIR", raising=False)
    monkeypatch.setenv("KMM_AUTOPILOT_ROLE", "worker")
    monkeypatch.setenv("KMM_AUTOPILOT_PHASE", "D")
    banner = mod.autopilot_banner(FOLDER, "D")
    assert "AUTOPILOT WORKER MODE" in banner
    assert "run only the active phase" in banner.lower()
    assert "decision-request" in banner
    assert f"{FOLDER}/orchestration/phase-D.status" in banner


def test_worker_uses_kmm_orch_dir_env(monkeypatch):
    monkeypatch.setenv("KMM_AUTOPILOT_ROLE", "worker")
    monkeypatch.setenv("KMM_AUTOPILOT_PHASE", "D")
    monkeypatch.setenv("KMM_ORCH_DIR", "/abs/orch")
    banner = mod.autopilot_banner("/ignored", "D")
    assert "/abs/orch/phase-D.status" in banner


def test_worker_phase_mismatch_warns(monkeypatch):
    monkeypatch.delenv("KMM_ORCH_DIR", raising=False)
    monkeypatch.setenv("KMM_AUTOPILOT_ROLE", "worker")
    monkeypatch.setenv("KMM_AUTOPILOT_PHASE", "C")
    banner = mod.autopilot_banner(FOLDER, "D")
    assert "MISMATCH" in banner
    assert f"{FOLDER}/orchestration/phase-C.status" in banner
    assert "FAILED" in banner
    assert "decision-request" not in banner


def test_worker_none_active_uses_env_phase(monkeypatch):
    monkeypatch.delenv("KMM_ORCH_DIR", raising=False)
    monkeypatch.setenv("KMM_AUTOPILOT_ROLE", "worker")
    monkeypatch.setenv("KMM_AUTOPILOT_PHASE", "D")
    banner = mod.autopilot_banner(FOLDER, None)
    assert f"{FOLDER}/orchestration/phase-D.status" in banner
    assert "phase-?.status" not in banner


def test_orchestrator_banner(monkeypatch):
    monkeypatch.setenv("KMM_AUTOPILOT_ROLE", "orchestrator")
    banner = mod.autopilot_banner(FOLDER, "B")
    assert "AUTOPILOT ORCHESTRATOR MODE" in banner
    assert "spawn" in banner.lower()


def test_no_banner_without_role(monkeypatch):
    monkeypatch.delenv("KMM_AUTOPILOT_ROLE", raising=False)
    assert mod.autopilot_banner(FOLDER, "B") == ""


def test_unknown_role_empty(monkeypatch):
    monkeypatch.setenv("KMM_AUTOPILOT_ROLE", "typo")
    assert mod.autopilot_banner(FOLDER, "B") == ""
