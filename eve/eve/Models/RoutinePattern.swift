import Foundation
import SwiftData

@Model
final class RoutinePattern {
  var id: UUID
  var title: String
  var patternType: String // "Location", "Time", "Calendar"
  var confidence: Double // 0.0 to 100.0
  var frequency: Int
  var lastObserved: Date
  var suggestedAction: String?
  var isUserVerified: Bool
  
  init(id: UUID = UUID(), title: String, patternType: String, confidence: Double, frequency: Int, lastObserved: Date = Date(), suggestedAction: String? = nil, isUserVerified: Bool = false) {
    self.id = id
    self.title = title
    self.patternType = patternType
    self.confidence = confidence
    self.frequency = frequency
    self.lastObserved = lastObserved
    self.suggestedAction = suggestedAction
    self.isUserVerified = isUserVerified
  }
}
