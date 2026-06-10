import json
import os
import datetime

CLIENTS_FILE = "CLIENTS.json"

def register_pending_payment(ref_id, plan, price, bank="FCB"):
    """Called by the website (simulated via webhook) when a user opens the modal."""
    try:
        with open(CLIENTS_FILE, "r") as f:
            data = json.load(f)
    except FileNotFoundError:
        data = {"pending_verifications": [], "active_subscriptions": []}

    pending_entry = {
        "ref_id": ref_id,
        "plan": plan,
        "price": price,
        "bank": bank,
        "status": "waiting_for_funds",
        "timestamp": datetime.datetime.now().isoformat()
    }
    
    data["pending_verifications"].append(pending_entry)
    
    with open(CLIENTS_FILE, "w") as f:
        json.dump(data, f, indent=2)
    return f"Registered pending payment: {ref_id}"

def verify_bank_clearance(ref_id):
    """The 'Watchdog' function. In production, this would be triggered by a Bank API or Mail parse."""
    with open(CLIENTS_FILE, "r") as f:
        data = json.load(f)
    
    found = False
    for entry in data["pending_verifications"]:
        if entry["ref_id"] == ref_id:
            entry["status"] = "cleared"
            # Move to active
            data["active_subscriptions"].append({
                "client_id": f"CL-{ref_id.split('-')[1]}",
                "plan": entry["plan"],
                "activation_date": datetime.datetime.now().isoformat(),
                "status": "active"
            })
            data["pending_verifications"].remove(entry)
            found = True
            break
    
    if found:
        with open(CLIENTS_FILE, "w") as f:
            json.dump(data, f, indent=2)
        return f"Payment {ref_id} CLEARED. Client activated."
    else:
        return f"Reference {ref_id} not found in pending."

if __name__ == "__main__":
    # Example simulation
    print(register_pending_payment("PD-X9Z2Y1", "Rowcell Pro", "$149 USD"))
    print(verify_bank_clearance("PD-X9Z2Y1"))
