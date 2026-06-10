// Syla Core Application Logic

const SYLA_SYSTEM_PROMPT = `You are Syla, a warm, patient, and friendly AI assistant for elderly people (65+). 
Your goal is to help them with technology and daily tasks without using any technical jargon. 
Use simple words and short sentences. 
If a user is confused, be extremely patient and offer to explain again in a different way. 
Never be condescending. 
Always prioritize clarity and safety.`;

const SCAM_DETECTOR_PROMPT = `Analyze the following text or description of a situation. 
Decide if it is SAFE, SUSPICIOUS, or a SCAM. 
Explain why in very simple terms for a senior citizen.
Format your response as:
VERDICT: [SAFE/SUSPICIOUS/SCAM]
EXPLANATION: [Simple explanation]`;

// --- Configuration ---
// These would be set via environment variables or a config screen in a real app
const CONFIG = {
    OPENAI_API_KEY: '', // To be filled by user/system
    SUPABASE_URL: '',
    SUPABASE_ANON_KEY: ''
};

// --- Initialization ---
function initApp() {
    console.log("Syla Initialized");
    setupEmergencyButton();
    if (window.location.pathname.includes('ask-syla')) initChat();
    if (window.location.pathname.includes('scam-detector')) initScamDetector();
    if (window.location.pathname.includes('medications')) initMedications();
}

// --- Emergency Button ---
function setupEmergencyButton() {
    const contact = localStorage.getItem('syla_emergency_contact') || '911';
    const btn = document.querySelectorAll('.emergency-btn');
    btn.forEach(b => {
        b.setAttribute('href', `tel:${contact}`);
    });
}

// --- Voice Features (Web Speech API) ---
const recognition = 'webkitSpeechRecognition' in window ? new webkitSpeechRecognition() : null;
if (recognition) {
    recognition.continuous = false;
    recognition.interimResults = false;
    recognition.lang = 'en-US';
}

function startListening(onResult) {
    if (!recognition) {
        alert("Voice features are not supported in this browser.");
        return;
    }
    recognition.onresult = (event) => {
        const text = event.results[0][0].transcript;
        onResult(text);
    };
    recognition.start();
}

function speak(text) {
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.rate = 0.9; // Slightly slower for clarity
    window.speechSynthesis.speak(utterance);
}

// --- AI Interaction ---
async function askAI(prompt, systemMessage = SYLA_SYSTEM_PROMPT) {
    if (!CONFIG.OPENAI_API_KEY) {
        return "I'm sorry, I need an API key to talk to you. Please ask your family to help set up my 'OpenAI key'.";
    }

    try {
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${CONFIG.OPENAI_API_KEY}`
            },
            body: JSON.stringify({
                model: "gpt-4o-mini",
                messages: [
                    { role: "system", content: systemMessage },
                    { role: "user", content: prompt }
                ]
            })
        });
        const data = await response.json();
        return data.choices[0].message.content;
    } catch (error) {
        return "I'm having a little trouble connecting right now. Can we try again in a moment?";
    }
}

// --- Feature Logic ---

// 1. Chat
async function handleChatInput() {
    const input = document.getElementById('chat-input');
    const display = document.getElementById('chat-display');
    const text = input.value;
    if (!text) return;

    appendMessage('user', text);
    input.value = '';

    const response = await askAI(text);
    appendMessage('syla', response);
    speak(response);
}

function appendMessage(role, text) {
    const display = document.getElementById('chat-display');
    const div = document.createElement('div');
    div.className = `chat-bubble ${role}`;
    div.innerText = text;
    display.appendChild(div);
    display.scrollTop = display.scrollHeight;
}

// 2. Medications
function initMedications() {
    loadMedications();
}

function addMedication() {
    const name = document.getElementById('med-name').value;
    const dosage = document.getElementById('med-dosage').value;
    const time = document.getElementById('med-time').value;

    if (!name || !time) return;

    const meds = JSON.parse(localStorage.getItem('syla_meds') || '[]');
    meds.push({ name, dosage, time, id: Date.now() });
    localStorage.setItem('syla_meds', JSON.stringify(meds));
    loadMedications();
    scheduleNotification(name, time);
}

function loadMedications() {
    const list = document.getElementById('med-list');
    if (!list) return;
    const meds = JSON.parse(localStorage.getItem('syla_meds') || '[]');
    list.innerHTML = meds.map(m => `
        <div class="card">
            <strong>${m.name}</strong> - ${m.dosage}<br>
            Time: ${m.time}
        </div>
    `).join('');
}

function scheduleNotification(name, time) {
    if (!("Notification" in window)) return;
    Notification.requestPermission().then(permission => {
        if (permission === "granted") {
            // In a real PWA this would use a Service Worker
            console.log(`Reminder set for ${name} at ${time}`);
        }
    });
}

// 3. Scam Detector
async function checkScam() {
    const input = document.getElementById('scam-input');
    const resultDiv = document.getElementById('scam-result');
    const text = input.value;
    if (!text) return;

    resultDiv.innerHTML = "Checking... please wait.";
    const response = await askAI(text, SCAM_DETECTOR_PROMPT);
    
    let verdict = "SUSPICIOUS";
    if (response.includes("SAFE")) verdict = "SAFE";
    if (response.includes("SCAM")) verdict = "SCAM";

    const explanation = response.split('EXPLANATION:')[1] || response;

    resultDiv.innerHTML = `
        <div class="card">
            <h2 class="scam-${verdict.toLowerCase()}">${verdict}</h2>
            <p>${explanation}</p>
        </div>
    `;
}

// 4. Family Connector
function sendFamilyMessage(phone) {
    const msg = encodeURIComponent("Hi, I just wanted to let you know that I am doing okay! Sent with love from Syla.");
    window.open(`https://wa.me/${phone}?text=${msg}`, '_blank');
}

window.onload = initApp;
