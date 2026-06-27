// Dricil Shared App Logic (Supabase + Auth)

const CONFIG = {
    SUPABASE_URL: '{{credential:supabase-project-url}}',
    SUPABASE_ANON_KEY: '{{credential:supabase-anon-key}}'
};

// Initialize Supabase Client (Assuming supabase.js is loaded via CDN)
let supabase;
if (typeof supabase !== 'undefined') {
    // This would be initialized if the script is loaded
}

const dricilApp = {
    async init() {
        if (typeof createClient !== 'undefined') {
            supabase = createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY);
        }
    },

    async signUp(email, password) {
        const { user, error } = await supabase.auth.signUp({ email, password });
        return { user, error };
    },

    async signIn(email, password) {
        const { user, error } = await supabase.auth.signIn({ email, password });
        return { user, error };
    },

    async getClientProfile(userId) {
        const { data, error } = await supabase
            .from('clients')
            .select('*')
            .eq('user_id', userId)
            .single();
        return { data, error };
    },

    async saveOnboarding(onboardingData) {
        const { data, error } = await supabase
            .from('clients')
            .insert([onboardingData]);
        return { data, error };
    },

    async getContentQueue(clientId) {
        const { data, error } = await supabase
            .from('content_queue')
            .select('*')
            .eq('client_id', clientId)
            .order('scheduled_date', { ascending: true });
        return { data, error };
    },

    async getReports(clientId) {
        const { data, error } = await supabase
            .from('reports')
            .select('*')
            .eq('client_id', clientId)
            .order('created_at', { ascending: false });
        return { data, error };
    },

    async updateAutoPublish(clientId, status) {
        const { data, error } = await supabase
            .from('clients')
            .update({ auto_publish: status })
            .eq('id', clientId);
        return { data, error };
    },

    // Bridge Logic: Orchestrate AI Automation
    async runAutomationCycle(clientId) {
        console.log(`[DRICIL] Initiating Automation Cycle for Client: ${clientId}`);
        
        // 1. Fetch Profile
        const { data: profile, error: profileError } = await this.getClientProfile(clientId);
        if (profileError) {
            console.error("Failed to fetch client profile:", profileError);
            return { error: "Profile lookup failed: " + profileError.message };
        }
        if (!profile) return { error: "Profile not found" };

        // 2. Generate Content Batch via dricilApi
        const contentJson = await dricilApi.generateSocialBatch(profile);
        if (!contentJson) return { error: "AI Generation failed" };

        try {
            const contentArray = JSON.parse(contentJson);
            // 3. Save to Supabase Queue
            const { error: insertError } = await supabase
                .from('content_queue')
                .insert(contentArray.map(item => ({
                    client_id: clientId,
                    platform: item.platform,
                    content_text: item.content_text,
                    scheduled_date: item.scheduled_date || new Date().toISOString(),
                    status: profile.auto_publish ? 'PUBLISHED' : 'PENDING'
                })));
            
            return { success: !insertError, error: insertError };
        } catch (e) {
            return { error: "JSON Parse Error", raw: contentJson };
        }
    },

    async generateMarketingReport(clientId) {
        try {
            // Fetch recent metrics from Supabase
            const { data: metrics, error: metricsError } = await supabase
                .from('analytics')
                .select('*')
                .eq('client_id', clientId)
                .limit(30);

            if (metricsError) {
                console.error("Failed to fetch analytics:", metricsError);
                return { data: null, error: metricsError };
            }

            const reportContent = await dricilApi.generateMonthlyReport(metrics);
            if (!reportContent) {
                return { data: null, error: "AI report generation failed" };
            }

            // Save report to Supabase
            const { data, error } = await supabase
                .from('reports')
                .insert([{
                    client_id: clientId,
                    title: `Marketing Report - ${new Date().toLocaleString('default', { month: 'long' })} 2026`,
                    content: reportContent,
                    type: 'MONTHLY'
                }]);

            return { data, error };
        } catch (error) {
            console.error("Marketing report generation failed:", error);
            return { data: null, error: error.message };
        }
    }
};

// Auto-init on load if libraries are present
document.addEventListener('DOMContentLoaded', () => {
    if (typeof createClient !== 'undefined') {
        dricilApp.init();
    }
});
