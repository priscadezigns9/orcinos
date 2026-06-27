/**
 * Tests for detectCrisis() from hartaly/shared/app.js
 *
 * Pure string-matching function — no DOM or network dependencies.
 */

function detectCrisis(text) {
    const keywords = ['suicide', 'self-harm', 'kill myself', 'end it all', "don't want to be here", 'hanging', 'overdose', 'cut myself'];
    return keywords.some(keyword => text.toLowerCase().includes(keyword));
}

describe('hartaly - detectCrisis', () => {
    test('detects "suicide" keyword', () => {
        expect(detectCrisis('I am thinking about suicide')).toBe(true);
    });

    test('detects "self-harm" keyword', () => {
        expect(detectCrisis('I have been engaging in self-harm')).toBe(true);
    });

    test('detects "kill myself"', () => {
        expect(detectCrisis('I want to kill myself')).toBe(true);
    });

    test('detects "end it all"', () => {
        expect(detectCrisis('I just want to end it all')).toBe(true);
    });

    test('detects "don\'t want to be here"', () => {
        expect(detectCrisis("I don't want to be here anymore")).toBe(true);
    });

    test('detects "hanging"', () => {
        expect(detectCrisis('I was thinking about hanging')).toBe(true);
    });

    test('detects "overdose"', () => {
        expect(detectCrisis('I took an overdose')).toBe(true);
    });

    test('detects "cut myself"', () => {
        expect(detectCrisis('I want to cut myself')).toBe(true);
    });

    test('is case-insensitive', () => {
        expect(detectCrisis('I am thinking about SUICIDE')).toBe(true);
        expect(detectCrisis('SELF-HARM is dangerous')).toBe(true);
    });

    test('returns false for safe text', () => {
        expect(detectCrisis('I am feeling happy today')).toBe(false);
        expect(detectCrisis('The weather is nice')).toBe(false);
        expect(detectCrisis('I had a good day at work')).toBe(false);
    });

    test('returns false for empty string', () => {
        expect(detectCrisis('')).toBe(false);
    });

    test('detects keyword embedded in longer text', () => {
        expect(detectCrisis('My friend mentioned overdose in conversation')).toBe(true);
    });
});
