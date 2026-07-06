import SwiftUI

struct WelcomeView: View {
  @Binding var currentStep: Int
  
  var body: some View {
    VStack(spacing: 30) {
      Spacer()
      
      Image(systemName: "sparkles")
        .font(.system(size: 80))
        .foregroundStyle(.blue.gradient)
        .symbolEffect(.pulse)
      
      Text("Adaptive AI\nReminder Assistant")
        .font(.largeTitle)
        .fontWeight(.bold)
        .multilineTextAlignment(.center)
      
      Text("Powered by Apple Intelligence to learn your routines and help you remember what matters most, without you having to ask.")
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
      
      Spacer()
      
      Button {
        withAnimation {
          currentStep = 1
        }
      } label: {
        Text("Get Started")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding()
          .background(Color.blue)
          .foregroundColor(.white)
          .cornerRadius(15)
      }
      .padding(.horizontal, 40)
      .padding(.bottom, 50)
    }
  }
}
