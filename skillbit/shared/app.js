// Skillbit Core Logic

// Note: Replace these with actual Supabase credentials if deployed
const SUPABASE_URL = window.CONFIG?.SUPABASE_URL || 'YOUR_SUPABASE_URL';
const SUPABASE_KEY = window.CONFIG?.SUPABASE_KEY || 'YOUR_SUPABASE_KEY';

// Mock Supabase Client if not available (for demonstration)
const supabase = (typeof createClient !== 'undefined') 
    ? createClient(SUPABASE_URL, SUPABASE_KEY)
    : {
        auth: {
            getUser: async () => ({ data: { user: JSON.parse(localStorage.getItem('sb-user')) }, error: null }),
            signInWithPassword: async () => ({ data: { user: { id: 'mock-id' } }, error: null }),
            signOut: async () => { localStorage.removeItem('sb-user'); window.location.reload(); }
        },
        from: (table) => ({
            select: () => ({ 
                eq: () => ({ single: async () => ({ data: JSON.parse(localStorage.getItem(`sb-${table}`)) || {}, error: null }) }),
                order: () => ({ limit: async () => ({ data: [], error: null }) })
            }),
            insert: () => ({ select: () => ({ single: async () => ({ data: {}, error: null }) }) }),
            update: () => ({ eq: async () => ({ data: {}, error: null }) })
        })
    };

// App State
let user = null;
let profile = null;
let lessons = [];
let currentLesson = null;
let quizScore = 0;

// Initialize
document.addEventListener('DOMContentLoaded', async () => {
    await checkAuth();
    await loadLessons();
    initUI();
});

async function checkAuth() {
    const { data } = await supabase.auth.getUser();
    user = data.user;
    if (user) {
        await fetchProfile();
        updateAuthUI(true);
    } else {
        updateAuthUI(false);
    }
}

async function fetchProfile() {
    // In a real app, this would fetch from Supabase
    // For this build, we'll use localStorage to ensure functionality
    const savedProfile = localStorage.getItem('skillbit_profile');
    if (savedProfile) {
        profile = JSON.parse(savedProfile);
    } else {
        profile = {
            user_id: user.id,
            username: user.email?.split('@')[0] || 'User',
            track: 'Web Dev',
            lessons_completed: 0,
            xp_total: 0,
            current_streak: 0,
            longest_streak: 0,
            last_activity: new Date().toISOString(),
            tier: 'free'
        };
        saveProfile();
    }
    checkStreak();
}

function checkStreak() {
    const lastDate = new Date(profile.last_activity).toDateString();
    const today = new Date().toDateString();
    const yesterday = new Date(Date.now() - 86400000).toDateString();

    if (lastDate === today) {
        // Streak already updated today
    } else if (lastDate === yesterday) {
        profile.current_streak++;
        if (profile.current_streak > profile.longest_streak) {
            profile.longest_streak = profile.current_streak;
        }
    } else {
        profile.current_streak = 1;
    }
    profile.last_activity = new Date().toISOString();
    saveProfile();
}

function saveProfile() {
    localStorage.setItem('skillbit_profile', JSON.stringify(profile));
    // Also update Supabase in real app
}

async function loadLessons() {
    try {
        const tracks = ['ail', 'cop', 'dig', 'ent', 'per', 'pub', 'uiu', 'web'];
        for (const t of tracks) {
            const response = await fetch(`../data/lessons_${t}.json`);
            const trackLessons = await response.json();
            lessons = [...lessons, ...trackLessons];
        }
    } catch (e) {
        console.error("Failed to load lessons", e);
    }
}

function initUI() {
    // Dashboard Logic
    if (document.getElementById('stats-streak')) {
        document.getElementById('stats-streak').innerText = profile.current_streak;
        document.getElementById('stats-xp').innerText = profile.xp_total;
        document.getElementById('stats-lessons').innerText = profile.lessons_completed;
        document.getElementById('user-level').innerText = calculateLevel(profile.xp_total);
    }

    // Library Logic
    const libraryGrid = document.getElementById('library-grid');
    if (libraryGrid) {
        const tracks = ['Web Dev', 'UI/UX Design', 'Digital Marketing', 'Personal Finance', 'Copywriting', 'Public Speaking', 'AI Literacy', 'Entrepreneurship'];
        tracks.forEach(track => {
            const card = document.createElement('div');
            card.className = 'track-card';
            card.innerHTML = `<h3>${track}</h3><p>10 Lessons</p>`;
            card.onclick = () => {
                localStorage.setItem('selected_track', track);
                window.location.href = 'lesson.html';
            };
            libraryGrid.appendChild(card);
        });
    }

    // Lesson Page Logic
    const lessonContainer = document.getElementById('lesson-viewer');
    if (lessonContainer) {
        const track = localStorage.getItem('selected_track') || 'Web Dev';
        const trackLessons = lessons.filter(l => l.track === track);
        // Pick first uncompleted lesson
        currentLesson = trackLessons[0]; // Simplified: always pick first for demo
        renderLesson();
    }
}

function calculateLevel(xp) {
    if (xp < 100) return 'Beginner';
    if (xp < 500) return 'Intermediate';
    if (xp < 2000) return 'Advanced';
    return 'Expert';
}

function renderLesson() {
    const viewer = document.getElementById('lesson-viewer');
    viewer.innerHTML = `
        <div class="lesson-content">
            <h2>${currentLesson.title}</h2>
            <p>${currentLesson.content}</p>
            <button class="btn btn-primary" style="margin-top:20px" onclick="startQuiz()">Start Quiz</button>
        </div>
    `;
}

function startQuiz() {
    const viewer = document.getElementById('lesson-viewer');
    let quizHtml = `<div class="card"><h2>Quiz</h2><div id="quiz-body">`;
    
    currentLesson.quiz.forEach((q, i) => {
        quizHtml += `
            <div class="quiz-question" id="q-${i}">
                <p><strong>Question ${i+1}:</strong> ${q.question}</p>
                <div class="options">
                    ${q.options.map((opt, optIdx) => `
                        <button class="option-btn" onclick="selectOption(${i}, '${opt}')">${opt}</button>
                    `).join('')}
                </div>
            </div>
        `;
    });

    quizHtml += `</div><button id="submit-quiz" class="btn btn-primary" onclick="submitQuiz()">Submit Answers</button></div>`;
    viewer.innerHTML = quizHtml;
}

const userAnswers = [];

function selectOption(qIdx, option) {
    userAnswers[qIdx] = option;
    const buttons = document.querySelectorAll(`#q-${qIdx} .option-btn`);
    buttons.forEach(btn => {
        btn.classList.remove('selected');
        if (btn.innerText === option) btn.classList.add('selected');
    });
}

async function submitQuiz() {
    let correct = 0;
    currentLesson.quiz.forEach((q, i) => {
        if (userAnswers[i] === q.answer) correct++;
    });

    const passed = correct >= 2;
    const xpEarned = passed ? currentLesson.xp : 0;

    if (passed) {
        profile.xp_total += xpEarned;
        profile.lessons_completed += 1;
        saveProfile();
    }

    const viewer = document.getElementById('lesson-viewer');
    viewer.innerHTML = `
        <div class="card text-center">
            <h2 style="color: ${passed ? '#A8E63D' : '#FF4B4B'}">${passed ? 'Success!' : 'Try Again'}</h2>
            <p>You got ${correct}/3 correct.</p>
            <p>XP Earned: ${xpEarned}</p>
            <div class="streak-flame">🔥 Streak: ${profile.current_streak}</div>
            <a href="dashboard.html" class="btn btn-primary" style="margin-top:20px">Back to Dashboard</a>
        </div>
    `;
}

function updateAuthUI(isLoggedIn) {
    const loginBtn = document.getElementById('login-btn');
    const userMenu = document.getElementById('user-menu');
    if (isLoggedIn) {
        if (loginBtn) loginBtn.style.display = 'none';
        if (userMenu) userMenu.style.display = 'block';
    } else {
        if (loginBtn) loginBtn.style.display = 'block';
        if (userMenu) userMenu.style.display = 'none';
    }
}

// Mock Auth Actions
function toggleAuth() {
    const modal = document.getElementById('auth-modal');
    modal.style.display = (modal.style.display === 'flex') ? 'none' : 'flex';
}

function mockLogin() {
    const email = document.getElementById('email').value;
    localStorage.setItem('sb-user', JSON.stringify({ id: 'u123', email: email }));
    window.location.reload();
}
