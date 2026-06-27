/**
 * Orcinos Shared OpenAI Client
 * 
 * Reusable wrapper for OpenAI Chat Completions API.
 * Used by: Syla, Hartaly, Slumber, Dricil
 * 
 * Usage:
 *   const ai = new OrcinosAI({ apiKey: 'sk-...' });
 *   const reply = await ai.chat('Hello', { systemPrompt: '...' });
 */

class OrcinosAI {
    constructor(config = {}) {
        this.apiKey = config.apiKey || '';
        this.baseUrl = config.baseUrl || 'https://api.openai.com/v1';
        this.defaultModel = config.model || 'gpt-4o-mini';
        this.defaultTemperature = config.temperature ?? 0.7;
    }

    setApiKey(key) {
        this.apiKey = key;
    }

    async chat(userMessage, options = {}) {
        const {
            systemPrompt = 'You are a helpful assistant.',
            model = this.defaultModel,
            temperature = this.defaultTemperature,
            maxTokens = null,
            history = [],
            errorMessage = 'Something went wrong. Please try again.'
        } = options;

        if (!this.apiKey) {
            return options.noKeyMessage || 'API key not configured. Please set up your OpenAI key.';
        }

        const messages = [
            { role: 'system', content: systemPrompt },
            ...history,
            { role: 'user', content: userMessage }
        ];

        const body = {
            model,
            messages,
            temperature
        };

        if (maxTokens) {
            body.max_tokens = maxTokens;
        }

        try {
            const response = await fetch(`${this.baseUrl}/chat/completions`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${this.apiKey}`
                },
                body: JSON.stringify(body)
            });

            const data = await response.json();

            if (data.error) {
                console.error('[OrcinosAI] API Error:', data.error);
                return null;
            }

            return data.choices[0].message.content;
        } catch (error) {
            console.error('[OrcinosAI] Request failed:', error);
            return errorMessage;
        }
    }
}

// Export for both module and script-tag usage
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { OrcinosAI };
}
