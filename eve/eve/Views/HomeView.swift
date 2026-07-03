import SwiftUI

struct HomeView: View {
  @Bindable var viewModel = HomeViewModel()
  
  var body: some View {
    NavigationView {
      ScrollView {
        VStack(alignment: .leading, spacing: 25) {
          Text(viewModel.currentDate)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
          
          if !viewModel.predictedActivities.isEmpty {
            Text("Predicted Context")
              .font(.title2)
              .fontWeight(.bold)
              .padding(.horizontal)
            
            ForEach(viewModel.predictedActivities) { prediction in
              PredictionCard(prediction: prediction)
            }
          }
          
          if !viewModel.suggestedQuestions.isEmpty {
            Text("Clarification Needed")
              .font(.title2)
              .fontWeight(.bold)
              .padding(.horizontal)
              .padding(.top, 10)
            
            ForEach(viewModel.suggestedQuestions, id: \.self) { question in
              QuestionCard(question: question)
            }
          }
        }
        .padding(.vertical)
      }
      .navigationTitle("Assistant")
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          NavigationLink(destination: SettingsView()) {
            Image(systemName: "gearshape.fill")
          }
        }
        ToolbarItem(placement: .navigationBarLeading) {
          NavigationLink(destination: AITransparencyView()) {
            Image(systemName: "brain.head.profile")
          }
        }
      }
      .onAppear {
        viewModel.loadPredictions()
      }
    }
  }
}

struct PredictionCard: View {
  let prediction: Prediction
  
  var body: some View {
    HStack(spacing: 15) {
      Image(systemName: iconForType(prediction.type))
        .font(.title)
        .foregroundColor(.blue)
        .frame(width: 40)
      
      VStack(alignment: .leading, spacing: 5) {
        Text(prediction.suggestion)
          .font(.headline)
        Text(prediction.context)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      
      Spacer()
    }
    .padding()
    .background(.ultraThinMaterial)
    .cornerRadius(15)
    .padding(.horizontal)
  }
  
  func iconForType(_ type: Prediction.PredictionType) -> String {
    switch type {
    case .reminder: return "bell.fill"
    case .scheduleChange: return "calendar.badge.exclamationmark"
    case .insight: return "lightbulb.fill"
    }
  }
}

struct QuestionCard: View {
  let question: String
  
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(question)
        .font(.headline)
      
      HStack {
        Button("Yes") { }
          .buttonStyle(.borderedProminent)
          .tint(.blue)
        Button("No") { }
          .buttonStyle(.bordered)
          .foregroundColor(.primary)
      }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.blue.opacity(0.1))
    .cornerRadius(15)
    .padding(.horizontal)
  }
}
