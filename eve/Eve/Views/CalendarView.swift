import SwiftUI

struct CalendarView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color(hex: "#4F83AB").ignoresSafeArea()
            
            GeometryReader { proxy in
                Ellipse()
                    .fill(Color(hex: "#E0ECF7"))
                    .frame(width: proxy.size.width * 2.5, height: proxy.size.height * 1.2)
                    .position(x: proxy.size.width / 2, y: -proxy.size.height * 0.1)
            }
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Bar
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 32) {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "chevron.backward.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(Color(hex: "#1D3557"))
                                .background(Circle().fill(Color.white))
                        }
                        
                        Text("Calendar")
                            .font(.system(size: 34, weight: .black, design: .default))
                            .foregroundColor(Color(hex: "#1D3557"))
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 32) {
                        Button(action: {}) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(Color(hex: "#1D3557"))
                                .background(Circle().fill(Color.white))
                        }
                        
                        Image(systemName: "calendar.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(Color(hex: "#1D3557"))
                            .background(Circle().fill(Color.white))
                            .offset(y: 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                // Calendar section title
                HStack {
                    Spacer()
                    Text("Today\nFriday, 5 July 2026")
                        .font(.system(size: 32, weight: .black, design: .default))
                        .foregroundColor(Color(hex: "#90B9DCCC"))
                        .multilineTextAlignment(.center)
                        .padding(.top, -10)
                    Spacer()
                }
                .padding(.horizontal, 24)
                
                Spacer().frame(height: 32)
                
                // Timeline Container
                ZStack(alignment: .top) {
                    Color(hex: "#1D3557")
                        .cornerRadius(32, corners: [.topLeft, .topRight])
                        .ignoresSafeArea(edges: .bottom)
                    
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer().frame(height: 30)
                            CalendarTimelineRow(time: "8.00 AM", isMainTime: true)
                            CalendarTimelineRow(time: "8.30 AM", title: "Go to the Office", subtitle: "Usually takes 20 minutes", isMainTime: false)
                            CalendarTimelineRow(time: "9.00 AM", isMainTime: true)
                            CalendarTimelineRow(time: "9.10 AM", title: "Meeting with Eve", subtitle: "Prepare charger", isMainTime: false, isImportant: true)
                            CalendarTimelineRow(time: "10.00 AM", isMainTime: true)
                            CalendarTimelineRow(time: "10.25 AM", title: "WFC in Max & Nine", subtitle: "Prepare earphones", isMainTime: false)
                            CalendarTimelineRow(time: "11.00 AM", isMainTime: true)
                            Spacer().frame(height: 40)
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }
}

struct CalendarTimelineRow: View {
    var time: String
    var title: String?
    var subtitle: String?
    var isMainTime: Bool
    var isImportant: Bool = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left Column: Time
            Text(time)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(isMainTime ? Color(hex: "#E8F3FF") : Color(hex: "#E8F3FF").opacity(0.5))
                .frame(width: 80, alignment: .trailing)
            
            // Timeline Center
            ZStack {
                Rectangle()
                    .fill(Color(hex: "#7AA0C3"))
                    .frame(width: 4)
                
                if title != nil {
                    Circle()
                        .fill(Color(hex: "#3FA9F5"))
                        .frame(width: 10, height: 10)
                }
            }
            .frame(width: 20)
            .padding(.horizontal, 8)
            
            // Right Column: Event Box
            if let title = title {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(hex: "#3FA9F5"))
                        .frame(width: 12, height: 1) // Connecting line
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 13, weight: isImportant ? .black : .bold))
                            .foregroundColor(Color(hex: "#E8F3FF"))
                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(hex: "#7AA0C3"))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "#1D3557"))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: "#3FA9F5"), lineWidth: 1)
                    )
                }
                .padding(.trailing, 24)
                .padding(.vertical, 8)
            } else {
                Spacer()
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minHeight: 60)
    }
}

#Preview {
    NavigationStack {
        CalendarView()
    }
}
