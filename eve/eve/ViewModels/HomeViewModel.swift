import Foundation
import Observation

@Observable
final class HomeViewModel {
  var currentDate: String = ""
  var predictedActivities: [Prediction] = []
  var suggestedQuestions: [String] = []
  
  init() {
    updateDate()
  }
  
  func updateDate() {
    let formatter = DateFormatter()
    formatter.dateStyle = .full
    self.currentDate = formatter.string(from: Date())
  }
  
  func loadPredictions() {
    self.predictedActivities = AILearningEngine.shared.predictedActivities
    self.suggestedQuestions = AILearningEngine.shared.suggestedQuestions
  }
}
