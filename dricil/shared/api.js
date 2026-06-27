// Dricil OpenAI API Integration Layer - Optimized for June 2026

const API_CONFIG = {
    OPENAI_API_KEY: '{{credential:openai-vision-business-v3}}',
    BASE_URL: 'https://api.openai.com/v1'
};

const dricilApi = {
    async generateContent(prompt, model = "gpt-4o") {
        try {
            const response = await fetch(`${API_CONFIG.BASE_URL}/chat/completions`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${API_CONFIG.OPENAI_API_KEY}`
                },
                body: JSON.stringify({
                    model: model,
                    messages: [
                        { 
                            role: "system", 
                            content: `You are the Dricil AI Agency Engine. 
                            You specialize in fully automatic digital marketing for high-end brands.
                            Your outputs are professional, data-driven, and optimized for maximum conversion.
                            Current Date: June 19, 2026.`
                        },
                        { role: "user", content: prompt }
                    ],
                    temperature: 0.7
                })
            });

            if (!response.ok) {
                console.error("OpenAI API error:", response.status, response.statusText);
                return null;
            }
            const data = await response.json();
            if (data.error) {
                console.error("OpenAI Error:", data.error);
                return null;
            }
            if (!data.choices || !data.choices[0]) {
                console.error("Unexpected API response structure:", data);
                return null;
            }
            return data.choices[0].message.content;
        } catch (error) {
            console.error("API Call Failed:", error);
            return null;
        }
    },

    // 1. Social Media Content Logic
    async generateSocialBatch(clientProfile) {
        const prompt = `Generate a 7-day social media content calendar for ${clientProfile.business_name}.
        Industry: ${clientProfile.industry}.
        Tone: ${clientProfile.brand_voice}.
        Platforms: ${clientProfile.platforms.join(', ')}.
        Include captions, hashtag strategies (max 10), and visual descriptions.`;
        return await this.generateContent(prompt);
    },

    // 2. SEO & Keyword Intelligence Logic
    async performSEOAudit(domain) {
        const prompt = `Perform a virtual SEO audit for ${domain}. 
        Identify technical gaps, keyword opportunities for 2026, and a content cluster strategy.
        Format as a professional brief.`;
        return await this.generateContent(prompt);
    },

    // 3. High-Fidelity Copywriting Logic
    async generateCopy(type, details) {
        const prompt = `Generate high-conversion ${type} copy. 
        Details: ${details}. 
        Focus on psychological triggers and clear calls to action.`;
        return await this.generateContent(prompt);
    },

    // 4. Email Marketing Automation
    async generateEmailSequence(campaignGoal, targetAudience) {
        const prompt = `Generate a 5-email nurturing sequence.
        Goal: ${campaignGoal}.
        Audience: ${targetAudience}.
        Focus on high open rates and engagement.`;
        return await this.generateContent(prompt);
    },

    // 5. Ad Creative Logic
    async generateAdStrategy(product, platform) {
        const prompt = `Generate a creative ad strategy for ${product} on ${platform}.
        Include 3 different hook variations and visual storyboard concepts.`;
        return await this.generateContent(prompt);
    },

    // 6. Monthly Report Synthesis
    async generateMonthlyReport(metrics) {
        const prompt = `Synthesize a monthly marketing performance report based on these metrics: ${JSON.stringify(metrics)}.
        Provide insights, ROI analysis, and strategic pivots for next month.`;
        return await this.generateContent(prompt);
    },

    // 7. Competitor Monitoring Intelligence
    async analyzeCompetitor(competitorUrl, marketNiche) {
        const prompt = `Perform a competitive analysis on ${competitorUrl} within the ${marketNiche} niche.
        Identify their ad spend focus, content gaps we can exploit, and pricing strategy.`;
        return await this.generateContent(prompt);
    }
};
