/**
 * Tests for calculateSignature() from riddiim/player/neural_engine.js
 *
 * Pure data-classification function — no DOM, Web Audio, or browser dependencies.
 */

function calculateSignature(signalData) {
    if (signalData.length < 5) return 'UNKNOWN_SIGNAL';

    const avg = signalData.reduce((a, b) => a + b, 0) / signalData.length;

    if (avg < 15) return 'deep bass soul';
    if (avg < 40) return 'lo-fi acoustic chill';
    if (avg < 70) return 'synth pop wave';
    if (avg < 100) return 'vibrant afrobeat';
    return 'high frequency dance';
}

describe('riddiim - calculateSignature', () => {
    test('returns UNKNOWN_SIGNAL for fewer than 5 data points', () => {
        expect(calculateSignature([])).toBe('UNKNOWN_SIGNAL');
        expect(calculateSignature([10])).toBe('UNKNOWN_SIGNAL');
        expect(calculateSignature([1, 2, 3, 4])).toBe('UNKNOWN_SIGNAL');
    });

    test('returns "deep bass soul" for avg < 15', () => {
        expect(calculateSignature([5, 10, 8, 12, 10])).toBe('deep bass soul');
    });

    test('returns "lo-fi acoustic chill" for 15 <= avg < 40', () => {
        expect(calculateSignature([20, 25, 30, 35, 15])).toBe('lo-fi acoustic chill');
    });

    test('returns "synth pop wave" for 40 <= avg < 70', () => {
        expect(calculateSignature([50, 55, 60, 45, 65])).toBe('synth pop wave');
    });

    test('returns "vibrant afrobeat" for 70 <= avg < 100', () => {
        expect(calculateSignature([80, 85, 90, 75, 95])).toBe('vibrant afrobeat');
    });

    test('returns "high frequency dance" for avg >= 100', () => {
        expect(calculateSignature([120, 110, 105, 100, 115])).toBe('high frequency dance');
    });

    test('boundary: avg exactly 15', () => {
        expect(calculateSignature([15, 15, 15, 15, 15])).toBe('lo-fi acoustic chill');
    });

    test('boundary: avg exactly 40', () => {
        expect(calculateSignature([40, 40, 40, 40, 40])).toBe('synth pop wave');
    });

    test('boundary: avg exactly 70', () => {
        expect(calculateSignature([70, 70, 70, 70, 70])).toBe('vibrant afrobeat');
    });

    test('boundary: avg exactly 100', () => {
        expect(calculateSignature([100, 100, 100, 100, 100])).toBe('high frequency dance');
    });

    test('exactly 5 data points', () => {
        expect(calculateSignature([1, 2, 3, 4, 5])).toBe('deep bass soul');
    });

    test('large dataset', () => {
        const data = new Array(1000).fill(50);
        expect(calculateSignature(data)).toBe('synth pop wave');
    });
});
