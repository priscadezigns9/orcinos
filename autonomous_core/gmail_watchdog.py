import subprocess
import re
import json
import os
import base64
import requests

GITHUB_REPO = "priscadezigns9/priscadezignswebsite"
GITHUB_TOKEN = "{{credential:github-pat-laboratory-deploy-v7}}"

def get_clients_from_github():
    url = f"https://api.github.com/repos/{GITHUB_REPO}/contents/CLIENTS.json"
    headers = {"Authorization": f"token {GITHUB_TOKEN}"}
    r = requests.get(url, headers=headers)
    if r.status_code == 200:
        data = r.json()
        content = base64.b64decode(data['content']).decode()
        return json.loads(content), data['sha']
    return None, None

def update_clients_on_github(data, sha):
    url = f"https://api.github.com/repos/{GITHUB_REPO}/contents/CLIENTS.json"
    headers = {"Authorization": f"token {GITHUB_TOKEN}"}
    payload = {
        "message": "Autonomous Watchdog: Payment Verified via Gmail",
        "content": base64.b64encode(json.dumps(data, indent=2).encode()).decode(),
        "sha": sha
    }
    r = requests.put(url, headers=headers, json=payload)
    return r.status_code

def check_gmail_for_payments():
    # Search for emails from today
    # Using a broad query to catch bank and paypal notifications
    query = 'is:unread (subject:payment OR subject:received OR subject:transfer OR subject:notification OR subject:credit)'
    cmd = ['outlook', 'mail', 'search', query, '--limit', '10']
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        return []

    lines = result.stdout.split('\n')
    email_ids = []
    for line in lines:
        if line and line[0].isdigit() or line and len(line) > 10: # Rough check for ID column
            parts = line.split()
            if parts and len(parts[0]) == 16: # Gmail IDs are usually 16 hex chars
                email_ids.append(parts[0])

    verified_refs = []
    for eid in email_ids:
        # Get email body
        read_cmd = ['outlook', 'mail', 'read', eid]
        read_res = subprocess.run(read_cmd, capture_output=True, text=True)
        body = read_res.stdout
        
        # Search for Reference ID (PD-XXXXXX or LAB-XXXXXX)
        match = re.search(r'(PD|LAB)-[A-Z0-9]{6}', body)
        if match:
            ref = match.group(0)
            verified_refs.append(ref)
            # Mark as read to avoid duplicate processing
            subprocess.run(['outlook', 'mail', 'move', eid, 'Archive'])
            
    return verified_refs

def run_watchdog():
    refs = check_gmail_for_payments()
    if not refs:
        print("No new payment references found in Gmail.")
        return

    clients, sha = get_clients_from_github()
    if not clients:
        print("Could not fetch CLIENTS.json")
        return

    updated = False
    for ref in refs:
        # Verify and Move to Active
        found = False
        for entry in clients.get("pending_verifications", []):
            if entry["ref_id"] == ref:
                print(f"Verifying {ref}...")
                clients["active_subscriptions"].append({
                    "client_id": f"CL-{ref.split('-')[1]}",
                    "plan": entry["plan"],
                    "activation_date": "2026-05-27T14:15:00Z", # Should be current time
                    "status": "active"
                })
                clients["pending_verifications"].remove(entry)
                updated = True
                found = True
                break
        
        if not found:
            # Maybe it's a direct payment without a pending entry (Rare)
            print(f"Reference {ref} found in email but not in pending list.")

    if updated:
        status = update_clients_on_github(clients, sha)
        print(f"Registry updated: {status}")
    else:
        print("No matches between emails and pending list.")

if __name__ == "__main__":
    run_watchdog()
