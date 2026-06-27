// Dricil Shared App Logic — uses shared OrcinosDB utility

const dricilDB = new OrcinosDB({
    url: '{{credential:supabase-project-url}}',
    anonKey: '{{credential:supabase-anon-key}}'
});

const dricilApp = {
    async init() {
        dricilDB.init();
    },

    async signUp(email, password) {
        return await dricilDB.signUp(email, password);
    },

    async signIn(email, password) {
        return await dricilDB.signIn(email, password);
    },

    async getClientProfile(userId) {
        return await dricilDB.fetchOne('clients', { user_id: userId });
    },

    async saveOnboarding(onboardingData) {
        return await dricilDB.insert('clients', onboardingData);
    },

    async getContentQueue(clientId) {
        return await dricilDB.fetchMany('content_queue', {
            filters: { client_id: clientId },
            orderBy: 'scheduled_date',
            ascending: true
        });
    },

    async getReports(clientId) {
        return await dricilDB.fetchMany('reports', {
            filters: { client_id: clientId },
            orderBy: 'created_at',
            ascending: false
        });
    },

    async updateAutoPublish(clientId, status) {
        return await dricilDB.update('clients', { auto_publish: status }, { id: clientId });
    },

    async runAutomationCycle(clientId) {
        console.log(`[DRICIL] Initiating Automation Cycle for Client: ${clientId}`);

        const { data: profile } = await this.getClientProfile(clientId);
        if (!profile) return { error: "Profile not found" };

        const contentJson = await dricilApi.generateSocialBatch(profile);
        if (!contentJson) return { error: "AI Generation failed" };

        try {
            const contentArray = JSON.parse(contentJson);
            const { error: insertError } = await dricilDB.insert(
                'content_queue',
                contentArray.map(item => ({
                    client_id: clientId,
                    platform: item.platform,
                    content_text: item.content_text,
                    scheduled_date: item.scheduled_date || new Date().toISOString(),
                    status: profile.auto_publish ? 'PUBLISHED' : 'PENDING'
                }))
            );

            return { success: !insertError, error: insertError };
        } catch (e) {
            return { error: "JSON Parse Error", raw: contentJson };
        }
    },

    async generateMarketingReport(clientId) {
        const { data: metrics } = await dricilDB.fetchMany('analytics', {
            filters: { client_id: clientId },
            limit: 30
        });

        const reportContent = await dricilApi.generateMonthlyReport(metrics);

        return await dricilDB.insert('reports', {
            client_id: clientId,
            title: `Marketing Report - ${new Date().toLocaleString('default', { month: 'long' })} 2026`,
            content: reportContent,
            type: 'MONTHLY'
        });
    }
};

// Auto-init on load if libraries are present
document.addEventListener('DOMContentLoaded', () => {
    dricilApp.init();
});
