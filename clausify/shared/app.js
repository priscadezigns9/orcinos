// Clausify App Logic

const Clausify = {
    // Supabase Config (Placeholder - to be filled by user)
    supabaseUrl: '',
    supabaseKey: '',
    
    init: function() {
        console.log("Clausify Initialized");
        this.loadFAQs();
        this.loadIPGuide();
        this.setupRateCalculator();
        this.setupContractGenerator();
        this.setupDMCAGenerator();
    },

    // 1. Contract Generator
    setupContractGenerator: function() {
        const form = document.getElementById('contract-form');
        if (!form) return;

        form.addEventListener('input', () => {
            this.updateContractPreview();
        });

        const downloadBtn = document.getElementById('download-contract');
        if (downloadBtn) {
            downloadBtn.addEventListener('click', () => {
                window.print();
            });
        }
        
        const saveBtn = document.getElementById('save-contract');
        if (saveBtn) {
            saveBtn.addEventListener('click', () => {
                this.saveContractToVault();
            });
        }
    },

    updateContractPreview: function() {
        const type = document.getElementById('contract-type').value;
        const creatorName = document.getElementById('creator-name').value || '[Your Name]';
        const clientName = document.getElementById('client-name').value || '[Client Name]';
        const deliverables = document.getElementById('deliverables').value || '[List of Deliverables]';
        const paymentAmount = document.getElementById('payment-amount').value || '[Payment Amount]';
        const deadline = document.getElementById('deadline').value || '[Deadline Date]';
        const jurisdiction = document.getElementById('jurisdiction').value || '[State/Country]';

        fetch('../data/contract-templates.json')
            .then(res => {
                if (!res.ok) throw new Error(`HTTP ${res.status}: ${res.statusText}`);
                return res.json();
            })
            .then(templates => {
                const template = templates.find(t => t.id === type);
                if (template) {
                    let html = template.template;
                    html = html.replace(/{{creator_name}}/g, creatorName);
                    html = html.replace(/{{client_name}}/g, clientName);
                    html = html.replace(/{{deliverables}}/g, deliverables);
                    html = html.replace(/{{payment_amount}}/g, paymentAmount);
                    html = html.replace(/{{deadline}}/g, deadline);
                    html = html.replace(/{{jurisdiction}}/g, jurisdiction);
                    
                    document.getElementById('contract-preview').innerHTML = html;
                }
            })
            .catch(error => {
                console.error("Failed to load contract templates:", error);
            });
    },

    saveContractToVault: function() {
        alert("Contract saved to Vault (Simulated). Connect Supabase in app.js for persistence.");
    },

    // 2. IP Protection Guide
    loadIPGuide: function() {
        const container = document.getElementById('ip-guide-container');
        if (!container) return;

        fetch('../data/ip-guide.json')
            .then(res => {
                if (!res.ok) throw new Error(`HTTP ${res.status}: ${res.statusText}`);
                return res.json();
            })
            .then(data => {
                container.innerHTML = data.map(item => `
                    <div class="card">
                        <h3>${item.title}</h3>
                        <ul>
                            ${item.steps.map(step => `<li>${step}</li>`).join('')}
                        </ul>
                    </div>
                `).join('');
            })
            .catch(error => {
                console.error("Failed to load IP guide:", error);
            });
    },

    // 3. DMCA Generator
    setupDMCAGenerator: function() {
        const form = document.getElementById('dmca-form');
        if (!form) return;

        form.addEventListener('submit', (e) => {
            e.preventDefault();
            const infringingUrl = document.getElementById('infringing-url').value;
            const description = document.getElementById('content-desc').value;
            const myName = document.getElementById('my-name').value;

            const notice = `
                DMCA TAKEDOWN NOTICE
                
                To: Designated Copyright Agent
                
                I, ${myName}, certify under penalty of perjury that I am the owner of the copyrighted material described below.
                
                Content Description: ${description}
                
                Infringing Location: ${infringingUrl}
                
                I have a good faith belief that use of the material in the manner complained of is not authorized by the copyright owner, its agent, or the law.
                
                Signed: ${myName}
                Date: ${new Date().toLocaleDateString()}
            `;

            const preview = document.getElementById('dmca-preview');
            preview.innerText = notice;
            preview.style.display = 'block';
            document.getElementById('copy-dmca').style.display = 'inline-block';
        });
        
        const copyBtn = document.getElementById('copy-dmca');
        if(copyBtn) {
            copyBtn.addEventListener('click', () => {
                const text = document.getElementById('dmca-preview').innerText;
                navigator.clipboard.writeText(text);
                alert("DMCA Notice copied to clipboard!");
            });
        }
    },

    // 4. Rate Calculator
    setupRateCalculator: function() {
        const calcBtn = document.getElementById('calculate-rate');
        if (!calcBtn) return;

        calcBtn.addEventListener('click', () => {
            const followers = parseInt(document.getElementById('followers').value);
            const engagement = parseFloat(document.getElementById('engagement').value);
            const contentType = document.getElementById('content-type').value;

            let baseRate = followers * 0.01; // $10 per 1000 followers
            let engagementMultiplier = engagement > 3 ? 1.5 : 1;
            
            let typeMultiplier = 1;
            if (contentType === 'video') typeMultiplier = 2.5;
            if (contentType === 'carousel') typeMultiplier = 1.5;
            
            let finalRate = baseRate * engagementMultiplier * typeMultiplier;
            
            document.getElementById('rate-result').innerText = `$${finalRate.toFixed(2)}`;
        });
    },

    // 6. Legal FAQ
    loadFAQs: function() {
        const container = document.getElementById('faq-container');
        if (!container) return;

        fetch('../data/faq.json')
            .then(res => {
                if (!res.ok) throw new Error(`HTTP ${res.status}: ${res.statusText}`);
                return res.json();
            })
            .then(faqs => {
                container.innerHTML = faqs.map(faq => `
                    <div class="faq-item">
                        <div class="faq-question" onclick="this.parentElement.classList.toggle('open')">
                            ${faq.q} <span>+</span>
                        </div>
                        <div class="faq-answer">
                            ${faq.a}
                        </div>
                    </div>
                `).join('');
            })
            .catch(error => {
                console.error("Failed to load FAQs:", error);
            });
    }
};

document.addEventListener('DOMContentLoaded', () => Clausify.init());
