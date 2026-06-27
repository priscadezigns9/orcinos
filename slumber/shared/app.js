// Slumber Core Logic — uses shared OrcinosAI and OrcinosDB utilities

// Config
const SLUMBER_CONFIG = {
    SUPABASE_URL: localStorage.getItem('SLUMBER_SUPABASE_URL') || '',
    SUPABASE_KEY: localStorage.getItem('SLUMBER_SUPABASE_KEY') || '',
    OPENAI_API_KEY: localStorage.getItem('SLUMBER_OPENAI_KEY') || ''
};

const SLUMBER_SYSTEM_PROMPT = "You are Slumber AI, a professional sleep coach. Analyze the user's sleep logs and provide specific, scientific, and actionable advice to improve their sleep. Keep it concise and encouraging.";

// Initialize shared clients
const slumberAI = new OrcinosAI({
    apiKey: SLUMBER_CONFIG.OPENAI_API_KEY,
    model: 'gpt-4o-mini'
});

const slumberDB = new OrcinosDB({
    url: SLUMBER_CONFIG.SUPABASE_URL,
    anonKey: SLUMBER_CONFIG.SUPABASE_KEY
});

// Auth UI Check
function checkAuth() {
    slumberDB.init();
    if (!slumberDB.client) {
        console.warn('Supabase not configured');
        return null;
    }
    const session = slumberDB.client.auth.session();
    if (!session && !window.location.pathname.includes('index.html')) {
        window.location.href = '../landing/index.html';
    }
    return session;
}

// Sleep Calculations
function calculateSleepStats(bedtimeStr, wakeTimeStr) {
    const bedtime = new Date(bedtimeStr);
    const wakeTime = new Date(wakeTimeStr);

    let durationMs = wakeTime - bedtime;
    if (durationMs < 0) {
        durationMs += 24 * 60 * 60 * 1000;
    }

    const durationMins = Math.floor(durationMs / 60000);
    const durationHrs = durationMins / 60;

    let baseScore = (durationHrs >= 7 && durationHrs <= 9) ? 100 : (durationHrs < 7 ? (durationHrs / 7) * 100 : (9 / durationHrs) * 100);

    return {
        durationMins,
        efficiencyScore: Math.min(100, Math.round(baseScore))
    };
}

// Gauge UI
function updateGauge(score) {
    const fill = document.querySelector('.gauge-fill');
    const val = document.querySelector('.score-val');
    if (!fill || !val) return;

    const circumference = 2 * Math.PI * 90;
    const offset = circumference - (score / 100) * circumference;

    fill.style.strokeDashoffset = offset;
    val.textContent = Math.round(score);
}

// AI Coach Call
async function getAICoachResponse(logs, userPrompt) {
    if (!SLUMBER_CONFIG.OPENAI_API_KEY) {
        return "OpenAI API Key not configured. Please set it in settings.";
    }

    const context = logs.map(l => `Date: ${l.date}, Duration: ${l.duration_mins}m, Quality: ${l.quality_rating}/5`).join('\n');

    return await slumberAI.chat(
        `Here are my sleep logs for the last week:\n${context}\n\nUser Question: ${userPrompt}`,
        { systemPrompt: SLUMBER_SYSTEM_PROMPT }
    );
}

// Data Loaders
async function loadArticles() {
    const res = await fetch('../data/articles.json');
    return await res.json();
}

async function loadSounds() {
    const res = await fetch('../data/sounds.json');
    return await res.json();
}

// Shared UI Handlers
document.addEventListener('DOMContentLoaded', () => {
    const logoutBtn = document.getElementById('logout-btn');
    if (logoutBtn && slumberDB.client) {
        logoutBtn.onclick = async () => {
            await slumberDB.signOut();
            window.location.href = '../landing/index.html';
        };
    }
});
