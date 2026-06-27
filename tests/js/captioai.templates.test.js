/**
 * Tests for CAPTION_TEMPLATES and HASHTAG_BANK from captioai/templates.js
 *
 * Validates structure, completeness, and data integrity of template data.
 */

const fs = require('fs');
const path = require('path');

// Load the templates file as raw text and evaluate the two exported objects
const fileContent = fs.readFileSync(
    path.join(__dirname, '../../captioai/templates.js'),
    'utf-8'
);

// Extract CAPTION_TEMPLATES and HASHTAG_BANK via Function constructor
const CAPTION_TEMPLATES = new Function(
    fileContent + '; return CAPTION_TEMPLATES;'
)();
const HASHTAG_BANK = new Function(
    fileContent + '; return HASHTAG_BANK;'
)();

const EXPECTED_PLATFORMS = ['Instagram', 'Threads', 'Facebook', 'Twitter', 'LinkedIn'];
const EXPECTED_TONES = ['Professional', 'Hype', 'Inspirational', 'Luxury', 'Spiritual'];

describe('captioai - CAPTION_TEMPLATES', () => {
    test('contains all expected platforms', () => {
        EXPECTED_PLATFORMS.forEach(platform => {
            expect(CAPTION_TEMPLATES).toHaveProperty(platform);
        });
    });

    test('each platform has all expected tones', () => {
        EXPECTED_PLATFORMS.forEach(platform => {
            EXPECTED_TONES.forEach(tone => {
                expect(CAPTION_TEMPLATES[platform]).toHaveProperty(tone);
            });
        });
    });

    test('each tone has at least 3 captions', () => {
        EXPECTED_PLATFORMS.forEach(platform => {
            EXPECTED_TONES.forEach(tone => {
                const captions = CAPTION_TEMPLATES[platform][tone];
                expect(Array.isArray(captions)).toBe(true);
                expect(captions.length).toBeGreaterThanOrEqual(3);
            });
        });
    });

    test('all captions are non-empty strings', () => {
        EXPECTED_PLATFORMS.forEach(platform => {
            EXPECTED_TONES.forEach(tone => {
                CAPTION_TEMPLATES[platform][tone].forEach(caption => {
                    expect(typeof caption).toBe('string');
                    expect(caption.trim().length).toBeGreaterThan(0);
                });
            });
        });
    });

    test('no duplicate captions within same platform/tone', () => {
        EXPECTED_PLATFORMS.forEach(platform => {
            EXPECTED_TONES.forEach(tone => {
                const captions = CAPTION_TEMPLATES[platform][tone];
                const unique = new Set(captions);
                expect(unique.size).toBe(captions.length);
            });
        });
    });
});

describe('captioai - HASHTAG_BANK', () => {
    test('contains all expected tones', () => {
        EXPECTED_TONES.forEach(tone => {
            expect(HASHTAG_BANK).toHaveProperty(tone);
        });
    });

    test('each tone has at least 10 hashtags', () => {
        EXPECTED_TONES.forEach(tone => {
            expect(HASHTAG_BANK[tone].length).toBeGreaterThanOrEqual(10);
        });
    });

    test('all hashtags are lowercase non-empty strings', () => {
        EXPECTED_TONES.forEach(tone => {
            HASHTAG_BANK[tone].forEach(tag => {
                expect(typeof tag).toBe('string');
                expect(tag.trim().length).toBeGreaterThan(0);
                expect(tag).toBe(tag.toLowerCase());
            });
        });
    });
});
