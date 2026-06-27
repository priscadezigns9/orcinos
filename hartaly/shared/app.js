// Hartaly App Logic — uses shared OrcinosAI and OrcinosDB utilities

// Config
const HARTALY_CONFIG = {
    SUPABASE_URL: 'https://sktpjacowqaedddtrhuz.supabase.co',
    SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNrdHBqYWNvd3FhZWRkZHRyaHV6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg2NDk5MzEsImV4cCI6MjA5NDIyNTkzMX0.FK4N_ATFTaUuGXrYu_7OBn3qCdlo0rOzxk-E6TxJxqs',
    OPENAI_API_KEY: 'your-openai-key'
};

const HARTALY_SYSTEM_PROMPT = "You are Hartaly, a warm, empathetic AI mental wellness coach. You speak like a trusted friend — never clinical, never robotic. You remember the user's history from this session. You use evidence-based CBT and mindfulness techniques naturally in conversation. You NEVER diagnose. If you detect self-harm or crisis language, you immediately stop coaching and display crisis hotline numbers with a warm, caring message. Keep responses concise (2-4 sentences) unless the user needs more.";

// Initialize shared clients
const hartalyAI = new OrcinosAI({
    apiKey: HARTALY_CONFIG.OPENAI_API_KEY,
    model: 'gpt-4o'
});

const hartalyDB = new OrcinosDB({
    url: HARTALY_CONFIG.SUPABASE_URL,
    anonKey: HARTALY_CONFIG.SUPABASE_ANON_KEY
});

// Crisis detection
function detectCrisis(text) {
    const keywords = ['suicide', 'self-harm', 'kill myself', 'end it all', "don't want to be here", 'hanging', 'overdose', 'cut myself'];
    return keywords.some(keyword => text.toLowerCase().includes(keyword));
}

function triggerCrisisProtocol() {
    window.location.href = '/app/crisis.html';
}

// App State
let currentUser = null;

// Auth Check
async function checkAuth() {
    hartalyDB.init();
    currentUser = await hartalyDB.getCurrentUser();

    if (currentUser) {
        const { data: profile } = await hartalyDB.fetchOne('users', { id: currentUser.id });
        if (profile) {
            currentUser.profile = profile;
        }
    } else {
        hartalyDB.requireAuth('/landing/index.html');
    }
}

// Hartaly AI Chat Logic
async function sendMessageToHartaly(message, history = []) {
    if (detectCrisis(message)) {
        triggerCrisisProtocol();
        return null;
    }

    return await hartalyAI.chat(message, {
        systemPrompt: HARTALY_SYSTEM_PROMPT,
        history,
        errorMessage: "I'm here for you, but I'm having a little trouble connecting right now. Take a deep breath with me?"
    });
}

// Mood Tracker Logic
async function logMood(score, note) {
    if (!hartalyDB.client) return;
    return await hartalyDB.insert('mood_logs', { user_id: currentUser.id, score, note });
}

// Journal Logic
async function generateJournalPrompt() {
    const { data: moods } = await hartalyDB.fetchMany('mood_logs', {
        orderBy: 'created_at',
        ascending: false,
        limit: 3
    });

    let context = "Neutral mood";
    if (moods && moods.length > 0) {
        const avg = moods.reduce((a, b) => a + b.score, 0) / moods.length;
        context = avg < 4 ? "low mood/sad" : avg > 7 ? "high mood/happy" : "stable mood";
    }

    const promptRequest = `User has been feeling ${context}. Generate a warm, single-sentence guided journal prompt for them to reflect on their day.`;

    return await hartalyAI.chat(promptRequest, {
        systemPrompt: 'You generate warm journal prompts.',
        maxTokens: 100
    });
}

// Breathing Room Audio
function playChime() {
    const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    const oscillator = audioCtx.createOscillator();
    const gainNode = audioCtx.createGain();

    oscillator.type = 'sine';
    oscillator.frequency.setValueAtTime(440, audioCtx.currentTime);
    gainNode.gain.setValueAtTime(0.1, audioCtx.currentTime);
    gainNode.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + 1.5);

    oscillator.connect(gainNode);
    gainNode.connect(audioCtx.destination);

    oscillator.start();
    oscillator.stop(audioCtx.currentTime + 1.5);
}

// Initialize on load
document.addEventListener('DOMContentLoaded', () => {
    checkAuth();
});
