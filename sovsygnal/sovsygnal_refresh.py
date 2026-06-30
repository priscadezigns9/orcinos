"""
SOVSYGNAL Hourly Refresh — Self-Running Script
Fetches live headlines from Reuters RSS and AP RSS,
rebuilds all 13 HTML pages, and commits them to GitHub.

Runs via GitHub Actions on schedule: every hour, 09:00–21:00 AST (13:00–01:00 UTC).
"""

import os
import re
import json
import base64
import datetime
import urllib.request
import xml.etree.ElementTree as ET

# ── CONFIG ────────────────────────────────────────────────────────────────────
OWNER  = "priscadezigns9"
REPO   = "orcinos"
SUBDIR = "sovsygnal"
TOKEN  = os.environ["GH_PAT"]

PAGES = [
    "index", "geopolitics", "stocks", "blockchain", "intelligence",
    "forex", "markets", "realestate", "anime", "gaming",
    "entertainment", "lifestyle", "biohacking"
]

# RSS sources — Reuters and AP public feeds
RSS_SOURCES = [
    ("reuters_world",    "https://feeds.reuters.com/reuters/worldNews"),
    ("reuters_business", "https://feeds.reuters.com/reuters/businessNews"),
    ("reuters_tech",     "https://feeds.reuters.com/reuters/technologyNews"),
    ("reuters_markets",  "https://feeds.reuters.com/reuters/marketsNews"),
    ("ap_world",         "https://feeds.apnews.com/apnews/world-news"),
    ("ap_us",            "https://feeds.apnews.com/apnews/us-news"),
    ("ap_tech",          "https://feeds.apnews.com/apnews/technology"),
    ("ap_business",      "https://feeds.apnews.com/apnews/business-news"),
]

# ── HELPERS ───────────────────────────────────────────────────────────────────

def fetch_rss(url):
    """Fetch and parse an RSS feed. Returns list of {title, link, desc, pubDate}."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "SovSignal/1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            xml_data = resp.read()
        root = ET.fromstring(xml_data)
        items = []
        for item in root.findall(".//item")[:8]:
            title = (item.findtext("title") or "").strip()
            link  = (item.findtext("link")  or "").strip()
            desc  = (item.findtext("description") or "").strip()
            pub   = (item.findtext("pubDate") or "").strip()
            # Strip HTML tags from description
            desc = re.sub(r"<[^>]+>", "", desc)[:300]
            if title and link:
                items.append({"title": title, "link": link, "desc": desc, "pub": pub})
        return items
    except Exception as e:
        print(f"  RSS fetch failed ({url}): {e}")
        return []


def gh_get_sha(path):
    """Get the current SHA for a file in the repo."""
    url = f"https://api.github.com/repos/{OWNER}/{REPO}/contents/{path}"
    req = urllib.request.Request(
        url,
        headers={"Authorization": f"token {TOKEN}", "User-Agent": "SovSignal/1.0"}
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
            return data.get("sha", "")
    except Exception:
        return ""


def gh_push(path, content_bytes, sha, message):
    """Push a file to GitHub via the Contents API."""
    url = f"https://api.github.com/repos/{OWNER}/{REPO}/contents/{path}"
    payload = {
        "message": message,
        "content": base64.b64encode(content_bytes).decode(),
    }
    if sha:
        payload["sha"] = sha
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        url, data=body, method="PUT",
        headers={
            "Authorization": f"token {TOKEN}",
            "Content-Type":  "application/json",
            "User-Agent":    "SovSignal/1.0",
        }
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            result = json.loads(resp.read())
            return "content" in result
    except urllib.error.HTTPError as e:
        body_err = e.read().decode()
        print(f"  Push error {e.code}: {body_err[:200]}")
        return False


# ── HTML TEMPLATES ────────────────────────────────────────────────────────────

STYLES = """<style>
:root{--primary:#8B0000;--bg:#f9f9f7;--card:#fff;--text:#1a1a1a}
*{margin:0;padding:0;box-sizing:border-box}
body{background:var(--bg);color:var(--text);font-family:'Inter',sans-serif;font-size:15px;line-height:1.6}
header{background:#000;color:#fff;padding:18px 28px;display:flex;align-items:center;gap:20px;flex-wrap:wrap;position:sticky;top:0;z-index:100}
header h1{font-family:'Playfair Display',serif;font-size:1.6rem;letter-spacing:2px}
header h1 a{color:#fff;text-decoration:none}
header p{font-size:.72rem;opacity:.6;letter-spacing:1px}
nav{display:flex;gap:4px;flex-wrap:wrap;margin-left:auto}
nav a{color:#ccc;text-decoration:none;font-size:.74rem;padding:5px 10px;border-radius:3px;transition:.2s;font-weight:600;letter-spacing:.5px}
nav a:hover,nav a.active{background:#8B0000;color:#fff}
.hamburger{display:none;cursor:pointer;flex-direction:column;gap:5px;margin-left:auto}
.hamburger div{width:24px;height:2px;background:#fff}
.ticker-wrap{background:#111;overflow:hidden;padding:8px 0;border-bottom:1px solid #333}
.ticker{display:flex;animation:ticker 70s linear infinite;white-space:nowrap}
.ticker-item{color:#ccc;font-size:.7rem;padding:0 40px;letter-spacing:.5px}
.ticker-item span{color:#8B0000;margin-right:8px}
@keyframes ticker{0%{transform:translateX(0)}100%{transform:translateX(-50%)}}
.container{max-width:1200px;margin:0 auto;padding:32px 20px;display:grid;grid-template-columns:1fr 280px;gap:32px}
main{min-width:0}
.section-label{font-size:.65rem;font-weight:800;text-transform:uppercase;letter-spacing:3px;color:var(--primary);border-bottom:2px solid var(--primary);padding-bottom:8px;margin-bottom:24px}
.news-grid{display:grid;gap:20px}
.news-card{background:var(--card);border:1px solid #e8e8e8;padding:22px;border-radius:6px;transition:box-shadow .2s}
.news-card:hover{box-shadow:0 4px 20px rgba(0,0,0,.08)}
.news-card h2{font-family:'Playfair Display',serif;font-size:1.1rem;line-height:1.4;margin-bottom:8px}
.news-card h2 a{color:var(--text);text-decoration:none}
.news-card h2 a:hover{color:var(--primary)}
aside{position:sticky;top:80px;align-self:start}
footer{background:#000;color:#666;text-align:center;padding:28px;font-size:.75rem;letter-spacing:1px}
@media(max-width:768px){
.container{grid-template-columns:1fr}
nav{display:none;position:absolute;top:100%;left:0;right:0;background:#fff;flex-direction:column;align-items:center;padding:20px;border-bottom:2px solid #000;z-index:999}
nav.active{display:flex}
nav a{font-size:.9rem;padding:12px 20px;width:80%;text-align:center;border:1px solid #eee;color:#000}
.hamburger{display:flex}
aside{order:2;width:100%}}
</style>"""

SCRIPT = """<script>
const h=document.getElementById('hamburger'),n=document.getElementById('main-nav');
if(h&&n)h.addEventListener('click',()=>n.classList.toggle('active'));
</script>"""

SIDEBAR = """<aside>
<div style="background:#000;color:#fff;padding:22px;border-radius:8px;margin-bottom:18px">
<div style="font-size:.58rem;font-weight:800;text-transform:uppercase;letter-spacing:2px;opacity:.7;margin-bottom:6px">Featured Brand</div>
<h4 style="font-family:'Playfair Display',serif;font-size:1.1rem;margin-bottom:4px">PRISCION</h4>
<p style="font-size:.78rem;opacity:.8;margin-bottom:14px">AI Intelligence Network</p>
<a href="https://orcinos.com/" target="_blank" style="display:inline-block;background:#8B0000;color:#fff;padding:8px 16px;border-radius:4px;font-size:.75rem;font-weight:700;text-decoration:none;text-transform:uppercase;letter-spacing:1px">Visit &rarr;</a>
</div>
<div style="background:#fff;border:1px solid #e8e8e8;padding:22px;border-radius:8px;margin-bottom:18px">
<div style="font-size:.58rem;font-weight:800;text-transform:uppercase;letter-spacing:2px;color:#8B0000;margin-bottom:8px">Recommended</div>
<h4 style="font-size:1rem;margin-bottom:10px;font-family:'Playfair Display',serif">Premium Tech Bundle</h4>
<a href="https://www.amazon.com/s?k=smart+home+bundle&tag=priscadezigns-20" target="_blank" style="display:inline-block;background:#FF9900;color:#000;padding:8px 16px;border-radius:4px;font-size:.75rem;font-weight:700;text-decoration:none">Shop on Amazon &rarr;</a>
</div>
<div style="background:linear-gradient(135deg,#8B0000,#000);color:#fff;padding:22px;border-radius:8px;text-align:center">
<div style="font-size:.58rem;font-weight:800;text-transform:uppercase;letter-spacing:2px;opacity:.7;margin-bottom:8px">Advertise Here</div>
<p style="font-size:.8rem;opacity:.85;margin-bottom:14px">Reach a high-fidelity intelligence audience</p>
<a href="advertise.html" style="display:inline-block;background:#fff;color:#8B0000;padding:8px 16px;border-radius:4px;font-size:.75rem;font-weight:700;text-decoration:none;text-transform:uppercase;letter-spacing:1px">Get Started &rarr;</a>
</div>
</aside>"""

NAV_PAGES = [
    ("index.html","Headlines"),("geopolitics.html","Geopolitics"),("stocks.html","Stocks"),
    ("blockchain.html","Blockchain"),("intelligence.html","Intelligence"),("forex.html","Forex"),
    ("markets.html","Markets"),("realestate.html","Real Estate"),("anime.html","Anime"),
    ("gaming.html","Gaming"),("entertainment.html","Entertainment"),("lifestyle.html","Lifestyle"),
    ("biohacking.html","Biohacking"),("advertise.html","Advertise"),
]

# Keyword routing: which RSS items belong on which page
PAGE_KEYWORDS = {
    "index":         ["breaking","world","us","top","latest"],
    "geopolitics":   ["war","nato","military","ukraine","russia","israel","iran","china","taiwan","sanction","diplomacy","conflict","attack","troops","terror","geopolit"],
    "stocks":        ["stock","equit","s&p","nasdaq","dow","nyse","share","ipo","earning","wall street","invest","bull","bear","market rally","fund"],
    "blockchain":    ["bitcoin","crypto","ethereum","blockchain","defi","nft","web3","token","coin","binance","solana","cardano","ada","btc","eth"],
    "intelligence":  ["ai","artificial intelligence","cybersecurity","hack","data breach","surveillance","intel","spy","algorithm","machine learning","openai","tech giant"],
    "forex":         ["dollar","euro","yen","pound","currency","forex","exchange rate","fed","central bank","interest rate","inflation","monetary","ecb","boj"],
    "markets":       ["oil","gold","silver","copper","commodity","brent","crude","futures","energy","gas","metal","raw material","trade"],
    "realestate":    ["real estate","property","housing","mortgage","rent","luxury home","commercial property","reit","construction","building"],
    "anime":         ["anime","manga","crunchyroll","studio","ghibli","shonen","seinen","otaku","vtuber","hololive","nintendo","pokemon"],
    "gaming":        ["gaming","game","console","playstation","xbox","nintendo","esport","steam","pc game","mobile game","video game","fps","rpg"],
    "entertainment": ["movie","film","music","celebrity","award","oscar","grammy","netflix","streaming","tv show","concert","album","box office","hollywood","disney"],
    "lifestyle":     ["luxury","fashion","travel","wellness","lifestyle","resort","hotel","restaurant","design","home","watch","jewel","style"],
    "biohacking":    ["health","biohack","longevity","fitness","supplement","sleep","nutrition","workout","wellness tech","wearable","biomarker","gut","hormone"],
}


def score_item(item, page):
    """Score how relevant an RSS item is to a given page."""
    text = (item["title"] + " " + item["desc"]).lower()
    keywords = PAGE_KEYWORDS.get(page, [])
    return sum(1 for kw in keywords if kw in text)


def select_items_for_page(all_items, page, n=4):
    """Select the top-n most relevant items for a page."""
    scored = [(score_item(i, page), i) for i in all_items]
    scored.sort(key=lambda x: -x[0])
    # Prefer scored items; fall back to unscored if needed
    selected = [i for s, i in scored if s > 0][:n]
    if len(selected) < n:
        used = {i["link"] for i in selected}
        fallback = [i for _, i in scored if i["link"] not in used]
        selected += fallback[: n - len(selected)]
    return selected[:n]


def make_card(item, date_str):
    title = item["title"].replace("<","&lt;").replace(">","&gt;").replace('"',"&quot;")
    desc  = item["desc"].replace("<","&lt;").replace(">","&gt;")[:280]
    link  = item["link"]
    return (
        f'<div class="news-card">'
        f'<h2><a href="{link}" target="_blank" rel="noopener">{title}</a></h2>'
        f'<p style="font-size:.82rem;color:#555;margin-top:6px">{desc}</p>'
        f'<p style="font-size:.7rem;color:#999;margin-top:10px">{date_str}</p>'
        f'</div>'
    )


def make_ticker(all_items):
    items = all_items[:14]
    tickers = ""
    for i in items:
        t = i["title"].replace("<","&lt;").replace(">","&gt;")[:90]
        tickers += f'<span class="ticker-item"><span>&#9679;</span>{t}</span>'
    # Duplicate for seamless loop
    tickers = tickers * 2
    return f'<div class="ticker-wrap"><div class="ticker">{tickers}</div></div>'


def make_nav(active_page):
    links = ""
    for href, label in NAV_PAGES:
        page_key = href.replace(".html","")
        cls = " class=\"active\"" if page_key == active_page else ""
        links += f'<a href="{href}"{cls}>{label}</a>\n'
    return f'<nav id="main-nav">\n{links}</nav>'


def build_page(page, cards_html, ticker_html, timestamp, date_str):
    label_map = {
        "index":"Headlines","geopolitics":"Geopolitics","stocks":"Stocks",
        "blockchain":"Blockchain","intelligence":"Intelligence","forex":"Forex",
        "markets":"Markets","realestate":"Real Estate","anime":"Anime",
        "gaming":"Gaming","entertainment":"Entertainment","lifestyle":"Lifestyle",
        "biohacking":"Biohacking",
    }
    label = label_map.get(page, page.title())
    title_map = {
        "index":"SOVSYGNAL | Headlines","geopolitics":"SOVSYGNAL | Geopolitics",
        "stocks":"SOVSYGNAL | Stocks","blockchain":"SOVSYGNAL | Blockchain",
        "intelligence":"SOVSYGNAL | Intelligence","forex":"SOVSYGNAL | Forex",
        "markets":"SOVSYGNAL | Markets","realestate":"SOVSYGNAL | Real Estate",
        "anime":"SOVSYGNAL | Anime","gaming":"SOVSYGNAL | Gaming",
        "entertainment":"SOVSYGNAL | Entertainment","lifestyle":"SOVSYGNAL | Lifestyle",
        "biohacking":"SOVSYGNAL | Biohacking",
    }
    title = title_map.get(page, f"SOVSYGNAL | {label}")
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>{title}</title>
<meta name="description" content="SOVSYGNAL - Global Intelligence Hub. {label} signals updated hourly.">
<link rel="icon" type="image/png" href="assets/logos/sovereign_favicon.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@700;900&family=Inter:wght@300;400;600;800&display=swap" rel="stylesheet">
{STYLES}
</head>
<body>
{ticker_html}
<header>
<h1><a href="index.html">SOVSYGNAL</a></h1>
<p>Global Intelligence Hub &middot; Updated {timestamp}</p>
<div class="hamburger" id="hamburger"><div></div><div></div><div></div></div>
{make_nav(page)}
</header>
<div class="container">
<main>
<div class="section-label">{label}</div>
<div class="news-grid">{cards_html}</div>
</main>
{SIDEBAR}
</div>
<footer><p>&copy; 2026 SOVSYGNAL &middot; PRISCION INTELLIGENCE MEDIA</p></footer>
{SCRIPT}
</body>
</html>"""


# ── MAIN ──────────────────────────────────────────────────────────────────────

def main():
    now = datetime.datetime.utcnow()
    # Convert to AST (UTC-4)
    ast = now - datetime.timedelta(hours=4)
    timestamp = ast.strftime("%b %d, %Y | %-I:%M %p AST")
    date_str  = ast.strftime("%b %d, %Y")
    commit_msg = f"SOVSYGNAL auto-refresh {ast.strftime('%Y-%m-%d %H:%M')} AST"

    print(f"[SOVSYGNAL] Starting refresh at {timestamp}")

    # 1. Fetch all RSS feeds
    all_items = []
    for name, url in RSS_SOURCES:
        print(f"  Fetching {name}...")
        items = fetch_rss(url)
        print(f"    Got {len(items)} items")
        all_items.extend(items)

    # Deduplicate by link
    seen = set()
    unique_items = []
    for i in all_items:
        if i["link"] not in seen:
            seen.add(i["link"])
            unique_items.append(i)

    print(f"  Total unique items: {len(unique_items)}")

    if len(unique_items) < 4:
        print("  WARNING: Not enough items fetched. Aborting to prevent empty pages.")
        return

    # 2. Build ticker from top headlines
    ticker_html = make_ticker(unique_items)

    # 3. Build and push each page
    pushed = 0
    for page in PAGES:
        print(f"  Building {page}.html...")
        items = select_items_for_page(unique_items, page, n=4)
        cards_html = "".join(make_card(i, date_str) for i in items)
        html = build_page(page, cards_html, ticker_html, timestamp, date_str)
        html_bytes = html.encode("utf-8")

        path = f"{SUBDIR}/{page}.html"
        sha  = gh_get_sha(path)
        ok   = gh_push(path, html_bytes, sha, commit_msg)
        status = "✓" if ok else "✗"
        print(f"    Push {status} ({len(html_bytes):,} bytes, sha={sha[:8]})")
        if ok:
            pushed += 1

    print(f"\n[SOVSYGNAL] Done — {pushed}/{len(PAGES)} pages pushed.")


if __name__ == "__main__":
    main()
