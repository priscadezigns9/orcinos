/*
    SOVSYGNAL | Neural Signal Engine v1.1
    (c) 2026 Prisca Dezigns AI Labs
    Autonomous High-Fidelity Signal Processing
*/

const SignalEngine = {
    sectors: {
        geopolitics: [
            "Omani Mediators Relay Tehran’s Formal Counteroffer to US.",
            "Strategic Initiative: Regional Channels Evaluate Multilateral Mediation.",
            "Sovereign Defense: AI-Driven Signal Processing prioritize in Security Budget."
        ],
        blockchain: [
            "SEC Finalizes Innovation Exemption for Tokenized Stocks.",
            "Ledger Efficiency: Major Exchange Finalizes Automated Proof-of-Reserve.",
            "Neural Ledger: $PRN Token Utility reaches 100% stable deployment."
        ],
        biohacking: [
            "Roche Obesity Drug outpaces Industry Targets in latest trials.",
            "Neural Benchmarks: New CGMs achieve 99% accuracy in real-time diagnostics.",
            "Regenerative Treatment: Scientific consensus emerging around neural-calibration."
        ],
        markets: [
            "Nasdaq Rebound: Chipmakers Lead Recovery Post-Selloff.",
            "Institutional Inflow: Tech Infrastructure Bonds see Record Volume.",
            "Global Fragmentation: Trade Logistics adapt to Economic Sovereignty shift."
        ],
        anime: [
            "Trending: Tongari Boushi no Atelier leads Seasonal Viewership.",
            "Grand Blue Dreaming Season 3 confirmed for July 2026 debut.",
            "Production quality remains high-fidelity across major studios."
        ],
        stocks: [
            "Market Stability: Institutional Flows Maintain Resilience.",
            "Tech Infrastructure Bonds see Record Institutional Inflow.",
            "S&P 500 stabilizes as Geopolitical Risk premiums subside."
        ],
        forex: [
            "Forex Stability Pivot: Major Pairs stabilize as risk premiums subside.",
            "Market sentiment shifts toward high-fidelity currency performance.",
            "Neural arbitrage algorithms report 99% accuracy in volatility projection."
        ],
        realestate: [
            "Veteran housing policy needs a preservation strategy.",
            "High-fidelity sector signal tracking market performance.",
            "Urban Sanctuary: Foster + Partners unveil Eco-Integrated Madrid Hub."
        ],
        intelligence: [
            "Defense Directive: AI-Driven Signal Processing prioritized.",
            "Strategic Intelligence: Data-transit corridors in Arctic Circle established.",
            "Global Signal: Sovereign Frequency 104.2 reaches peak fidelity."
        ],
        lifestyle: [
            "Resilient Habitat: Lord Norman Foster addresses Madrid CityLab.",
            "Urban Sanctuary: Eco-Integrated design becomes the new gold standard.",
            "High-fidelity living: Personal sanctuary engineering trends upward."
        ]
    },

    ads: [
        { brand: "ORCINOS", text: "Apex Intelligence for the sovereign architect.", link: "https://orcinos.com/" },
        { brand: "GLOW PROTOCOL", text: "DNA-optimized skincare. Enter the future.", link: "https://orcinos.com/glowprotocol/" },
        { brand: "ATELIA GAMING", text: "The sovereign economy of play.", link: "https://orcinos.com/ateliagaming/" }
    ],

    init() {
        console.log("SovSygnal Neural Handshake: ACTIVE");
        this.startTickers();
        this.updateSectors();
        this.injectMessenger();
    },

    startTickers() {
        const dateEl = document.getElementById('live-date');
        const tickerEl = document.getElementById('live-ticker');
        
        if (tickerEl) {
            setInterval(() => {
                const prn = (4.0 + Math.random() * 0.5).toFixed(2);
                const eth = (3500 + Math.random() * 50).toFixed(0);
                tickerEl.innerHTML = `MARKET: $PRN +${prn}% · ETH $${eth} · Intelligence: <span style="color:#D0021B; font-weight:800;">LIVE</span>`;
            }, 3000);
        }
    },

    updateSectors() {
        Object.keys(this.sectors).forEach(sector => {
            const el = document.getElementById(`news-${sector}`);
            if (el) {
                const news = this.sectors[sector];
                let i = 0;
                setInterval(() => {
                    i = (i + 1) % news.length;
                    el.style.opacity = 0;
                    setTimeout(() => {
                        el.innerText = news[i];
                        el.style.opacity = 1;
                    }, 500);
                }, 10000);
            }
        });
    },

    injectMessenger() {
        if (document.getElementById('sovsygnal-messenger')) return;

        const messenger = document.createElement('div');
        messenger.id = 'sovsygnal-messenger';
        messenger.style = `
            position: fixed; bottom: 30px; right: 30px;
            width: 350px; height: 500px;
            background: white; border: 4px solid black;
            box-shadow: 0 20px 50px rgba(0,0,0,0.3);
            z-index: 5000; display: flex; flex-direction: column;
            font-family: 'Inter', sans-serif; transition: transform 0.3s ease;
        `;
        
        messenger.innerHTML = `
            <div style="background: black; color: white; padding: 15px; font-weight: 800; font-size: 0.8rem; display: flex; justify-content: space-between; align-items: center;">
                <span>NEURAL DESK | SOVSYGNAL</span>
                <span style="color: #D0021B; font-size: 0.6rem; letter-spacing: 1px;">ENCRYPTED</span>
            </div>
            <div id="chat-stream" style="flex: 1; padding: 20px; overflow-y: auto; font-size: 0.85rem; line-height: 1.4; color: #333;">
                <div style="margin-bottom: 15px;"><strong>SYSTEM:</strong> Neural handshake established. Sector parity confirmed.</div>
            </div>
            <div style="padding: 15px; border-top: 1px solid #eee;">
                <input type="text" placeholder="Type a command..." style="width: 100%; border: 2px solid #000; padding: 10px; font-family: inherit; font-size: 0.8rem; outline: none;">
            </div>
        `;

        document.body.appendChild(messenger);

        const stream = document.getElementById('chat-stream');
        setInterval(() => {
            const sectors = Object.keys(this.sectors);
            const sector = sectors[Math.floor(Math.random() * sectors.length)];
            const msg = document.createElement('div');
            msg.style.marginBottom = '15px';
            msg.style.opacity = 0;
            msg.style.transition = 'opacity 0.5s ease';
            msg.innerHTML = `<strong>${sector.toUpperCase()}:</strong> ${this.sectors[sector][Math.floor(Math.random() * this.sectors[sector].length)]}`;
            stream.appendChild(msg);
            setTimeout(() => msg.style.opacity = 1, 10);
            stream.scrollTop = stream.scrollHeight;
            if (stream.children.length > 15) stream.removeChild(stream.firstChild);
        }, 8000);
    }
};

document.addEventListener('DOMContentLoaded', () => SignalEngine.init());
