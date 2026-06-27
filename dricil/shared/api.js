// Dricil OpenAI API Integration Layer — uses shared OrcinosAI utility

const dricilAI = new OrcinosAI({
    apiKey: '{{credential:openai-vision-business-v3}}',
    model: 'gpt-4o',
    temperature: 0.7
});

const DRICIL_SYSTEM_PROMPT = `You are the Dricil AI Agency Engine. 
You specialize in fully automatic digital marketing for high-end brands.
Your outputs are professional, data-driven, and optimized for maximum conversion.
Current Date: ${new Date().toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })}.`;

const dricilApi = {
    async generateContent(prompt, model = "gpt-4o") {
        return await dricilAI.chat(prompt, {
            systemPrompt: DRICIL_SYSTEM_PROMPT,
            model
        });
    },

    async generateSocialBatch(clientProfile) {
        const prompt = `Generate a 7-day social media content calendar for ${clientProfile.business_name}.
        Industry: ${clientProfile.industry}.
        Tone: ${clientProfile.brand_voice}.
        Platforms: ${clientProfile.platforms.join(', ')}.
        Include captions, hashtag strategies (max 10), and visual descriptions.`;
        return await this.generateContent(prompt);
    },

    async performSEOAudit(domain) {
        const prompt = `Perform a virtual SEO audit for ${domain}. 
        Identify technical gaps, keyword opportunities for 2026, and a content cluster strategy.
        Format as a professional brief.`;
        return await this.generateContent(prompt);
    },

    async generateCopy(type, details) {
        const prompt = `Generate high-conversion ${type} copy. 
        Details: ${details}. 
        Focus on psychological triggers and clear calls to action.`;
        return await this.generateContent(prompt);
    },

    async generateEmailSequence(campaignGoal, targetAudience) {
        const prompt = `Generate a 5-email nurturing sequence.
        Goal: ${campaignGoal}.
        Audience: ${targetAudience}.
        Focus on high open rates and engagement.`;
        return await this.generateContent(prompt);
    },

    async generateAdStrategy(product, platform) {
        const prompt = `Generate a creative ad strategy for ${product} on ${platform}.
        Include 3 different hook variations and visual storyboard concepts.`;
        return await this.generateContent(prompt);
    },

    async generateMonthlyReport(metrics) {
        const prompt = `Synthesize a monthly marketing performance report based on these metrics: ${JSON.stringify(metrics)}.
        Provide insights, ROI analysis, and strategic pivots for next month.`;
        return await this.generateContent(prompt);
    },

    async analyzeCompetitor(competitorUrl, marketNiche) {
        const prompt = `Perform a competitive analysis on ${competitorUrl} within the ${marketNiche} niche.
        Identify their ad spend focus, content gaps we can exploit, and pricing strategy.`;
        return await this.generateContent(prompt);
    }
};
