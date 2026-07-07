import SwiftUI

struct WelcomeView: View {
    @Binding var currentStep: Int
    
    var body: some View {
        ZStack {
            Color(hex: "#E0ECF7").ignoresSafeArea()
            
            // Decorative Background Bubbles
            GeometryReader { geometry in
                let ratioX = geometry.size.width / 402.0
                let ratioY = geometry.size.height / 874.0
                
                FloatingBubble()
                    .position(x: (285 + 76/2) * ratioX, y: (198 + 62/2) * ratioY)
                
                FloatingBubble()
                    .position(x: (23 + 76/2) * ratioX, y: (290 + 62/2) * ratioY)
                
                FloatingBubble(scale: 0.85)
                    .position(x: (98 + 63/2) * ratioX, y: (186 + 52/2) * ratioY)
                
                // Robot Icon
                ZStack {
                    Circle().fill(Color.white).frame(width: 158, height: 158)
                        .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
                    
                    // Robot Face Inner
                    ZStack {
                        Circle().fill(Color(hex: "#1A1916")).frame(width: 120, height: 80)
                        
                        VStack(spacing: 8) {
                            HStack(spacing: 16) {
                                Capsule().fill(Color(hex: "#E0ECF7")).frame(width: 12, height: 8)
                                Capsule().fill(Color(hex: "#E0ECF7")).frame(width: 12, height: 8)
                            }
                            Capsule().fill(Color(hex: "#E0ECF7")).frame(width: 30, height: 6)
                        }
                    }
                }
                .position(x: (122 + 158/2) * ratioX, y: (242 + 158/2) * ratioY)
                
                // Text Area
                VStack(alignment: .leading, spacing: 10) {
                    Text("EVE")
                        .font(.system(size: 86, weight: .black, design: .default))
                        .foregroundColor(Color(hex: "#19355E"))
                    
                    Text("Your adaptive routine companion")
                        .font(.system(size: 30, weight: .black, design: .default))
                        .foregroundColor(Color(hex: "#1D3557").opacity(0.59))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .position(x: (62 + 213/2) * ratioX, y: (426 + (86+163)/2) * ratioY)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation {
                    currentStep = 1
                }
            }
        }
    }
}

struct FloatingBubble: View {
    var scale: CGFloat = 1.0
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Circle().fill(Color.white).frame(width: 5, height: 5)
                .offset(x: 0, y: 57)
            
            Circle().fill(Color.white).frame(width: 12, height: 12)
                .offset(x: 5, y: 45)
            
            Ellipse().fill(Color.white).frame(width: 67, height: 54)
                .offset(x: 8.75, y: 0)
        }
        .frame(width: 76, height: 62)
        .scaleEffect(scale)
    }
}
