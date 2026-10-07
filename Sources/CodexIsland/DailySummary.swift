import Foundation

struct DailySummary {
    let turns: String
    let duration: String
    let sentence: String

    init(stats: DailyStats) {
        let count = max(0, stats.completedTurns)
        turns = "\(count.formatted()) \(count == 1 ? "turn" : "turns")"
        let seconds = stats.activeDuration.isFinite ? max(0, stats.activeDuration) : 0
        let minutes = Int(min(seconds / 60, 1440))
        if seconds > 0 && minutes == 0 { duration = "less than 1 min" }
        else if minutes < 60 { duration = "\(minutes.formatted()) \(minutes == 1 ? "min" : "mins")" }
        else {
            let hours = minutes / 60, remainder = minutes % 60
            duration = "\(hours.formatted()) \(hours == 1 ? "hr" : "hrs")" +
                (remainder == 0 ? "" : " \(remainder.formatted()) \(remainder == 1 ? "min" : "mins")")
        }
        sentence = "You completed \(turns) today and were active for about \(duration)."
    }
}
