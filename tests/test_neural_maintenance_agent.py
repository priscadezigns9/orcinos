import json
import os
import pytest
from unittest.mock import patch

from autonomous_core.neural_maintenance_agent import perform_neural_maintenance


@pytest.fixture(autouse=True)
def run_in_tmp(tmp_path, monkeypatch):
    """Run every test with cwd set to a temp directory."""
    monkeypatch.chdir(tmp_path)
    return tmp_path


class TestPerformNeuralMaintenance:
    def test_no_files_produces_no_output(self, capsys):
        perform_neural_maintenance()
        captured = capsys.readouterr()
        assert captured.out.strip() == ""

    def test_clients_json_verified(self, run_in_tmp, capsys):
        clients = {"pending_verifications": [], "active_subscriptions": []}
        (run_in_tmp / "CLIENTS.json").write_text(json.dumps(clients))

        perform_neural_maintenance()
        captured = capsys.readouterr()
        assert "Registry integrity verified" in captured.out

    def test_links_json_missing_brand_warns(self, run_in_tmp, capsys):
        links = {"brands": {"nonexistent_brand": {}}, "last_maintenance": ""}
        (run_in_tmp / "LINKS.json").write_text(json.dumps(links))

        perform_neural_maintenance()
        captured = capsys.readouterr()
        assert "Warning" in captured.out
        assert "nonexistent_brand" in captured.out

    def test_links_json_updates_last_maintenance(self, run_in_tmp):
        links = {"brands": {}, "last_maintenance": "old"}
        links_path = run_in_tmp / "LINKS.json"
        links_path.write_text(json.dumps(links))

        perform_neural_maintenance()

        updated = json.loads(links_path.read_text())
        assert updated["last_maintenance"] != "old"
        # Verify it's a valid ISO timestamp
        from datetime import datetime
        datetime.fromisoformat(updated["last_maintenance"])

    def test_existing_brand_dir_no_warning(self, run_in_tmp, capsys):
        brand_dir = run_in_tmp / "my_brand"
        brand_dir.mkdir()
        links = {"brands": {str(brand_dir): {}}, "last_maintenance": ""}
        (run_in_tmp / "LINKS.json").write_text(json.dumps(links))

        perform_neural_maintenance()
        captured = capsys.readouterr()
        assert "Warning" not in captured.out

    def test_both_files_present(self, run_in_tmp, capsys):
        clients = {"pending_verifications": [], "active_subscriptions": []}
        (run_in_tmp / "CLIENTS.json").write_text(json.dumps(clients))

        links = {"brands": {}, "last_maintenance": ""}
        (run_in_tmp / "LINKS.json").write_text(json.dumps(links))

        perform_neural_maintenance()
        captured = capsys.readouterr()
        assert "Registry integrity verified" in captured.out
