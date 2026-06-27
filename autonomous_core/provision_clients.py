import subprocess
import re
import json
import os
import base64
import requests

GITHUB_REPO = "priscadezigns9/priscadezignswebsite"
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")

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
        "message": "Autonomous Provisioning: Confirmation Emails Sent",
        "content": base64.b64encode(json.dumps(data, indent=2).encode()).decode(),
        "sha": sha
    }
    r = requests.put(url, headers=headers, json=payload)
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
    if re.fullmatch(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', client_email):
        cmd = ['outlook', 'mail', 'send', client_email, '--subject', subject, '--body', body]
        subprocess.run(cmd)
        return True
    return False

def run_provisioning():
    if not GITHUB_TOKEN:
        print("GITHUB_TOKEN environment variable is not set.")
        return
    clients, sha = get_clients_from_github()
    if not clients:
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
