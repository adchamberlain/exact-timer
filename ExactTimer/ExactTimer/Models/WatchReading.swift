import Foundation
import SwiftData

/// A single accuracy measurement comparing watch time to NTP time
@Model
final class WatchReading {
    var id: UUID

    /// The watch this reading belongs to
    var watch: Watch?

    /// When the reading was captured (NTP-accurate reference time)
    var capturedAt: Date

    /// The time shown on the mechanical watch
    var watchHour: Int
    var watchMinute: Int
    var watchSecond: Int

    /// The deviation in seconds (positive = watch is fast, negative = watch is slow)
    var deviationSeconds: Double

    /// Running total of deviation for trend calculation
    var cumulativeDeviation: Double

    /// Confidence score from ML model (0-1)
    var confidenceScore: Double?

    /// Optional photo of this reading
    @Attribute(.externalStorage)
    var photoData: Data?

    /// Whether the user manually adjusted the ML prediction
    var wasManuallyAdjusted: Bool = false

    init(
        watch: Watch,
        capturedAt: Date,
        watchHour: Int,
        watchMinute: Int,
        watchSecond: Int,
        referenceTime: Date,
        previousCumulativeDeviation: Double = 0
    ) {
        self.id = UUID()
        self.watch = watch
        self.capturedAt = capturedAt
        self.watchHour = watchHour
        self.watchMinute = watchMinute
        self.watchSecond = watchSecond

        // Calculate deviation
        let watchTime = Self.timeToSeconds(hour: watchHour, minute: watchMinute, second: watchSecond)
        let refComponents = Calendar.current.dateComponents([.hour, .minute, .second], from: referenceTime)
        let refTime = Self.timeToSeconds(
            hour: refComponents.hour ?? 0,
            minute: refComponents.minute ?? 0,
            second: refComponents.second ?? 0
        )

        // Handle wrap-around (e.g., watch shows 11:59:50, reference is 12:00:10)
        var deviation = Double(watchTime - refTime)
        if deviation > 43200 { // More than 12 hours
            deviation -= 86400
        } else if deviation < -43200 {
            deviation += 86400
        }

        self.deviationSeconds = deviation
        self.cumulativeDeviation = previousCumulativeDeviation + deviation
    }

    /// Convert time components to seconds since midnight
    private static func timeToSeconds(hour: Int, minute: Int, second: Int) -> Int {
        return hour * 3600 + minute * 60 + second
    }

    /// Formatted watch time string
    var watchTimeString: String {
        String(format: "%d:%02d:%02d", watchHour, watchMinute, watchSecond)
    }

    /// Formatted deviation string
    var deviationString: String {
        let absDeviation = abs(deviationSeconds)
        let sign = deviationSeconds >= 0 ? "+" : "-"

        if absDeviation < 60 {
            return String(format: "%@%.1fs", sign, absDeviation)
        } else {
            let minutes = Int(absDeviation) / 60
            let seconds = absDeviation.truncatingRemainder(dividingBy: 60)
            return String(format: "%@%dm %.1fs", sign, minutes, seconds)
        }
    }
}
