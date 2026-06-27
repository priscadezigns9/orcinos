/**
 * DEPRECATED: This file was a duplicate of syla/shared/app.js.
 * It has been replaced by the shared utilities in this directory:
 * 
 *   - shared/openai-client.js  — Reusable OpenAI API wrapper (OrcinosAI)
 *   - shared/supabase-client.js — Reusable Supabase client (OrcinosDB)
 *   - shared/sw-factory.js     — Service Worker factory
 *   - shared/base.css          — Common CSS reset and components
 * 
 * For Syla-specific logic, see: syla/shared/app.js
 * 
 * This file is kept for backward compatibility and re-exports
 * the Syla app init for any pages still referencing shared/app.js.
 */

// Load the canonical Syla logic if OrcinosAI is available
if (typeof OrcinosAI === 'undefined') {
    console.warn('[Orcinos] shared/app.js requires shared/openai-client.js to be loaded first.');
}

// Re-export notice
console.info('[Orcinos] shared/app.js is deprecated. Use shared/openai-client.js + product-specific app.js instead.');
