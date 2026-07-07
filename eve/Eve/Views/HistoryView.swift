import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color(hex: "#E0ECF7").ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Nav
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.backward.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(Color(hex: "#1D3557"))
                            .background(Circle().fill(Color.white))
                    }
                    
                    Text("History")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.leading, 12)
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                // Character + Chat Bubble
                HStack(alignment: .center, spacing: 16) {
                    // Robot Face Group
                    ZStack {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 79, height: 79)
                        
                        Circle()
                            .fill(Color.white)
                            .frame(width: 70, height: 70)
                        
                        // Screen
                        Ellipse()
                            .fill(Color(hex: "#1A1916"))
                            .frame(width: 54, height: 36)
                            .offset(y: -2)
                        
                        // Face details
                        VStack(spacing: 4) {
                            HStack(spacing: 14) {
                                Ellipse().fill(Color(hex: "#E0ECF7")).frame(width: 5, height: 3)
                                Ellipse().fill(Color(hex: "#E0ECF7")).frame(width: 5, height: 3)
                            }
                            Rectangle().fill(Color(hex: "#E0ECF7")).frame(width: 13, height: 2)
                        }
                        .offset(y: -2)
                    }
                    
                    // Chat Bubble
                    ZStack(alignment: .leading) {
                        // The triangle pointing left
                        Path { path in
                            path.move(to: CGPoint(x: 10, y: 15))
                            path.addLine(to: CGPoint(x: 0, y: 25))
                            path.addLine(to: CGPoint(x: 10, y: 35))
                        }
                        .fill(Color.white)
                        .offset(x: -8)
                        
                        Text("I learn from your interactions and adaptively remind you.")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "#1D3557"))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .cornerRadius(12)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)
                
                // Timeline
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        HistoryTimelineRow(
                            dateLabel: "Today",
                            timeLabel: "8.00\nAM",
                            isExpanded: true,
                            title: "Notification Response",
                            bodyText: "You answered: “I’ll be at the Office.”\nEVE confirmed: “Routine updated”\nEVE confirmed: “Feed dog.“",
                            insightTitle: "Learning Insight:",
                            insightBody: "EVE learned: User prefers Office routine on Monday mornings"
                        )
                        
                        HistoryTimelineRow(
                            timeLabel: "9.00\nAM",
                            isExpanded: true,
                            title: "Pattern Confirmation",
                            bodyText: "You confirmed: “Bring Charger”\nEVE confirmed: “Routine Updated”",
                            insightBody: "EVE updated: “Bring Charger” is a preferred task when visiting Downtown."
                        )
                        
                        HistoryTimelineRow(
                            timeLabel: "10.00\nAM",
                            isExpanded: false,
                            title: "New Data Pick-Up"
                        )
                        
                        HistoryTimelineRow(
                            timeLabel: "11.00\nAM",
                            isExpanded: false,
                            title: "Pattern Confirmation"
                        )
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }
}

struct HistoryTimelineRow: View {
    var dateLabel: String?
    var timeLabel: String?
    var isExpanded: Bool
    var title: String
    var bodyText: String?
    var insightTitle: String?
    var insightBody: String?
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left Time Column
            VStack(spacing: 8) {
                if let dateLabel = dateLabel {
                    Text(dateLabel)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(hex: "#1E3659"))
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                }
                if let timeLabel = timeLabel {
                    Text(timeLabel)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: "#1E3659"))
                        .multilineTextAlignment(.center)
                        .padding(.top, dateLabel == nil ? 12 : 0)
                }
            }
            .frame(width: 65, alignment: .top)
            
            // Timeline Line
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Color(hex: "#7AA0C3"))
                    .frame(width: 4)
                
                Circle()
                    .fill(Color(hex: "#3FA9F5"))
                    .frame(width: 10, height: 10)
                    .offset(y: dateLabel != nil ? 54 : 14)
            }
            .frame(width: 24)
            .padding(.horizontal, 8)
            
            // Card Content
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: "#1E3659"))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(Color(hex: "#ADC0D3"))
                        .font(.system(size: 12, weight: .bold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, isExpanded ? 16 : 12)
                
                if isExpanded {
                    if let bodyText = bodyText {
                        Text(bodyText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "#1E3659"))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }
                    
                    if let insightBody = insightBody {
                        VStack(alignment: .leading, spacing: 4) {
                            if let insightTitle = insightTitle {
                                Text(insightTitle)
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(Color(hex: "#1E3659"))
                            }
                            Text(insightBody)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: "#1E3659"))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: "#C4D7EA"))
                    }
                }
            }
            .background(Color(hex: "#E8F3FF"))
            .cornerRadius(12)
            .padding(.top, dateLabel != nil ? 40 : 0)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
}
