import SwiftUI

struct WelcomeView: View {
    @Binding var currentStep: Int
    
    var body: some View {
        ZStack {
            Color(.textPrimary).ignoresSafeArea()
            
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 800, height: 500)
                .blur(radius: 100)
                .position(x: 200, y: 400)
                .ignoresSafeArea(edges: .all)
            
            // Decorative Background Bubbles
            GeometryReader { geometry in
                let ratioX = geometry.size.width / 402.0
                let ratioY = geometry.size.height / 874.0
                
                FloatingBubble1()
                    .position(x: (275 + 76/2) * ratioX, y: (190 + 62/2) * ratioY)
                FloatingBubble1()
                    .position(x: (275 + 76/2) * ratioX, y: (190 + 62/2) * ratioY)
                    .blur(radius: 10)
                
                FloatingBubble2()
                    .position(x: (23 + 76/2) * ratioX, y: (280 + 62/2) * ratioY)
                
                FloatingBubble2()
                    .position(x: (23 + 76/2) * ratioX, y: (280 + 62/2) * ratioY)
                    .blur(radius: 10)
                
                FloatingBubble2(scale: 0.85)
                    .position(x: (98 + 63/2) * ratioX, y: (170 + 52/2) * ratioY)
                
                FloatingBubble2(scale: 0.85)
                    .position(x: (98 + 63/2) * ratioX, y: (170 + 52/2) * ratioY)
                    .blur(radius: 10)
                
                // Robot Icon
                Image("Avatar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .position(x: (122 + 158/2) * ratioX, y: (242 + 158/2) * ratioY)
                
                // Text Area
                VStack(alignment: .leading, spacing: 10) {
                    Text("EVE")
                        .font(.system(size: 86, weight: .bold, design: .default))
                        .foregroundColor(Color(.textPrimary))
                        .position(x: (20 + 213/2) * ratioX, y: (350 + (86+163)/2) * ratioY)
                    
                    Text("Your adaptive routine companion")
                        .font(.system(size: 30, weight: .bold, design: .default))
                        .foregroundColor(Color(.textPrimary).opacity(0.59))
                        .fixedSize(horizontal: false, vertical: true)
                        .position(x: (75 + 213/2) * ratioX, y: (-5 + (86+163)/2) * ratioY)
                }
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
    
    
    struct FloatingBubble1: View {
        var scale: CGFloat = 1.0
        
        var body: some View {
            ZStack(alignment: .topLeading) {
                Circle().fill(Color.white).frame(width: 5, height: 5)
                    .offset(x: -10, y: 57)
                
                Circle().fill(Color.white).frame(width: 12, height: 12)
                    .offset(x: -5, y: 45)
                
                Ellipse().fill(Color.white).frame(width: 67, height: 54)
                    .offset(x: 0, y: 0)
            }
            .frame(width: 76, height: 62)
            .scaleEffect(scale)
        }
    }
    
    
    struct FloatingBubble2: View {
        var scale: CGFloat = 1.0
        
        var body: some View {
            ZStack(alignment: .topLeading) {
                Circle().fill(Color.white).frame(width: 5, height: 5)
                    .offset(x: 90, y: 57)
                
                Circle().fill(Color.white).frame(width: 12, height: 12)
                    .offset(x: 75, y: 45)
                
                Ellipse().fill(Color.white).frame(width: 67, height: 54)
                    .offset(x: 8.75, y: 0)
            }
            .frame(width: 76, height: 62)
            .scaleEffect(scale)
        }
    }
}

#Preview {
  WelcomeView(currentStep: .constant(0))
}
