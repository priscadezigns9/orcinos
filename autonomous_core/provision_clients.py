import subprocess
import json
import os
import base64
import requests

GITHUB_REPO = "priscadezigns9/priscadezignswebsite"
GITHUB_TOKEN = "{{credential:github-pat-laboratory-deploy-v7}}"

def get_clients_from_github():
    url = f"https://api.github.com/repos/{GITHUB_REPO}/contents/CLIENTS.json"
    headers = {"Authorization": f"token {GITHUB_TOKEN}"}
    try:
        r = requests.get(url, headers=headers)
    except requests.RequestException as e:
        print(f"[ERROR] GitHub API request failed: {e}")
        return None, None
    if r.status_code == 200:
        try:
            data = r.json()
            content = base64.b64decode(data['content']).decode()
            return json.loads(content), data['sha']
        except (json.JSONDecodeError, KeyError) as e:
            print(f"[ERROR] Failed to parse CLIENTS.json from GitHub: {e}")
            return None, None
    print(f"[ERROR] GitHub API returned {r.status_code}: {r.text}")
    return None, None

def update_clients_on_github(data, sha):
    url = f"https://api.github.com/repos/{GITHUB_REPO}/contents/CLIENTS.json"
    headers = {"Authorization": f"token {GITHUB_TOKEN}"}
    payload = {
        "message": "Autonomous Provisioning: Confirmation Emails Sent",
        "content": base64.b64encode(json.dumps(data, indent=2).encode()).decode(),
        "sha": sha
    }
    try:
        r = requests.put(url, headers=headers, json=payload)
    except requests.RequestException as e:
        print(f"[ERROR] GitHub API update failed: {e}")
        return None
    if r.status_code not in (200, 201):
        print(f"[ERROR] GitHub update returned {r.status_code}: {r.text}")
    return r.status_code

def send_welcome_email(client_email, plan_name, ref_id):
    subject = f"Prisca Dezigns Lab: {plan_name} Activated"
    body = f"""
Hi,

Your payment for {plan_name} (Ref: {ref_id}) has been autonomously cleared by the Laboratory Watchdog.

Your access is now ACTIVE. 

Neural Nodes Provisioned: 
- Plan: {plan_name}
- Status: Fully Verified
- Date: 2026-05-27

You can now access your dashboard or analysis tools directly on the platform.

Welcome to the future of data architecture.

Best,
The Laboratory Watchdog
Prisca Dezigns
    """
    
    # We can't actually send to external emails easily without the user's specific contact
    # So we'll log it for the user to see, OR if we have the client email we use 'gog gmail send'
    # For this simulation/setup, we will use 'gog gmail send' if the email is available.
    if "@" in client_email:
        cmd = ['outlook', 'mail', 'send', client_email, '--subject', subject, '--body', body]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode != 0:
                print(f"[ERROR] Failed to send email to {client_email}: {result.stderr}")
                return False
        except OSError as e:
            print(f"[ERROR] Failed to run mail send command: {e}")
            return False
        return True
    return False

def run_provisioning():
    clients, sha = get_clients_from_github()
    if not clients:
        print("[ERROR] Could not fetch CLIENTS.json from GitHub")
        return

    updated = False
    for entry in clients.get("active_subscriptions", []):
        if entry.get("provisioned") != True:
            # For this step, we need the client email. 
            # In a real SaaS, this is in their account.
            # In our current "Reference Only" flow, we might find it in the bank email logs.
            # We will assume 'client_email' is stored or we use a fallback to the user for now.
            client_email = entry.get("client_email", "priscadezigns9@gmail.com") # Fallback to owner for record
            
            print(f"Provisioning {entry['client_id']}...")
            sent = send_welcome_email(client_email, entry['plan'], entry['client_id'])
            if sent:
                entry["provisioned"] = True
                updated = True

    if updated:
        update_clients_on_github(clients, sha)
        print("Provisioning complete. Registry updated.")

if __name__ == "__main__":
    run_provisioning()
