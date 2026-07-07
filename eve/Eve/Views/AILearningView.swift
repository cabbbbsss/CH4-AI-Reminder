import SwiftUI
import SwiftData

struct AILearningView: View {
  @Bindable var engine = AILearningEngine.shared
  @Binding var currentStep: Int
  @Environment(\.modelContext) private var modelContext
  
  var body: some View {
    VStack(spacing: 40) {
      Text("AI is Learning...")
        .font(.largeTitle)
        .fontWeight(.bold)
      
      ZStack {
        Circle()
          .stroke(Color.gray.opacity(0.2), lineWidth: 10)
          .frame(width: 200, height: 200)
        
        Circle()
          .trim(from: 0.0, to: CGFloat(engine.analysisProgress))
          .stroke(Color.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
          .frame(width: 200, height: 200)
          .rotationEffect(.degrees(-90))
          .animation(.spring(response: 0.6, dampingFraction: 0.8), value: engine.analysisProgress)
        
        Image(systemName: "brain.head.profile")
          .font(.system(size: 80))
          .foregroundStyle(.blue.gradient)
          .symbolEffect(.pulse, isActive: engine.isAnalyzing)
      }
      
      Text(engine.currentAnalysisTask)
        .font(.headline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .animation(.easeInOut, value: engine.currentAnalysisTask)
      
      if !engine.isAnalyzing && engine.analysisProgress == 1.0 {
        Button {
          PermissionManager.shared.completeOnboarding()
          withAnimation {
            currentStep = 3 // Go to Home
          }
        } label: {
          Text("Continue to Home")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(15)
        }
        .padding(.horizontal, 40)
        .transition(.opacity)
      }
    }
    .padding()
    .task {
      await engine.analyzeUserRoutines(context: modelContext)
    }
  }
}

#Preview {
    AILearningView(currentStep: .constant(2))
}
