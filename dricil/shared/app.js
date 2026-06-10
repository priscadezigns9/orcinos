/**
 * Dricil App Logic
 * Autonomous AI Digital Agency Core
 */

const SUPABASE_URL = 'https://sktpjacowqaedddtrhuz.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNrdHBqYWNvd3FhZWRkZHRyaHV6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg2NDk5MzEsImV4cCI6MjA5NDIyNTkzMX0.FK4N_ATFTaUuGXrYu_7OBn3qCdlo0rOzxk-E6TxJxqs';

const dricilApp = {
    init() {
        console.log("Dricil Agency Activated.");
        this.checkSession();
    },

    getSupabase() {
        if (typeof createClient !== 'undefined') {
            return createClient(SUPABASE_URL, SUPABASE_KEY);
        }
        return null;
    },

    async checkSession() {
        const sb = this.getSupabase();
        if (!sb) return;
        const { data: { session } } = await sb.auth.getSession();
        if (session) {
            document.body.classList.add('logged-in');
        }
    },

    // Agency Services
    async getClients() {
        const sb = this.getSupabase();
        if (!sb) return [];
        const { data, error } = await sb
            .from('clients')
            .select('*')
            .order('name');
        return data || [];
    },

    async getContentQueue(clientId) {
        const sb = this.getSupabase();
        if (!sb) return [];
        const { data, error } = await sb
            .from('content_queue')
            .select('*')
            .eq('client_id', clientId)
            .order('scheduled_date', { ascending: true });
        return { data, error };
    },

    async getReports(clientId) {
        const sb = this.getSupabase();
        if (!sb) return [];
        const { data, error } = await sb
            .from('reports')
            .select('*')
            .eq('client_id', clientId)
            .order('created_at', { ascending: false });
        return { data, error };
    },

    async updateAutoPublish(clientId, status) {
        const sb = this.getSupabase();
        if (!sb) return;
        const { data, error } = await sb
            .from('clients')
            .update({ auto_publish: status })
            .eq('id', clientId);
        return { data, error };
    }
};

// Auto-init on load if libraries are present
document.addEventListener('DOMContentLoaded', () => {
    if (typeof createClient !== 'undefined') {
        dricilApp.init();
    }
});
