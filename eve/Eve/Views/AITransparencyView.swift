import SwiftUI

struct AITransparencyView: View {
  @Bindable var viewModel = AITransparencyViewModel()
  
  var body: some View {
    List {
      Section(header: Text("Learned Patterns")) {
        if viewModel.patterns.isEmpty {
          Text("No patterns learned yet.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(viewModel.patterns) { pattern in
            PatternRow(pattern: pattern) {
              viewModel.ignorePattern(pattern)
            }
          }
          .onDelete(perform: viewModel.deletePattern)
        }
      }
      
      Section(footer: Text("Every correction improves future predictions. The AI relies entirely on on-device Apple Intelligence to ensure your privacy.")) {
        EmptyView()
      }
    }
    .navigationTitle("AI Knowledge")
  }
}

struct PatternRow: View {
  let pattern: RoutinePattern
  let onIgnore: () -> Void
  
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(pattern.title)
          .font(.headline)
        Spacer()
        Text("\(Int(pattern.confidence))% Conf.")
          .font(.caption)
          .foregroundColor(confidenceColor(pattern.confidence))
          .padding(4)
          .background(confidenceColor(pattern.confidence).opacity(0.2))
          .cornerRadius(4)
      }
      
      HStack {
        Label(pattern.patternType, systemImage: iconForType(pattern.patternType))
          .font(.caption)
          .foregroundStyle(.secondary)
        
        Spacer()
        
        Button("Incorrect") {
          withAnimation {
            onIgnore()
          }
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .tint(.red)
      }
    }
    .padding(.vertical, 4)
  }
  
  func iconForType(_ type: String) -> String {
    switch type {
    case "Location": return "location.fill"
    case "Time": return "clock.fill"
    case "Calendar": return "calendar"
    case "Context": return "link"
    default: return "sparkles"
    }
  }
  
  func confidenceColor(_ confidence: Double) -> Color {
    if confidence > 80 { return .green }
    if confidence > 50 { return .orange }
    return .red
  }
}

#Preview {
    AITransparencyView()
}
