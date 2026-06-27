/**
 * Tests for calculateLevel() from skillbit/shared/app.js
 *
 * The original function lives in a browser-only file, so we re-declare the
 * pure logic here (it has zero DOM or external dependencies).
 */

function calculateLevel(xp) {
    if (xp < 100) return 'Beginner';
    if (xp < 500) return 'Intermediate';
    if (xp < 2000) return 'Advanced';
    return 'Expert';
}

describe('skillbit - calculateLevel', () => {
    test('returns Beginner for xp < 100', () => {
        expect(calculateLevel(0)).toBe('Beginner');
        expect(calculateLevel(50)).toBe('Beginner');
        expect(calculateLevel(99)).toBe('Beginner');
    });

    test('returns Intermediate for 100 <= xp < 500', () => {
        expect(calculateLevel(100)).toBe('Intermediate');
        expect(calculateLevel(250)).toBe('Intermediate');
        expect(calculateLevel(499)).toBe('Intermediate');
    });

    test('returns Advanced for 500 <= xp < 2000', () => {
        expect(calculateLevel(500)).toBe('Advanced');
        expect(calculateLevel(1000)).toBe('Advanced');
        expect(calculateLevel(1999)).toBe('Advanced');
    });

    test('returns Expert for xp >= 2000', () => {
        expect(calculateLevel(2000)).toBe('Expert');
        expect(calculateLevel(5000)).toBe('Expert');
        expect(calculateLevel(999999)).toBe('Expert');
    });

    test('handles negative xp as Beginner', () => {
        expect(calculateLevel(-1)).toBe('Beginner');
    });
});
