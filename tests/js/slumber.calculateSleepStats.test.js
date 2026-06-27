/**
 * Tests for calculateSleepStats() from slumber/shared/app.js
 *
 * Pure computation — no DOM or network dependencies.
 */

function calculateSleepStats(bedtimeStr, wakeTimeStr) {
    const bedtime = new Date(bedtimeStr);
    const wakeTime = new Date(wakeTimeStr);

    let durationMs = wakeTime - bedtime;
    if (durationMs < 0) { // Crossed midnight
        durationMs += 24 * 60 * 60 * 1000;
    }

    const durationMins = Math.floor(durationMs / 60000);
    const durationHrs = durationMins / 60;

    let baseScore = (durationHrs >= 7 && durationHrs <= 9)
        ? 100
        : (durationHrs < 7 ? (durationHrs / 7) * 100 : (9 / durationHrs) * 100);

    return {
        durationMins,
        efficiencyScore: Math.min(100, Math.round(baseScore))
    };
}

describe('slumber - calculateSleepStats', () => {
    test('8 hours of sleep gives 100% efficiency', () => {
        const result = calculateSleepStats(
            '2026-06-27T22:00:00',
            '2026-06-28T06:00:00'
        );
        expect(result.durationMins).toBe(480); // 8 hours
        expect(result.efficiencyScore).toBe(100);
    });

    test('7 hours of sleep gives 100% efficiency', () => {
        const result = calculateSleepStats(
            '2026-06-27T23:00:00',
            '2026-06-28T06:00:00'
        );
        expect(result.durationMins).toBe(420);
        expect(result.efficiencyScore).toBe(100);
    });

    test('9 hours of sleep gives 100% efficiency', () => {
        const result = calculateSleepStats(
            '2026-06-27T21:00:00',
            '2026-06-28T06:00:00'
        );
        expect(result.durationMins).toBe(540);
        expect(result.efficiencyScore).toBe(100);
    });

    test('5 hours of sleep gives reduced score', () => {
        const result = calculateSleepStats(
            '2026-06-28T01:00:00',
            '2026-06-28T06:00:00'
        );
        expect(result.durationMins).toBe(300);
        // 5/7 * 100 ≈ 71
        expect(result.efficiencyScore).toBe(71);
    });

    test('11 hours of sleep gives reduced score', () => {
        const result = calculateSleepStats(
            '2026-06-27T19:00:00',
            '2026-06-28T06:00:00'
        );
        expect(result.durationMins).toBe(660);
        // 9/11 * 100 ≈ 82
        expect(result.efficiencyScore).toBe(82);
    });

    test('handles midnight crossing (same-day timestamps)', () => {
        // When wake time appears earlier than bed time on same date,
        // the function adds 24h to correct: 01:00 - 23:00 = -22h + 24h = 2h
        const result = calculateSleepStats(
            '2026-06-27T23:00:00',
            '2026-06-27T01:00:00'
        );
        expect(result.durationMins).toBe(120); // 2 hours
    });

    test('normal overnight sleep with correct dates', () => {
        // bedtime 11pm June 27, wake 7am June 28 => 8 hours
        const result = calculateSleepStats(
            '2026-06-27T23:00:00',
            '2026-06-28T07:00:00'
        );
        expect(result.durationMins).toBe(480);
        expect(result.efficiencyScore).toBe(100);
    });

    test('zero duration sleep', () => {
        const result = calculateSleepStats(
            '2026-06-28T06:00:00',
            '2026-06-28T06:00:00'
        );
        expect(result.durationMins).toBe(0);
        expect(result.efficiencyScore).toBe(0);
    });
});
