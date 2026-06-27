import json
import os
import tempfile
import pytest
from unittest.mock import patch

from autonomous_core.financial_watchdog import (
    register_pending_payment,
    verify_bank_clearance,
)


@pytest.fixture(autouse=True)
def tmp_clients_file(tmp_path, monkeypatch):
    """Redirect CLIENTS_FILE to a temp directory for every test."""
    clients_path = str(tmp_path / "CLIENTS.json")
    monkeypatch.setattr(
        "autonomous_core.financial_watchdog.CLIENTS_FILE", clients_path
    )
    return clients_path


class TestRegisterPendingPayment:
    def test_creates_file_when_missing(self, tmp_clients_file):
        result = register_pending_payment("PD-ABC123", "Pro Plan", "$99 USD")
        assert "PD-ABC123" in result

        with open(tmp_clients_file) as f:
            data = json.load(f)
        assert len(data["pending_verifications"]) == 1
        assert data["pending_verifications"][0]["ref_id"] == "PD-ABC123"
        assert data["pending_verifications"][0]["plan"] == "Pro Plan"
        assert data["pending_verifications"][0]["price"] == "$99 USD"
        assert data["pending_verifications"][0]["bank"] == "FCB"
        assert data["pending_verifications"][0]["status"] == "waiting_for_funds"

    def test_appends_to_existing_file(self, tmp_clients_file):
        seed = {
            "pending_verifications": [
                {"ref_id": "PD-EXIST1", "plan": "Basic", "price": "$49"}
            ],
            "active_subscriptions": [],
        }
        with open(tmp_clients_file, "w") as f:
            json.dump(seed, f)

        register_pending_payment("PD-NEW001", "Premium", "$199 USD")

        with open(tmp_clients_file) as f:
            data = json.load(f)
        assert len(data["pending_verifications"]) == 2
        refs = [e["ref_id"] for e in data["pending_verifications"]]
        assert "PD-EXIST1" in refs
        assert "PD-NEW001" in refs

    def test_custom_bank(self, tmp_clients_file):
        register_pending_payment("PD-BNK001", "Plan A", "$10", bank="CHASE")

        with open(tmp_clients_file) as f:
            data = json.load(f)
        assert data["pending_verifications"][0]["bank"] == "CHASE"

    def test_return_message_contains_ref_id(self, tmp_clients_file):
        result = register_pending_payment("PD-MSG123", "Plan B", "$50")
        assert "PD-MSG123" in result

    def test_timestamp_is_iso_format(self, tmp_clients_file):
        register_pending_payment("PD-TS0001", "Plan C", "$25")

        with open(tmp_clients_file) as f:
            data = json.load(f)
        ts = data["pending_verifications"][0]["timestamp"]
        # Should be parseable ISO format
        from datetime import datetime
        datetime.fromisoformat(ts)


class TestVerifyBankClearance:
    def _seed_pending(self, path, ref_id="PD-X9Z2Y1", plan="Pro"):
        data = {
            "pending_verifications": [
                {
                    "ref_id": ref_id,
                    "plan": plan,
                    "price": "$149 USD",
                    "bank": "FCB",
                    "status": "waiting_for_funds",
                }
            ],
            "active_subscriptions": [],
        }
        with open(path, "w") as f:
            json.dump(data, f)

    def test_clears_existing_payment(self, tmp_clients_file):
        self._seed_pending(tmp_clients_file)
        result = verify_bank_clearance("PD-X9Z2Y1")
        assert "CLEARED" in result

        with open(tmp_clients_file) as f:
            data = json.load(f)
        assert len(data["pending_verifications"]) == 0
        assert len(data["active_subscriptions"]) == 1
        assert data["active_subscriptions"][0]["status"] == "active"
        assert data["active_subscriptions"][0]["plan"] == "Pro"

    def test_client_id_derived_from_ref(self, tmp_clients_file):
        self._seed_pending(tmp_clients_file, ref_id="PD-ABCDEF")
        verify_bank_clearance("PD-ABCDEF")

        with open(tmp_clients_file) as f:
            data = json.load(f)
        assert data["active_subscriptions"][0]["client_id"] == "CL-ABCDEF"

    def test_not_found_returns_message(self, tmp_clients_file):
        self._seed_pending(tmp_clients_file)
        result = verify_bank_clearance("PD-NONEXIST")
        assert "not found" in result

        with open(tmp_clients_file) as f:
            data = json.load(f)
        assert len(data["pending_verifications"]) == 1
        assert len(data["active_subscriptions"]) == 0

    def test_multiple_pending_only_clears_matching(self, tmp_clients_file):
        data = {
            "pending_verifications": [
                {"ref_id": "PD-AAA111", "plan": "Basic", "price": "$49", "bank": "FCB", "status": "waiting_for_funds"},
                {"ref_id": "PD-BBB222", "plan": "Pro", "price": "$149", "bank": "FCB", "status": "waiting_for_funds"},
            ],
            "active_subscriptions": [],
        }
        with open(tmp_clients_file, "w") as f:
            json.dump(data, f)

        verify_bank_clearance("PD-BBB222")

        with open(tmp_clients_file) as f:
            data = json.load(f)
        assert len(data["pending_verifications"]) == 1
        assert data["pending_verifications"][0]["ref_id"] == "PD-AAA111"
        assert len(data["active_subscriptions"]) == 1
        assert data["active_subscriptions"][0]["plan"] == "Pro"
