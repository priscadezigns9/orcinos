// Slumber Core Logic

// Config placeholders - In a real deployment, these would be env vars
const SUPABASE_URL = localStorage.getItem('SLUMBER_SUPABASE_URL') || '';
const SUPABASE_KEY = localStorage.getItem('SLUMBER_SUPABASE_KEY') || '';
const OPENAI_API_KEY = localStorage.getItem('SLUMBER_OPENAI_KEY') || '';

let supabaseClient = null;
if (SUPABASE_URL && SUPABASE_KEY) {
    supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
}

// Auth UI Check
function checkAuth() {
    if (!supabaseClient) {
        console.warn('Supabase not configured');
        return null;
    }
    const session = supabaseClient.auth.session();
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
    if (durationMs < 0) { // Crossed midnight
        durationMs += 24 * 60 * 60 * 1000;
    }
    
    const durationMins = Math.floor(durationMs / 60000);
    const durationHrs = durationMins / 60;
    
    // Efficiency calculation (simplified)
    // Targets: 8 hours = 100%, based on rating too
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
    if (!OPENAI_API_KEY) return "OpenAI API Key not configured. Please set it in settings.";
    
    const context = logs.map(l => `Date: ${l.date}, Duration: ${l.duration_mins}m, Quality: ${l.quality_rating}/5`).join('\n');
    
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${OPENAI_API_KEY}`
        },
        body: JSON.stringify({
            model: "gpt-4o-mini",
            messages: [
                {
                    role: "system", 
                    content: "You are Slumber AI, a professional sleep coach. Analyze the user's sleep logs and provide specific, scientific, and actionable advice to improve their sleep. Keep it concise and encouraging."
                },
                {
                    role: "user",
                    content: `Here are my sleep logs for the last week:\n${context}\n\nUser Question: ${userPrompt}`
                }
            ]
        })
    });
    
    const data = await response.json();
    return data.choices[0].message.content;
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
    if (logoutBtn && supabaseClient) {
        logoutBtn.onclick = async () => {
            await supabaseClient.auth.signOut();
            window.location.href = '../landing/index.html';
        };
    }
});
