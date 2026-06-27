/**
 * Orcinos Shared Supabase Client
 * 
 * Reusable Supabase initialization, authentication, and common data operations.
 * Used by: Hartaly, Skillbit, Slumber, Dricil
 * 
 * Usage:
 *   const db = new OrcinosDB({ url: '...', anonKey: '...' });
 *   await db.init();
 *   const user = await db.getCurrentUser();
 */

class OrcinosDB {
    constructor(config = {}) {
        this.url = config.url || '';
        this.anonKey = config.anonKey || '';
        this.client = null;
        this.currentUser = null;
    }

    init() {
        if (!this.url || !this.anonKey) {
            console.warn('[OrcinosDB] Supabase URL or key not configured.');
            return null;
        }

        if (typeof supabase !== 'undefined' && supabase.createClient) {
            this.client = supabase.createClient(this.url, this.anonKey);
        } else if (typeof createClient !== 'undefined') {
            this.client = createClient(this.url, this.anonKey);
        } else {
            console.warn('[OrcinosDB] Supabase library not loaded.');
            return null;
        }

        return this.client;
    }

    async getCurrentUser() {
        if (!this.client) return null;

        try {
            const { data: { user } } = await this.client.auth.getUser();
            this.currentUser = user;
            return user;
        } catch (error) {
            console.error('[OrcinosDB] Auth check failed:', error);
            return null;
        }
    }

    async signUp(email, password) {
        if (!this.client) return { user: null, error: 'Client not initialized' };
        const { data, error } = await this.client.auth.signUp({ email, password });
        return { user: data?.user, error };
    }

    async signIn(email, password) {
        if (!this.client) return { user: null, error: 'Client not initialized' };
        const { data, error } = await this.client.auth.signInWithPassword({ email, password });
        return { user: data?.user, error };
    }

    async signOut() {
        if (!this.client) return;
        await this.client.auth.signOut();
    }

    async fetchOne(table, filters = {}) {
        if (!this.client) return { data: null, error: 'Client not initialized' };
        let query = this.client.from(table).select('*');
        for (const [key, value] of Object.entries(filters)) {
            query = query.eq(key, value);
        }
        return await query.single();
    }

    async fetchMany(table, options = {}) {
        if (!this.client) return { data: null, error: 'Client not initialized' };
        const { filters = {}, orderBy = null, ascending = true, limit = null } = options;

        let query = this.client.from(table).select('*');
        for (const [key, value] of Object.entries(filters)) {
            query = query.eq(key, value);
        }
        if (orderBy) {
            query = query.order(orderBy, { ascending });
        }
        if (limit) {
            query = query.limit(limit);
        }
        return await query;
    }

    async insert(table, rows) {
        if (!this.client) return { data: null, error: 'Client not initialized' };
        return await this.client.from(table).insert(Array.isArray(rows) ? rows : [rows]);
    }

    async update(table, values, filters = {}) {
        if (!this.client) return { data: null, error: 'Client not initialized' };
        let query = this.client.from(table).update(values);
        for (const [key, value] of Object.entries(filters)) {
            query = query.eq(key, value);
        }
        return await query;
    }

    requireAuth(redirectPath = '/landing/index.html') {
        if (!this.currentUser) {
            if (!window.location.pathname.includes('landing') &&
                !window.location.pathname.includes('index.html')) {
                window.location.href = redirectPath;
            }
            return false;
        }
        return true;
    }
}

// Export for both module and script-tag usage
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { OrcinosDB };
}
