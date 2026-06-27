// Supabase & OpenAI Keys (Placeholders - User must provide real keys in production)
const SUPABASE_URL = 'https://sktpjacowqaedddtrhuz.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNrdHBqYWNvd3FhZWRkZHRyaHV6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg2NDk5MzEsImV4cCI6MjA5NDIyNTkzMX0.FK4N_ATFTaUuGXrYu_7OBn3qCdlo0rOzxk-E6TxJxqs';
const OPENAI_API_KEY = 'your-openai-key';

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

        if (!response.ok) {
            console.error("OpenAI API error:", response.status, response.statusText);
            return "I'm here for you, but I'm having a little trouble connecting right now. Take a deep breath with me?";
        }
        const data = await response.json();
        if (!data.choices || !data.choices[0]) {
            console.error("Unexpected API response structure:", data);
            return "I'm here for you, but I'm having a little trouble connecting right now. Take a deep breath with me?";
        }
        return data.choices[0].message.content;
    } catch (error) {
        console.error("AI Error:", error);
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
    try {
        if (!supabaseClient) {
            console.error("Supabase client not initialized");
            return "What is one thing you are grateful for today?";
        }

        // Get recent mood
        const { data: moods, error: moodError } = await supabaseClient
            .from('mood_logs')
            .select('score')
            .order('created_at', { ascending: false })
            .limit(3);

        if (moodError) {
            console.error("Failed to fetch mood logs:", moodError);
        }

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
        if (!response.ok) {
            console.error("OpenAI API error:", response.status, response.statusText);
            return "What is one thing you are grateful for today?";
        }
        const data = await response.json();
        if (!data.choices || !data.choices[0]) {
            console.error("Unexpected API response structure:", data);
            return "What is one thing you are grateful for today?";
        }
        return data.choices[0].message.content;
    } catch (error) {
        console.error("Journal prompt generation failed:", error);
        return "What is one thing you are grateful for today?";
    }
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
