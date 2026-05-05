//
//  RoastHeatService.swift
//  thebitbinder
//
//  Single source of truth for per-target heat. Pure function over RoastTarget
//  snapshot data — no persistence. Powers the heat bar, ranking, warming
//  state, and header copy in Roast Mode v2.
//

import Foundation

struct HeatInputs {
    let bitCount: Int
    let recentPracticeDays: Int   // unique practice days in last 7
    let lastHitDaysAgo: Int       // days since last "killer" performance, 999 if never
    let daysSinceUsed: Int        // days since any joke updated/performed
}

enum RoastHeatService {
    /// Heat in 0..100. Spec formula:
    /// `bits*4 + recentPracticeDays*8 + (lastHitDaysAgo<=3 ? 20 : 0) - daysSinceUsed*2`
    static func heat(for inputs: HeatInputs) -> Int {
        let raw = inputs.bitCount * 4
            + inputs.recentPracticeDays * 8
            + (inputs.lastHitDaysAgo <= 3 ? 20 : 0)
            - inputs.daysSinceUsed * 2
        return min(100, max(0, raw))
    }

    /// Convenience: derives `HeatInputs` from a `RoastTarget` snapshot.
    static func heat(for target: RoastTarget) -> Int {
        guard target.isValid, let jokes = target.jokes else { return 0 }
        let active = jokes.filter { !$0.isTrashed }
        let bits = active.count
        let now = Date()
        let cal = Calendar.current

        // Distinct days in last 7 with any performance recorded
        let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: now) ?? now
        let recentDays = Set(active.compactMap { joke -> Date? in
            guard let last = joke.lastPerformedDate, last >= sevenDaysAgo else { return nil }
            return cal.startOfDay(for: last)
        }).count

        // Days since most recent killer performance
        let lastKillerHit = active
            .filter { $0.isKiller }
            .compactMap { $0.lastPerformedDate }
            .max()
        let lastHitDaysAgo: Int = {
            guard let d = lastKillerHit else { return 999 }
            return cal.dateComponents([.day], from: d, to: now).day ?? 999
        }()

        // Days since any interaction (jokes or target itself)
        let lastTouch = max(
            target.dateModified,
            active.map { max($0.dateModified, $0.lastPerformedDate ?? .distantPast) }.max() ?? .distantPast
        )
        let daysSinceUsed = cal.dateComponents([.day], from: lastTouch, to: now).day ?? 0

        return heat(for: HeatInputs(
            bitCount: bits,
            recentPracticeDays: recentDays,
            lastHitDaysAgo: lastHitDaysAgo,
            daysSinceUsed: max(0, daysSinceUsed)
        ))
    }
}

/// Warming state for the Roast list bg + count copy.
enum WarmingState {
    case cold, warm, hot

    static func state(targetCount: Int, maxHeat: Int) -> WarmingState {
        if targetCount == 0 { return .cold }
        return maxHeat >= 60 ? .hot : .warm
    }
}
