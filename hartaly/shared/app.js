// Keys loaded from runtime config — never hardcode real credentials in source
const SUPABASE_URL = window.HARTALY_CONFIG?.SUPABASE_URL || '';
const SUPABASE_ANON_KEY = window.HARTALY_CONFIG?.SUPABASE_ANON_KEY || '';
const OPENAI_API_KEY = window.HARTALY_CONFIG?.OPENAI_API_KEY || '';

// Check if crisis keywords are present
function detectCrisis(text) {
    const keywords = ['suicide', 'self-harm', 'kill myself', 'end it all', "don't want to be here", 'hanging', 'overdose', 'cut myself'];
    return keywords.some(keyword => text.toLowerCase().includes(keyword));
}

// Crisis Protocol Redirect
function triggerCrisisProtocol() {
    window.location.href = '/app/crisis.html';
}

// App State
let currentUser = null;

// Initialize Supabase Client (Assuming supabase library is loaded via script tag)
const supabaseClient = (typeof supabase !== 'undefined') ? supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY) : null;

// Auth Check
async function checkAuth() {
    if (!supabaseClient) return;
    const { data: { user } } = await supabaseClient.auth.getUser();
    if (user) {
        currentUser = user;
        // Load user profile from 'users' table
        const { data: profile } = await supabaseClient.from('users').select('*').eq('id', user.id).single();
        if (profile) {
            currentUser.profile = profile;
        }
    } else {
        if (!window.location.pathname.includes('landing')) {
            window.location.href = '/landing/index.html';
        }
    }
}

// Hartaly AI Chat Logic
async function sendMessageToHartaly(message, history = []) {
    if (detectCrisis(message)) {
        triggerCrisisProtocol();
        return null;
    }

    const systemPrompt = "You are Hartaly, a warm, empathetic AI mental wellness coach. You speak like a trusted friend — never clinical, never robotic. You remember the user's history from this session. You use evidence-based CBT and mindfulness techniques naturally in conversation. You NEVER diagnose. If you detect self-harm or crisis language, you immediately stop coaching and display crisis hotline numbers with a warm, caring message. Keep responses concise (2-4 sentences) unless the user needs more.";

    const messages = [
        { role: "system", content: systemPrompt },
        ...history,
        { role: "user", content: message }
    ];

    try {
        const response = await fetch('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${OPENAI_API_KEY}`
            },
            body: JSON.stringify({
                model: "gpt-4o",
                messages: messages,
                temperature: 0.7
            })
        });

        const data = await response.json();
        if (data.error) return "I'm here for you, but I'm having a little trouble connecting right now. Take a deep breath with me?";
        return data.choices?.[0]?.message?.content || "I'm here for you. Let me try again in a moment.";
    } catch (error) {
        return "I'm here for you, but I'm having a little trouble connecting right now. Take a deep breath with me?";
    }
}

// Mood Tracker Logic
async function logMood(score, note) {
    if (!supabaseClient) return;
    const { data, error } = await supabaseClient.from('mood_logs').insert([
        { user_id: currentUser.id, score, note }
    ]);
    return { data, error };
}

// Journal Logic
async function generateJournalPrompt() {
    // Get recent mood
    const { data: moods } = await supabaseClient
        .from('mood_logs')
        .select('score')
        .order('created_at', { ascending: false })
        .limit(3);
    
    let context = "Neutral mood";
    if (moods && moods.length > 0) {
        const avg = moods.reduce((a, b) => a + b.score, 0) / moods.length;
        context = avg < 4 ? "low mood/sad" : avg > 7 ? "high mood/happy" : "stable mood";
    }

    const promptRequest = `User has been feeling ${context}. Generate a warm, single-sentence guided journal prompt for them to reflect on their day.`;
    
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${OPENAI_API_KEY}`
        },
        body: JSON.stringify({
            model: "gpt-4o",
            messages: [{ role: "user", content: promptRequest }],
            max_tokens: 100
        })
    });
    const data = await response.json();
    if (data.error) return "Unable to generate prompt right now.";
    return data.choices?.[0]?.message?.content || "Take a moment to reflect on something that made you smile today.";
}

// Breathing Room Audio
function playChime() {
    const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    const oscillator = audioCtx.createOscillator();
    const gainNode = audioCtx.createGain();

    oscillator.type = 'sine';
    oscillator.frequency.setValueAtTime(440, audioCtx.currentTime); // A4
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
