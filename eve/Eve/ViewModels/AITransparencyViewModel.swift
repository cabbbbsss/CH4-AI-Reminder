import Foundation
import Observation
import SwiftUI

@Observable
final class AITransparencyViewModel {
  var patterns: [RoutinePattern] = []
  
  init() {
    fetchPatterns()
  }
  
  func fetchPatterns() {
    // In a real app with SwiftData, this could use a @Query in the View or fetch from ModelContext.
    // For the mock/prototype UI state:
    patterns = [
      RoutinePattern(title: "Leaves home around 7:20 AM", patternType: "Location", confidence: 92.0, frequency: 14),
      RoutinePattern(title: "Usually forgets charger", patternType: "Context", confidence: 61.0, frequency: 4),
      RoutinePattern(title: "Gym every Tuesday", patternType: "Calendar", confidence: 88.0, frequency: 10)
    ]
  }
  
  func deletePattern(at offsets: IndexSet) {
    patterns.remove(atOffsets: offsets)
    // In a real app, delete from SwiftData
  }
  
  func ignorePattern(_ pattern: RoutinePattern) {
    if let index = patterns.firstIndex(where: { $0.id == pattern.id }) {
      patterns.remove(at: index)
    }
  }
}
