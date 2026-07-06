import Foundation

struct Prediction: Identifiable, Hashable {
  let id = UUID()
  let suggestion: String
  let context: String
  let type: PredictionType
  let confidence: Double
  
  enum PredictionType: String, Hashable {
    case reminder = "Reminder"
    case scheduleChange = "Schedule Change"
    case insight = "Insight"
  }
}
