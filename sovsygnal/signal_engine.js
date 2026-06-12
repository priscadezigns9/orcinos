/* 
    ORCPULSE | Neural News Engine v1.3
    (c) 2026 Orcinos AI Labs
    Autonomous High-Fidelity Pulse Processing
*/

const PulseEngine = {
    sectors: {
        geopolitics: [
            "Omani Mediators Relay Tehran’s Formal Counteroffer to US.",
            "Strategic Initiative: Regional Channels Evaluate Multilateral Mediation.",
            "Elite Defense: AI-Driven Pulse Processing prioritized in Security Budget."
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
            "Global Fragmentation: Trade Logistics adapt to Economic Independence shift."
        ],
        anime: [
            "Trending: Tongari Boushi no Atelier leads Seasonal Viewership.",
            "Grand Blue Dreaming Season 3 confirmed for July 2026 debut.",
            "Production quality reaches new High-Fidelity standard for 'Summer 2026'."
        ],
        stocks: [
            "Dow Jones Futures: Industrial Sentiment remains Bullish.",
            "Tech Sector Resilience: S&P 500 maintains level despite volatility.",
            "Dividend Growth: Top-tier equities announce record yields."
        ],
        lifestyle: [
            "Resilient Habitat: Lord Norman Foster addresses Madrid CityLab.",
            "Smart Cities: AI Integration optimizes urban resource logistics.",
            "Minimalist Architecture: Focus on sanctuary-based living spaces."
        ],
        forex: [
            "USD/JPY Stability: Central Banks maintain current policy stance.",
            "Euro-Zone Outlook: Inflation targets met, markets stabilize.",
            "GBP/USD Resilience: Strong labor data bolsters Sterling."
        ],
        realestate: [
            "Veteran housing policy needs a preservation strategy.",
            "Luxury Listings: High-end properties see increased international demand.",
            "Sustainable Development: Eco-friendly construction becomes industry standard."
        ]
    },

    ads: [
        { brand: "ORCINOS", text: "Apex Intelligence for the elite architect.", link: "https://orcinos.com/" },
        { brand: "GLOW PROTOCOL", text: "DNA-optimized skincare. Enter the future.", link: "https://orcinos.com/glowprotocol/" },
        { brand: "ATELIA GAMING", text: "The independent economy of play.", link: "https://orcinos.com/ateliagaming/" },
        { brand: "PEAK FIT", text: "Biohacking performance metrics. Join the elite.", link: "https://orcinos.com/peakfit/" },
        { brand: "COUTURE GALLERY", text: "High-end bags. Archival craftsmanship.", link: "https://orcinos.com/couturegallery/" }
    ],

    init() {
        console.log("OrcPulse Neural Handshake: ACTIVE");
        this.startTickers();
        this.updateSectors();
        this.updateAds();
        this.injectMessenger();
    },

    startTickers() {
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
        const sectorKeys = Object.keys(this.sectors);
        let index = 0;
        setInterval(() => {
            const sector = sectorKeys[index % sectorKeys.length];
            const el = document.getElementById(`news-${sector}`);
            if (el) {
                el.style.opacity = 0;
                setTimeout(() => {
                    el.innerText = this.sectors[sector][Math.floor(Math.random() * this.sectors[sector].length)];
                    el.style.opacity = 1;
                }, 500);
            }
            index++;
        }, 4000); // Fluid rotation every 4s
    },

    updateAds() {
        const brandAds = document.querySelectorAll('.ticker-item.brand');
        if (brandAds.length > 0) {
            brandAds.forEach((ad, idx) => {
                setInterval(() => {
                    const randomAd = this.ads[Math.floor(Math.random() * this.ads.length)];
                    const span = ad.querySelector('span');
                    const p = ad.querySelector('p');
                    if (span && p) {
                        ad.style.opacity = 0;
                        setTimeout(() => {
                            span.innerText = randomAd.brand;
                            p.innerText = randomAd.text;
                            ad.style.opacity = 1;
                        }, 500);
                    }
                }, 10000 + (idx * 2000)); // Staggered rotation
            });
        }
    },

    injectMessenger() {
        if (document.getElementById('orc-messenger')) return;

        const messenger = document.createElement('div');
        messenger.id = 'orc-messenger';
        messenger.style = `
            position: fixed; bottom: 30px; right: 30px;
            width: min(350px, 90vw); height: 500px;
            background: white; border: 4px solid black;
            box-shadow: 0 20px 50px rgba(0,0,0,0.3);
            z-index: 5000; display: flex; flex-direction: column;
            font-family: 'Inter', sans-serif; transition: transform 0.3s cubic-bezier(0.4, 0, 0.2, 1);
        `;

        messenger.innerHTML = `
            <div style="background: black; color: white; padding: 15px; font-weight: 800; font-size: 0.75rem; letter-spacing: 2px; display: flex; justify-content: space-between; align-items: center; cursor: pointer;" onclick="toggleMessenger()">
                <span>NEURAL DESK | ORCPULSE</span>
                <span id="msg-toggle-icon">_</span>
            </div>
            <div id="chat-stream" style="flex: 1; padding: 20px; overflow-y: auto; font-size: 0.85rem; line-height: 1.4; color: #333; background: #fff;">
                <div style="margin-bottom: 15px;"><strong>SYSTEM:</strong> Neural handshake established. Sector parity confirmed.</div>
            </div>
            <div style="padding: 15px; border-top: 1px solid #eee; background: #fff;">
                <input type="text" placeholder="Type a command..." style="width: 100%; border: 2px solid #000; padding: 10px; font-family: inherit; font-size: 0.8rem; outline: none;">
            </div>
        `;

        document.body.appendChild(messenger);

        window.toggleMessenger = () => {
            const m = document.getElementById('orc-messenger');
            const icon = document.getElementById('msg-toggle-icon');
            if (m.style.transform === 'translateY(calc(100% - 45px))') {
                m.style.transform = 'translateY(0)';
                icon.innerText = '_';
            } else {
                m.style.transform = 'translateY(calc(100% - 45px))';
                icon.innerText = '^';
            }
        };

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
            if (stream.children.length > 20) stream.removeChild(stream.firstChild);
        }, 8000);
    }
};

document.addEventListener('DOMContentLoaded', () => PulseEngine.init());
