/*
    SOVSYGNAL | Neural Signal Engine v1.0
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
        ]
    },

    ads: [
        { brand: "ORCINOS", text: "Apex Intelligence for the sovereign architect. Build your digital empire.", link: "https://orcinos.com/" },
        { brand: "GLOW PROTOCOL", text: "Regenerative beauty tech and DNA-optimized skincare. Enter the future.", link: "https://orcinos.com/glowprotocol/" },
        { brand: "ATELIA GAMING", text: "The sovereign economy of play. High-fidelity gaming and meta-assets.", link: "https://orcinos.com/ateliagaming/" }
    ],

    init() {
        console.log("SovSygnal Neural Handshake: ACTIVE");
        this.startTickers();
        this.updateSectors();
        this.injectMessenger();
        this.rotateAds();
    },

    startTickers() {
        const ticker = document.querySelector('.utility-bar div:last-child');
        if (ticker) {
            setInterval(() => {
                const prn = (4.0 + Math.random() * 0.5).toFixed(2);
                const eth = (3500 + Math.random() * 50).toFixed(0);
                ticker.innerHTML = `MARKET: $PRN +${prn}% · ETH $${eth} · Intelligence: <span style="color:#D0021B; font-weight:800;">LIVE</span>`;
            }, 3000);
        }
    },

    updateSectors() {
        // Logic to update sector headlines if IDs are present
        Object.keys(this.sectors).forEach(sector => {
            const el = document.getElementById(`news-${sector}`);
            if (el) {
                const news = this.sectors[sector];
                let i = 0;
                setInterval(() => {
                    el.innerText = news[i];
                    i = (i + 1) % news.length;
                }, 8000);
            }
        });
    },

    rotateAds() {
        const adContainer = document.querySelector('.ad-group');
        // This would rotate the static ads if needed
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
                <div style="margin-bottom: 15px;"><strong>SYSTEM:</strong> Neural handshake established. Listening to global frequency 104.2...</div>
                <div style="margin-bottom: 15px;"><strong>INTEL:</strong> Sector parity confirmed. Geopolitics signal at 98.4% fidelity.</div>
            </div>
            <div style="padding: 15px; border-top: 1px solid #eee;">
                <input type="text" placeholder="Type a command or signal..." style="width: 100%; border: 2px solid #000; padding: 10px; font-family: inherit; font-size: 0.8rem; outline: none;">
            </div>
        `;

        document.body.appendChild(messenger);

        // Simple Chat Automation for "Updates"
        const stream = document.getElementById('chat-stream');
        setInterval(() => {
            const sectors = ['GEOPOLITICS', 'BLOCKCHAIN', 'BIOHACKING', 'MARKETS'];
            const sector = sectors[Math.floor(Math.random() * sectors.length)];
            const msg = document.createElement('div');
            msg.style.marginBottom = '15px';
            msg.innerHTML = `<strong>${sector}:</strong> ${this.sectors[sector.toLowerCase()][Math.floor(Math.random() * 3)]}`;
            stream.appendChild(msg);
            stream.scrollTop = stream.scrollHeight;
            if (stream.children.length > 10) stream.removeChild(stream.firstChild);
        }, 12000);
    }
};

document.addEventListener('DOMContentLoaded', () => SignalEngine.init());
